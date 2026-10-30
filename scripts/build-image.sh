#!/bin/bash
# Build an Ubuntu 26.10 SD-card image for Orange Pi 5 (needs root for mmdebstrap/chroot)
# Usage: build-image.sh [--variant server|desktop] [--reuse-rootfs]
#          --reuse-rootfs     reuse build/image[-desktop]/rootfs from a previous run
#        build-image.sh [--variant ...] --rootfs-tar FILE
#          rootless (mmdebstrap --mode=unshare): only build the root filesystem, as a
#          tarball, to check that the package set resolves and the hooks run
# IMAGE_VARIANT=desktop in the environment works too. Both variants need
# out/debs-media from scripts/build-media-debs.sh (rootless, run it first).
set -euo pipefail
VARIANT=${IMAGE_VARIANT:-server} REUSE_ROOTFS=0 ROOTFS_TAR=
args=("$@")
while [ $# -gt 0 ]; do
  case $1 in
    --variant) VARIANT=${2:?--variant needs server or desktop}; shift 2 ;;
    --variant=*) VARIANT=${1#*=}; shift ;;
    --reuse-rootfs) REUSE_ROOTFS=1; shift ;;
    --rootfs-tar) ROOTFS_TAR=$(realpath -m "${2:?--rootfs-tar needs a file name}"); shift 2 ;;
    *) echo "unknown option: $1"; exit 1 ;;
  esac
done
case $VARIANT in server|desktop) ;; *) echo "unknown variant: $VARIANT"; exit 1 ;; esac
# sudo drops the environment, so pass the variant on as an option
[ -n "$ROOTFS_TAR" ] || [ "$(id -u)" -eq 0 ] || exec sudo "$0" --variant "$VARIANT" "${args[@]}"
TOP=$(cd "$(dirname "$0")/.." && pwd)
if [ "$VARIANT" = server ]; then WORK=$TOP/build/image; else WORK=$TOP/build/image-$VARIANT; fi
[ -z "$ROOTFS_TAR" ] || WORK=$TOP/build/rootfs-tar-$VARIANT
OUT=$TOP/out
ROOT=$WORK/rootfs
SUITE=stonking
MIRROR=http://ports.ubuntu.com/ubuntu-ports
COMPONENTS="main restricted universe multiverse"
IMG=$OUT/ubuntu-26.10-$VARIANT-orangepi5.img
PKGS=(
  ubuntu-minimal ubuntu-server-minimal ubuntu-standard
  openssh-server initramfs-tools u-boot-menu cloud-init cloud-guest-utils
  unattended-upgrades ca-certificates bash-completion nano htop
  mtd-utils nvme-cli gdisk rsync needrestart zstd
  # Toolchain so DKMS can build out-of-tree modules against linux-headers
  build-essential dkms
  # ubuntu-standard's Recommends (installed without recommends above), minus desktop/grub bits
  apparmor command-not-found ethtool iptables iputils-tracepath manpages mtr-tiny
  openssh-client sysstat tcpdump telnet trace-cmd ufw update-manager-core uuid-runtime
  # Firmware: GPU (Mali CSF), common USB Wi-Fi/BT/ethernet dongles
  linux-firmware-misc linux-firmware-realtek linux-firmware-mediatek wireless-regdb
  # Media/board test tools: V4L2 codecs (v4l2-ctl, v4l2-compliance, GStreamer
  # v4l2codecs, FFmpeg v4l2-request, fluster conformance), NPU (Teflon), I2C, EDID
  v4l-utils gstreamer1.0-tools gstreamer1.0-plugins-base gstreamer1.0-plugins-good
  gstreamer1.0-plugins-bad ffmpeg fluster mesa-teflon-delegate i2c-tools edid-decode
  # Sound: ALSA tools (aplay, speaker-test, alsactl and the udev rule that applies
  # the UCM boot defaults), UCM profiles, and GStreamer's alsasink
  alsa-utils alsa-ucm-conf gstreamer1.0-alsa
)
# Desktop: Ubuntu's GNOME desktop seed, installed with its Recommends as Ubuntu
# Desktop is (except scripts/desktop-exclude.pref), plus video playback
DESKTOP_PKGS=(
  ubuntu-desktop-minimal
  # GPU: Mesa panthor (GL/GLES/EGL) and panvk (Vulkan), and test tools
  libgl1-mesa-dri libegl-mesa0 mesa-vulkan-drivers mesa-utils vulkan-tools
  kmscube libdrm-tests glmark2-es2-wayland
  # Players: GNOME's Showtime (GStreamer) and mpv; GStreamer decoders, GL and
  # GTK 4 dmabuf sinks; v4l2codecs (in plugins-bad) outranks the software decoders
  showtime mpv gstreamer1.0-libav gstreamer1.0-plugins-ugly gstreamer1.0-gl
  gstreamer1.0-gtk4 gstreamer1.0-dav1d gstreamer1.0-pipewire gstreamer1.0-alsa
  gstreamer1.0-plugins-base-apps
  # Jellyfin MPV Shim's dependencies that Ubuntu packages (the shim itself and two
  # small libraries are pinned wheels: scripts/jellyfin-mpv-shim.wheels)
  python3-venv python3-mpv python3-requests python3-urllib3 python3-websocket
  python3-certifi python3-pil python3-pystray python3-gi gir1.2-ayatanaappindicator3-0.1
  wl-clipboard
  # VA-API over the V4L2 stateless decoders (our libva-v4l2-request build, in
  # out/debs-media) for browsers and other VA clients; Firefox from Mozilla's
  # repository and Google Chrome from Google's (flags: work/_out/desktop-image/RESULTS.md)
  v4l2-request-va-driver vainfo firefox google-chrome-stable
)
RECOMMENDS=false
if [ "$VARIANT" = desktop ]; then
  PKGS+=("${DESKTOP_PKGS[@]}")
  RECOMMENDS=true
fi

shopt -s nullglob
debs=("$OUT"/debs/linux-image-*.deb)
[ ${#debs[@]} -eq 1 ] || { echo "expected exactly one linux-image deb in $OUT/debs"; exit 1; }
hdrs=("$OUT"/debs/linux-headers-*.deb)
[ ${#hdrs[@]} -eq 1 ] || { echo "expected exactly one linux-headers deb in $OUT/debs"; exit 1; }
for f in u-boot-rockchip.bin u-boot-rockchip-spi.bin; do
  [ -f "$OUT/$f" ] || { echo "missing $OUT/$f (run scripts/build-uboot.sh)"; exit 1; }
done

# Extra mmdebstrap options per mode and variant
MODE=root
EXTRA=() POST=() SOURCES=()
# The hooks read scripts, overlay and out/ from $TOP. In unshare mode they run as
# a subordinate uid that can't read $HOME, so a copy goes into the chroot.
HT="'$TOP'"
if [ -n "$ROOTFS_TAR" ]; then
  MODE=unshare
  rm -rf "$WORK"; mkdir -p "$WORK"
  S=$WORK/opi5-top
  mkdir -p "$S/scripts" "$S/out/debs"
  cp -a "$TOP/scripts/customize-rootfs.sh" "$TOP/scripts/customize-desktop.sh" \
    "$TOP/scripts/jellyfin-mpv-shim.wheels" "$S/scripts/"
  cp -a "$TOP/overlay" "$TOP/overlay-desktop" "$S/"
  cp -a "${debs[0]}" "${hdrs[0]}" "$S/out/debs/"
  cp -a "$OUT/u-boot-rockchip.bin" "$OUT/u-boot-rockchip-spi.bin" "$S/out/"
  EXTRA+=(--setup-hook='mkdir -p "$1/tmp"' --setup-hook="copy-in '$S' /tmp")
  HT='"$1/tmp/opi5-top"'
  POST+=(--customize-hook='rm -rf "$1/tmp/opi5-top"')
fi
# Local repository with our rebuilds of FFmpeg, mpv and GStreamer (V4L2 stateless
# decoding fixes; they sort above the archive versions, and overlay/ pins them).
# apt reads it at the same path outside (mmdebstrap) and inside the chroot, from
# a world-readable copy (see build-media-debs.sh).
need=(ffmpeg gstreamer1.0-plugins-bad)
[ "$VARIANT" = desktop ] && need+=(mpv v4l2-request-va-driver)
for p in "${need[@]}"; do
  ls "$OUT"/debs-media/"${p}"_*+opi5*.deb >/dev/null 2>&1 ||
    { echo "missing the $p rebuild in $OUT/debs-media (run scripts/build-media-debs.sh)"; exit 1; }
done
MEDIA=$(mktemp -d /tmp/opi5-media-repo.XXXXXX)
trap 'rm -rf "$MEDIA"' EXIT
cp "$OUT"/debs-media/*.deb "$OUT"/debs-media/Packages "$MEDIA/"
chmod -R a+rX "$MEDIA"
EXTRA+=(--setup-hook='mkdir -p "$1/tmp"' --setup-hook="copy-in '$MEDIA' /tmp")
POST+=(--customize-hook="rm -rf \"\$1$MEDIA\"")
SOURCES+=("deb [trusted=yes] file://$MEDIA ./")
if [ "$VARIANT" = desktop ]; then
  EXTRA+=(--setup-hook='mkdir -p "$1/etc/apt/preferences.d"'
    --setup-hook="upload '$TOP/scripts/desktop-exclude.pref' /etc/apt/preferences.d/opi5-desktop-exclude.pref"
    --setup-hook="upload '$TOP/overlay-desktop/etc/apt/preferences.d/mozilla.pref' /etc/apt/preferences.d/mozilla.pref"
    --customize-hook="$HT/scripts/customize-desktop.sh \"\$1\" $HT")
  POST+=(--customize-hook='rm -f "$1/etc/apt/preferences.d/opi5-desktop-exclude.pref"')
  # Third-party repositories (mmdebstrap copies these into sources.list.d as NNNN<name>;
  # customize-desktop.sh replaces them with the image's own definitions)
  SOURCES+=("$TOP/overlay-desktop/etc/apt/sources.list.d/mozilla.sources" "$TOP/scripts/google-chrome.sources")
fi

# An interrupted run can leave /dev, /proc, /sys bind-mounted in the old rootfs
if findmnt -rno TARGET | grep -q "^$WORK/"; then
  echo "mounts still active under $WORK; unmount them (findmnt | grep $WORK) and retry"; exit 1
fi
if [ "$REUSE_ROOTFS" = 1 ]; then
  [ -f "$WORK/.rootfs-done" ] || [ -f "$ROOT/boot/extlinux/extlinux.conf" ] || { echo "no completed rootfs in $ROOT"; exit 1; }
  rm -f "$WORK"/*.ext4 "$WORK"/*.vfat
else
[ -n "$ROOTFS_TAR" ] || { rm -rf "$WORK"; mkdir -p "$ROOT"; }
TARGET=$ROOT
[ -z "$ROOTFS_TAR" ] || TARGET=$ROOTFS_TAR
# man-db index rebuilds and per-package fsyncs are the slowest parts under qemu
mmdebstrap --mode=$MODE --arch=arm64 --variant=apt \
  --keyring=/usr/share/keyrings/ubuntu-archive-keyring.gpg \
  --aptopt="APT::Install-Recommends \"$RECOMMENDS\"" \
  --dpkgopt=force-unsafe-io \
  --essential-hook='if [ -x "$1/usr/bin/debconf-set-selections" ]; then echo "man-db man-db/auto-update boolean false" | chroot "$1" debconf-set-selections; fi' \
  --include="$(IFS=,; echo "${PKGS[*]}")" \
  "${EXTRA[@]}" \
  --customize-hook="$HT/scripts/customize-rootfs.sh \"\$1\" $HT" \
  "${POST[@]}" \
  "$SUITE" "$TARGET" \
  "deb $MIRROR $SUITE $COMPONENTS" \
  "deb $MIRROR $SUITE-updates $COMPONENTS" \
  "deb $MIRROR $SUITE-security $COMPONENTS" \
  "${SOURCES[@]}"
if [ -n "$ROOTFS_TAR" ]; then
  rm -rf "$WORK"
  ls -lh "$ROOTFS_TAR"
  exit 0
fi
touch "$WORK/.rootfs-done"
fi

# Never copy (or later rm -rf) a rootfs with host filesystems still mounted in it
if findmnt -rno TARGET | grep -q "^$ROOT/"; then
  echo "filesystems still mounted under $ROOT:"; findmnt -rno TARGET | grep "^$ROOT/"; exit 1
fi

# Root filesystem sized to content + headroom; cloud-init grows it to the card on first boot
used=$(du -sm "$ROOT" | cut -f1)
fs_mb=$(( (used * 13 / 10 + 512 + 63) / 64 * 64 ))
mkfs.ext4 -q -F -L rootfs -d "$ROOT" "$WORK/rootfs.ext4" "${fs_mb}M"

# cloud-init NoCloud seed on a small FAT partition, editable from any OS
CIDATA_MB=64
mkfs.vfat -n CIDATA -C "$WORK/cidata.vfat" $(( CIDATA_MB * 1024 )) >/dev/null
mkdir -p "$WORK/cidata"
mount -o loop "$WORK/cidata.vfat" "$WORK/cidata"
cp "$TOP/cidata/meta-data" "$TOP/cidata/network-config" "$WORK/cidata/"
# cidata/user-data is your local copy (ignored by git: it may hold keys);
# without one the image gets the example (user ubuntu, password ubuntu, must
# be changed at first login)
if [ -f "$TOP/cidata/user-data" ]; then
  cp "$TOP/cidata/user-data" "$WORK/cidata/user-data"
else
  echo "NOTE: no cidata/user-data, using cidata/user-data.example (ubuntu/ubuntu, expires at first login)"
  cp "$TOP/cidata/user-data.example" "$WORK/cidata/user-data"
fi
umount "$WORK/cidata"

# Layout: GPT | U-Boot @ sector 64 (32 KiB) | CIDATA @ 16 MiB | rootfs (last, grown on first boot)
rm -f "$IMG" "$IMG.xz"
truncate -s $(( 16 + CIDATA_MB + fs_mb + 1 ))M "$IMG"
sfdisk -q "$IMG" <<SFDISK
label: gpt
start=32768, size=$(( CIDATA_MB * 2048 )), type=EBD0A0A2-B9E5-4433-87C0-68B6B72699C7, name="CIDATA"
start=$(( (16 + CIDATA_MB) * 2048 )), size=$(( fs_mb * 2048 )), type=0FC63DAF-8483-4772-8E79-3D69D8477DE4, name="rootfs", attrs="LegacyBIOSBootable"
SFDISK
dd if="$WORK/cidata.vfat" of="$IMG" bs=1M seek=16 conv=notrunc status=none
dd if="$WORK/rootfs.ext4" of="$IMG" bs=1M seek=$(( 16 + CIDATA_MB )) conv=notrunc,sparse status=none
dd if="$OUT/u-boot-rockchip.bin" of="$IMG" bs=512 seek=64 conv=notrunc status=none

xz -T0 -6 -k -f "$IMG"
(cd "$OUT" && sha256sum "$(basename "$IMG").xz" > "$(basename "$IMG").xz.sha256")
[ -n "${SUDO_UID:-}" ] && chown "$SUDO_UID:$SUDO_GID" "$IMG" "$IMG.xz" "$IMG.xz.sha256"
rm -rf "$WORK"
ls -lh "$IMG" "$IMG.xz"
