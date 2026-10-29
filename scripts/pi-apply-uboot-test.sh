#!/bin/bash
# Runs ON the Orange Pi: put a test U-Boot on the SD card (not SPI) and switch
# the Linux serial console to 115200 to match it.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || exec sudo "$0" "$@"
D=$(cd "$(dirname "$0")" && pwd)
BIN=$D/u-boot-rockchip.bin

sed -i 's/console=ttyS2,1500000/console=ttyS2,115200/' /etc/default/u-boot
u-boot-update
grep -m1 'append' /boot/extlinux/extlinux.conf

root=$(findmnt -no SOURCE /)
sd=/dev/$(lsblk -no PKNAME "$root")
[[ $sd == /dev/mmcblk* ]] || { echo "root isn't on the SD card ($root); not writing U-Boot"; exit 1; }
first=$(sfdisk -d "$sd" | awk -F'[=,]' '/start=/{gsub(/ /,"",$2); print $2; exit}')
need=$(( 64 + ($(stat -c %s "$BIN") + 511) / 512 ))
[ "$first" -ge "$need" ] || { echo "U-Boot would overlap partition 1 on $sd"; exit 1; }
dd if="$BIN" of="$sd" bs=512 seek=64 conv=fsync,notrunc status=none
cmp -n "$(stat -c %s "$BIN")" -i 0:32768 "$BIN" "$sd" && echo "Test U-Boot written to $sd and verified."
echo "Reboot when the serial logger is running: sudo reboot"
