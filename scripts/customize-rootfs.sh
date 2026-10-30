#!/bin/bash
# mmdebstrap customize hook: board config, kernel install, first-boot cleanup
set -euo pipefail
R=$1 TOP=$2

rsync -rlt --chown=root:root --chmod=D755,F644 "$TOP/overlay/" "$R/"
# Overlay programs (rsync above made every file 0644)
find "$R/usr/local/sbin" "$R/usr/local/bin" -maxdepth 1 -type f -exec chmod 755 {} +
rm -f "$R/etc/apt/sources.list"
echo orangepi5 > "$R/etc/hostname"
printf '127.0.0.1\tlocalhost\n127.0.1.1\torangepi5\n::1\tlocalhost ip6-localhost ip6-loopback\nff02::1\tip6-allnodes\nff02::2\tip6-allrouters\n' > "$R/etc/hosts"
echo 'LANG=C.UTF-8' > "$R/etc/default/locale"
install -Dm644 -t "$R/usr/lib/u-boot/orangepi5/" "$TOP/out/u-boot-rockchip.bin" "$TOP/out/u-boot-rockchip-spi.bin"

# Kernel + headers (for DKMS): postinst hooks build the initramfs and extlinux.conf (u-boot-menu)
cp "$TOP"/out/debs/linux-image-*.deb "$TOP"/out/debs/linux-headers-*.deb "$R/tmp/"
chroot "$R" sh -c 'dpkg -i /tmp/linux-image-*.deb /tmp/linux-headers-*.deb'
rm -f "$R"/tmp/linux-image-*.deb "$R"/tmp/linux-headers-*.deb
# fdtdir: U-Boot picks rk3588s-orangepi-5{,-sata}.dtb from it (M.2 auto-detect)
grep -q 'fdtdir /usr/lib/linux-image-' "$R/boot/extlinux/extlinux.conf" || { echo "extlinux.conf missing fdtdir"; exit 1; }
for dtb in rk3588s-orangepi-5.dtb rk3588s-orangepi-5-sata.dtb; do
  ls "$R"/usr/lib/linux-image-*/rockchip/$dtb >/dev/null || { echo "missing $dtb"; exit 1; }
done
ls "$R"/boot/initrd.img-* >/dev/null

# Per-machine state regenerated on first boot (cloud-init/systemd)
rm -f "$R"/etc/ssh/ssh_host_*
: > "$R/etc/machine-id"
rm -f "$R/var/lib/dbus/machine-id" "$R/etc/apt/apt.conf.d/99mmdebstrap"
chroot "$R" apt-get clean
# Re-enable man-db index updates (disabled during the build for speed)
echo "man-db man-db/auto-update boolean true" | chroot "$R" debconf-set-selections
touch "$R/var/lib/man-db/auto-update"

# mmdebstrap bind-mounts the host's /sys, including efivarfs on UEFI hosts; that
# submount makes mmdebstrap's own "umount /sys" fail with "target is busy".
# (Root mode only: in unshare mode the inherited submount is locked and
# mmdebstrap detaches /sys itself.)
if [ "${MMDEBSTRAP_MODE:-root}" = root ] && mountpoint -q "$R/sys/firmware/efi/efivars"; then
  umount "$R/sys/firmware/efi/efivars"
fi
