#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Storage copy aggregator over three scratch disks, sha256-verified, survives yanks. Mounted by LABEL, never sdX:
#   OPI5SCRATCH-SD  /mnt/scratch-sd   Transcend SD reader on the dock hub (8-1.1)
#   OPI5SCRATCH-USB /mnt/scratch-usb  SanDisk Ultra Fit, now on the dock hub (8-1.2)
#   OPI5SCRATCH-EXT /mnt/scratch-ext  SanDisk Extreme 0781:5580 on the board's top USB3 port (6-1)
#   copy-agg.sh <secs> [nfiles=4] [GiB per file=4]       log: ~/copyagg/copies.log, summary ~/copyagg/summary.txt
# Setup (once): nfiles random files per disk with their sha256 (sd/f*.bin, usb/g*.bin, ext/h*.bin).
# Four workers at the same time: a ring sd->usb (f), usb->ext (g), ext->sd (h), plus ext->usb (h), so ext<->usb
# runs in both directions. If EXT isn't mounted, it falls back to sd<->usb (f, g). Each copy: dd with
# conv=fsync (O_DIRECT reads), then sha256 of the destination read back with O_DIRECT (from the media, not the page
# cache), then compare with the reference. A mismatch is DATA CORRUPTION (logged as CORRUPT, kept for analysis).
# An I/O error is logged; the worker then waits for the filesystem label to reappear, runs e2fsck -fy, remounts it,
# re-verifies every reference file there and continues. Every line: epoch dir file bytes secs MB/s result.
SECS=${1:?secs}; NF=${2:-4}; GB=${3:-4}
D=$HOME/copyagg; mkdir -p $D; LOG=$D/copies.log; EV=$D/events.log
SDM=/mnt/scratch-sd; USM=/mnt/scratch-usb; EXM=/mnt/scratch-ext
declare -A LBL=([$SDM]=OPI5SCRATCH-SD [$USM]=OPI5SCRATCH-USB [$EXM]=OPI5SCRATCH-EXT)
declare -A PFX=([$SDM]=f [$USM]=g [$EXM]=h)
END=$(( $(date +%s) + SECS ))
ev() { echo "$(date +%s.%N) $*" | tee -a $EV; }
mounted() {  # mounted, and writable for real (an ext4 that shut down after a yank stays mounted)
  mountpoint -q $1 && ! findmnt -no OPTIONS $1 | grep -qE '(^|,)(ro|emergency_ro|shutdown)(,|$)' && touch $1/.probe 2>/dev/null && rm -f $1/.probe; }
remount() {  # remount <mnt>: wait for the label, fsck (dry), mount
  local m=$1 l=${LBL[$1]}
  sudo umount -l $m 2>/dev/null; sleep 2
  for ((s=0; s<300; s++)); do [ -e /dev/disk/by-label/$l ] && [ -b "$(readlink -f /dev/disk/by-label/$l)" ] && break; sleep 1; [ $(date +%s) -ge $END ] && return 1; done
  [ -e /dev/disk/by-label/$l ] || return 1
  local dev=$(readlink -f /dev/disk/by-label/$l)
  sudo e2fsck -fy $dev > $D/fsck.$(date +%s).out 2>&1; local rc=$?
  ev "REAPPEARED $m $dev after ${s}s; e2fsck -fy exit $rc (0 clean, 1 fixed): $(grep -vE '^(Pass|e2fsck) ' $D/fsck.*.out | tail -4 | tr '\n' '|')"
  sudo mount -o noatime $dev $m && ev "REMOUNTED $m" || { ev "MOUNT FAILED $m"; return 1; }
  for f in $m/*.bin; do [ -f $f.sha256 ] || continue   # every reference file must still match its checksum
    local h=$(sha_direct $f); [ "$h" = "$(cat $f.sha256)" ] && ev "VERIFY ok $f" || { ev "VERIFY MISMATCH $f (recreating)"; rm -f $f $f.sha256; }
  done
  rm -f $m/*.tmp $m/*.copy; mkref $m ${PFX[$m]}
}
sha_direct() { dd if=$1 iflag=direct bs=4M status=none | sha256sum | cut -c1-64; }
mkref() {  # mkref <mnt> <prefix>
  for ((i=0; i<NF; i++)); do
    local f=$1/$2$i.bin
    [ -s $f ] && [ -s $f.sha256 ] && continue
    ev "creating $f (${GB} GiB)"
    openssl enc -aes-128-ctr -pass pass:opi5$2$i -nosalt -pbkdf2 < <(head -c $((GB<<30)) /dev/zero) 2>/dev/null | dd of=$f bs=4M oflag=direct status=none
    sha_direct $f > $f.sha256
  done; }
worker() {  # worker <src mnt> <dst mnt> <prefix> <label>
  local s=$1 d=$2 p=$3 n=$4 i=0
  while [ $(date +%s) -lt $END ]; do
    mounted $s && mounted $d || { mounted $s || remount $s; mounted $d || remount $d; continue; }
    local f=$p$((i % NF)).bin; i=$((i+1))
    local t0=$(date +%s.%N) res=ok
    if ! dd if=$s/$f of=$d/$f.tmp bs=4M iflag=direct conv=fsync status=none 2>>$D/$n.err; then
      res="IOERR($(tail -1 $D/$n.err | cut -c1-60))"; ev "$n IOERR copying $f"
      mounted $s || remount $s; mounted $d || remount $d
    else
      mv $d/$f.tmp $d/$f.copy; sync -f $d/$f.copy
      local h=$(sha_direct $d/$f.copy) r=$(cat $s/$f.sha256 2>/dev/null)
      if [ -z "$h" ] || [ "$h" = "$(echo -n | sha256sum | cut -c1-64)" ]; then res="IOERR(readback)"
      elif [ "$h" != "$r" ]; then res="CORRUPT sha=$h ref=$r"; ev "$n CORRUPT $f -> kept as $d/$f.corrupt.$i"; mv $d/$f.copy $d/$f.corrupt.$i
      fi
    fi
    local t1=$(date +%s.%N) b=$((GB<<30))
    echo "$t1 $n $f $b $(awk -v a=$t0 -v b=$t1 -v n=$b 'BEGIN{printf "%.1f %.1f", b-a, n/1048576/(b-a)}') $res" >> $LOG
    rm -f $d/$f.copy $d/$f.tmp 2>/dev/null
  done; }
for m in $SDM $USM; do mounted $m || remount $m || { echo "$m not available"; exit 1; }; done
EXT=1; mounted $EXM || remount $EXM || { EXT=0; ev "no $EXM: running sd<->usb only"; }
mkref $SDM f; mkref $USM g; [ $EXT = 1 ] && mkref $EXM h
ev "start: $NF x $GB GiB per disk, ${SECS}s, ext=$EXT"
WS=()
if [ $EXT = 1 ]; then
  worker $SDM $USM f sd2usb & WS+=($!)
  worker $USM $EXM g usb2ext & WS+=($!)
  worker $EXM $SDM h ext2sd & WS+=($!)
  worker $EXM $USM h ext2usb & WS+=($!)
else
  worker $SDM $USM f sd2usb & WS+=($!)
  worker $USM $SDM g usb2sd & WS+=($!)
fi
wait "${WS[@]}"
{ echo "# copy-agg $(date '+%F %T')"
  for n in sd2usb usb2sd usb2ext ext2sd ext2usb; do grep -q " $n " $LOG || continue; awk -v n=$n '$2==n{c++; s+=$5; t+=$4; if($7=="ok")ok++; else if($7 ~ /^CORRUPT/)bad++; else err++}
    END{printf "%s: %d copies, %d ok, %d io-errors, %d CORRUPT, mean %.1f MB/s\n", n, c, ok, err, bad, (s? t/1048576/s : 0)}' $LOG; done
  echo "events: $(grep -cE 'IOERR|REAPPEARED|CORRUPT' $EV) (see $EV)"
  echo "USB resets in dmesg: $(sudo dmesg | grep -ciE 'reset (high|super)speed|usb .* reset')"
  echo "uas/usb-storage/ext4 errors: $(sudo dmesg | grep -ciE 'uas_eh|usb-storage|I/O error|EXT4-fs error|blk_update_request')"
} | tee $D/summary.txt
