#!/bin/bash
# Runs ON the Orange Pi (copied there by pi-update.sh): install the new kernel,
# boot config, helper scripts and U-Boot files, and put the new U-Boot on the
# SD card (where it's easy to recover) for testing before it goes to SPI flash.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || exec sudo "$0" "$@"
D=$(cd "$(dirname "$0")" && pwd)

echo "==> Removing interim drop-in modules (the kernel package has them now)"
# updates/ takes precedence over the package's modules for the same release
for d in /lib/modules/*/updates/opi5-*; do
  if [ -d "$d" ]; then
    rm -r "$d"
    kver=${d#/lib/modules/}; depmod -a "${kver%%/*}"
  fi
done

echo "==> Kernel packages"
dpkg -i "$D"/linux-image-*.deb "$D"/linux-headers-*.deb

echo "==> Boot config (fdtdir + U-Boot M.2 auto-detect)"
install -m644 "$D/u-boot.default" /etc/default/u-boot
u-boot-update
grep -E '^\s*(linux|fdt|fdtdir|append)' /boot/extlinux/extlinux.conf | head -4

echo "==> Helper scripts and U-Boot images"
install -m755 "$D/opi5-install-ssd" /usr/local/sbin/
rm -f /usr/local/sbin/opi5-install-nvme
install -Dm644 -t /usr/lib/u-boot/orangepi5/ "$D/u-boot-rockchip.bin" "$D/u-boot-rockchip-spi.bin"

echo "==> U-Boot to SD card"
root=$(findmnt -no SOURCE /)
sd=/dev/$(lsblk -no PKNAME "$root")
[[ $sd == /dev/mmcblk* ]] || { echo "root isn't on the SD card ($root); not writing U-Boot"; exit 1; }
first=$(sfdisk -d "$sd" | awk -F'[=,]' '/start=/{gsub(/ /,"",$2); print $2; exit}')
need=$(( 64 + ($(stat -c %s "$D/u-boot-rockchip.bin") + 511) / 512 ))
[ "$first" -ge "$need" ] || { echo "U-Boot would overlap partition 1 on $sd"; exit 1; }
dd if="$D/u-boot-rockchip.bin" of="$sd" bs=512 seek=64 conv=fsync,notrunc status=none
cmp -n "$(stat -c %s "$D/u-boot-rockchip.bin")" -i 0:32768 "$D/u-boot-rockchip.bin" "$sd" && echo "U-Boot written to $sd and verified"

echo
echo "Done. Reboot to test: sudo reboot"
