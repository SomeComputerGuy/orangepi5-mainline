#!/bin/bash
# Recovery: rewrite only the bootloader on an SD card (partitions untouched).
# Usage: flash-uboot-sd.sh /dev/sdX [u-boot-rockchip.bin]
set -euo pipefail
[ "$(id -u)" -eq 0 ] || exec sudo "$0" "$@"
TOP=$(cd "$(dirname "$0")/.." && pwd)
DEV=${1:?usage: $0 /dev/sdX [u-boot-rockchip.bin]}
BIN=${2:-$TOP/out/u-boot-rockchip.bin}
[ "$(lsblk -dno RM "$DEV" | tr -d ' ')" = 1 ] || { echo "$DEV is not removable; refusing"; exit 1; }
lsblk -o NAME,SIZE,LABEL,MODEL "$DEV"
read -rp "Write $(basename "$BIN") to $DEV at sector 64? Type the device name to confirm: " ok
[ "$ok" = "$DEV" ] || exit 1
dd if="$BIN" of="$DEV" bs=512 seek=64 conv=fsync,notrunc status=none
cmp -n "$(stat -c %s "$BIN")" -i 0:32768 "$BIN" "$DEV" && echo "Written and verified."
