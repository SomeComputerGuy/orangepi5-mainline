#!/bin/bash
# Build an Ubuntu 26.10 server SD-card image for Orange Pi 5 (needs root for mmdebstrap/chroot)
# Usage: build-image.sh [--reuse-rootfs]   (reuse build/image/rootfs from a previous run)
set -euo pipefail
[ "$(id -u)" -eq 0 ] || exec sudo "$0" "$@"
REUSE_ROOTFS=0
[ "${1:-}" = --reuse-rootfs ] && REUSE_ROOTFS=1
TOP=$(cd "$(dirname "$0")/.." && pwd)
OUT=$TOP/out WORK=$TOP/build/image
ROOT=$WORK/rootfs
SUITE=stonking
MIRROR=http://ports.ubuntu.com/ubuntu-ports
COMPONENTS="main restricted universe multiverse"
IMG=$OUT/ubuntu-26.10-server-orangepi5.img
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
)

shopt -s nullglob
debs=("$OUT"/debs/linux-image-*.deb)
[ ${#debs[@]} -eq 1 ] || { echo "expected exactly one linux-image deb in $OUT/debs"; exit 1; }
hdrs=("$OUT"/debs/linux-headers-*.deb)
[ ${#hdrs[@]} -eq 1 ] || { echo "expected exactly one linux-headers deb in $OUT/debs"; exit 1; }
for f in u-boot-rockchip.bin u-boot-rockchip-spi.bin; do
  [ -f "$OUT/$f" ] || { echo "missing $OUT/$f (run scripts/build-uboot.sh)"; exit 1; }
done

# An interrupted run can leave /dev, /proc, /sys bind-mounted in the old rootfs
if findmnt -rno TARGET | grep -q "^$WORK/"; then
  echo "mounts still active under $WORK; unmount them (findmnt | grep $WORK) and retry"; exit 1
fi
if [ "$REUSE_ROOTFS" = 1 ]; then
  [ -f "$WORK/.rootfs-done" ] || [ -f "$ROOT/boot/extlinux/extlinux.conf" ] || { echo "no completed rootfs in $ROOT"; exit 1; }
  rm -f "$WORK"/*.ext4 "$WORK"/*.vfat
else
rm -rf "$WORK"; mkdir -p "$ROOT"
# man-db index rebuilds and per-package fsyncs are the slowest parts under qemu
mmdebstrap --mode=root --arch=arm64 --variant=apt \
  --keyring=/usr/share/keyrings/ubuntu-archive-keyring.gpg \
  --aptopt='APT::Install-Recommends "false"' \
  --dpkgopt=force-unsafe-io \
  --essential-hook='if [ -x "$1/usr/bin/debconf-set-selections" ]; then echo "man-db man-db/auto-update boolean false" | chroot "$1" debconf-set-selections; fi' \
  --include="$(IFS=,; echo "${PKGS[*]}")" \
  --customize-hook="'$TOP/scripts/customize-rootfs.sh' \"\$1\" '$TOP'" \
  "$SUITE" "$ROOT" \
  "deb $MIRROR $SUITE $COMPONENTS" \
  "deb $MIRROR $SUITE-updates $COMPONENTS" \
  "deb $MIRROR $SUITE-security $COMPONENTS"
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
