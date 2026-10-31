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
# The signed media repository is made as the invoking user, whose home holds the
# repository signing key (scripts/make-media-repo.sh), before switching to root
[ "$(id -u)" -eq 0 ] || "$(dirname "$0")/make-media-repo.sh"
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
# Every package below is either part of Ubuntu's own seed for the variant or board
# enablement; the reason for each is in work/_out/desktop-image/RESULTS.md ("What the
# image contains"). Test tools are not installed: the board tests install what they need.
PKGS=(
  ubuntu-minimal ubuntu-server-minimal ubuntu-standard
  openssh-server initramfs-tools u-boot-menu cloud-init cloud-guest-utils
  unattended-upgrades ca-certificates bash-completion nano htop
  nvme-cli gdisk rsync needrestart zstd
  # ubuntu-standard's Recommends (installed without recommends above), minus desktop/grub bits
  apparmor command-not-found ethtool iptables iputils-tracepath manpages mtr-tiny
  openssh-client sysstat tcpdump telnet trace-cmd ufw update-manager-core uuid-runtime
  # Firmware: GPU (Mali CSF), common USB Wi-Fi/BT/ethernet dongles
  linux-firmware-misc linux-firmware-realtek linux-firmware-mediatek wireless-regdb
  # Sound: the board's UCM profiles (our alsa-ucm-conf rebuild, patches/alsa-ucm-conf)
  # and alsa-utils, whose udev rule (alsactl) applies their boot defaults: without
  # it the ES8388 jack starts at -96 dB. The desktop seed has both anyway.
  alsa-ucm-conf alsa-utils
)
# Desktop: Ubuntu Desktop as Ubuntu preinstalls it on boards (the Raspberry Pi desktop
# image is ubuntu-desktop with its Recommends; scripts/desktop-exclude.pref leaves out
# only what can't work here), plus the hardware-decode enablement:
DESKTOP_PKGS=(
  ubuntu-desktop
  # VA-API driver over the V4L2 stateless decoders (our libva-v4l2-request build), the
  # VA-API counterpart of mesa-va-drivers on PCs: browsers and other VA clients
  v4l2-request-va-driver
  # GStreamer's v4l2codecs decoders (our gst-plugins-bad rebuild): hardware decoding
  # in Showtime and other GStreamer players
  gstreamer1.0-plugins-bad
  # Firefox from Mozilla's repository: Ubuntu's is a snap, which can't load a system
  # VA-API driver (overlay-desktop/etc/apt/sources.list.d/mozilla.sources)
  firefox
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
  cp -a "$TOP/scripts/customize-rootfs.sh" "$TOP/scripts/customize-desktop.sh" "$S/scripts/"
  cp -a "$TOP/overlay" "$TOP/overlay-desktop" "$S/"
  cp -a "${debs[0]}" "${hdrs[0]}" "$S/out/debs/"
  cp -a "$OUT/u-boot-rockchip.bin" "$OUT/u-boot-rockchip-spi.bin" "$OUT/debs-media" "$S/out/"
  EXTRA+=(--setup-hook='mkdir -p "$1/tmp"' --setup-hook="copy-in '$S' /tmp")
  HT='"$1/tmp/opi5-top"'
  POST+=(--customize-hook='rm -rf "$1/tmp/opi5-top"')
fi
# Local repository with our rebuilds (out/debs-media: FFmpeg, mpv, GStreamer,
# alsa-ucm-conf, the VA-API driver; they sort above the archive versions, and
# overlay/ pins them). apt reads it at the same path outside (mmdebstrap) and
# inside the chroot, from a world-readable copy (see build-media-debs.sh).
# Both variants get the same repository, which customize-rootfs.sh also keeps in
# the image as an apt source, so packages from these sources that aren't
# preinstalled (mpv, ffmpeg, libmpv2 for a Jellyfin client, ...) install as our builds.
need=(ffmpeg libmpv2 gstreamer1.0-plugins-bad gstreamer1.0-plugins-good v4l2-request-va-driver alsa-ucm-conf)
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
  # Mozilla's repository (mmdebstrap copies it into sources.list.d as NNNNmozilla.sources;
  # customize-desktop.sh replaces it with the overlay's copy)
  SOURCES+=("$TOP/overlay-desktop/etc/apt/sources.list.d/mozilla.sources")
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
