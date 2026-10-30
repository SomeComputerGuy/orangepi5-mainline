#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# ONE-TIME, DESTRUCTIVE: wipe the two user-approved scratch disks and make one ext4 partition on each.
# DONE 2026-10-30 05:37; do not re-run. Current scratch disks (mount by LABEL only, sdX names change on every replug):
#   LABEL            mount             device                                   port
#   OPI5SCRATCH-SD   /mnt/scratch-sd   Transcend SD reader + 119.3 GiB SD card   dock hub 8-1.1 (USB3)
#   OPI5SCRATCH-USB  /mnt/scratch-usb  SanDisk Ultra Fit 114.6 GiB (0781:5583)   dock hub 8-1.2 (USB3, moved there by the user)
#   OPI5SCRATCH-EXT  /mnt/scratch-ext  SanDisk Extreme 58 GB (0781:5580)         board top USB3 port 6-1 (wiped by the user, not this script)
# The identity patterns below are the ones used for the 05:37 run (Ultra Fit then on a board port).
#   scratch-setup.sh            (approved by the user 2026-10-30: Transcend SD 119.3 GB on the dongle hub 8-1.1,
#                                SanDisk Ultra Fit 114.6 GB on the board USB3 port)
# The disks are found by transport path + model + size, NOT by sdX name, and the script refuses anything else
# (root disk, mounted partitions, unexpected size). Mounts at /mnt/scratch-sd and /mnt/scratch-usb.
set -euo pipefail
pick() {  # pick <usb path pattern> <model regex> <min GB> <max GB>
  for d in /sys/block/sd*; do
    local n=$(basename $d) p=$(readlink -f $d) m=$(cat $d/device/model 2>/dev/null | xargs) sz=$(( $(cat $d/size) * 512 / 1000000000 ))
    echo "$p" | grep -qE "$1" && echo "$m" | grep -qiE "$2" && [ $sz -ge $3 ] && [ $sz -le $4 ] && { echo /dev/$n; return; }
  done; }
SD=$(pick '/8-1\.1[:/.]' 'transcend|card|reader|sd' 120 135 || true)   # decimal GB (119.3 GiB = 128 GB)
USB=$(pick '(fc880000|fc800000|fcd00000)\.usb/' 'sandisk|ultra|fit' 115 130 || true)   # a board port (EHCI or xHCI), not the dongle
ROOT=$(lsblk -no PKNAME $(findmnt -no SOURCE /))
for v in SD USB; do
  d=${!v}; [ -n "$d" ] || { echo "no $v disk found (expected identity not matched) - refusing"; lsblk -o NAME,SIZE,MODEL,TRAN,MOUNTPOINTS; exit 1; }
  [ "$(basename $d)" != "$ROOT" ] || { echo "$d is the root disk - refusing"; exit 1; }
  findmnt -rno SOURCE | grep -q "^$d" && { echo "$d has mounted partitions - refusing"; exit 1; }
  echo "$v -> $d ($(cat /sys/block/$(basename $d)/device/model | xargs), $(lsblk -dno SIZE $d))"
done
mk() {  # mk <disk> <label> <mountpoint>
  sudo wipefs -a $1
  echo ',,L' | sudo sfdisk -q --label gpt $1
  sudo partprobe $1; sleep 2
  local p=${1}1; sudo mkfs.ext4 -q -F -L $2 -E lazy_itable_init=0,lazy_journal_init=0 $p
  sudo mkdir -p $3; sudo mount -o noatime LABEL=$2 $3; sudo chown $(id -u):$(id -g) $3
  echo "$2: $(findmnt -no SOURCE,SIZE,FSTYPE $3)"
}
mk $SD OPI5SCRATCH-SD /mnt/scratch-sd
mk $USB OPI5SCRATCH-USB /mnt/scratch-usb
