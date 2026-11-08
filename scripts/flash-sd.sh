#!/bin/bash
# Write the Orange Pi 5 image to an SD card: scripts/flash-sd.sh /dev/sdX [server|desktop]
set -euo pipefail
[ "$(id -u)" -eq 0 ] || exec sudo "$0" "$@"
TOP=$(cd "$(dirname "$0")/.." && pwd)
DEV=${1:?usage: $0 /dev/sdX [server|desktop]}
VARIANT=${2:-server}
case $VARIANT in server|desktop) ;; *) echo "unknown variant: $VARIANT"; exit 1 ;; esac
IMG=$TOP/out/ubuntu-26.10-$VARIANT-orangepi5.img

[ -b "$DEV" ] || { echo "$DEV is not a block device"; exit 1; }
[ "$(lsblk -dno TYPE "$DEV")" = disk ] || { echo "$DEV is not a whole disk"; exit 1; }
[ "$(lsblk -dno RM "$DEV" | tr -d ' ')" = 1 ] || { echo "$DEV is not removable; refusing"; exit 1; }
if lsblk -no MOUNTPOINTS "$DEV" | grep -q .; then
  echo "$DEV has mounted partitions; unmount them first"; exit 1
fi
[ -f "$IMG" ] || { echo "missing $IMG (run scripts/build-image.sh --variant $VARIANT)"; exit 1; }

lsblk -o NAME,SIZE,TRAN,MODEL "$DEV"
read -rp "ERASE $DEV and write $(basename "$IMG")? Type the device name ($DEV) to confirm: " ok
[ "$ok" = "$DEV" ] || { echo "aborted"; exit 1; }

wipefs -a "$DEV"
dd if="$IMG" of="$DEV" bs=4M conv=fsync oflag=direct status=progress
sync
# Verify: compare the written bytes against the image
echo "Verifying..."
cmp -n "$(stat -c %s "$IMG")" "$IMG" "$DEV" && echo "Verify OK"
partprobe "$DEV" 2>/dev/null || true
lsblk -o NAME,SIZE,LABEL,PARTLABEL "$DEV"
echo "Done. Eject the card and put it in the Orange Pi 5."
