#!/bin/bash
# rtl.sh <label> <hog threads> <planetest args>: like rtb.sh with a DDR hog running
label=$1; th=$2; shift 2
[ "$th" -gt 0 ] && ./memhog $th 6 &
sudo ./planetest -t 4.5 "$@" > /tmp/rt.log 2>&1 &
sleep 1.2; (sudo ./ddrbw 3 | awk "{print \$2\"/\"\$4}" | tr "\n" " " > /tmp/bw.txt) & r=$(./irqrate.sh 3); wait
echo "[$label hog=$th] irq/s: $r :: rd/wr MB/s $(cat /tmp/bw.txt) :: $(grep -E "fps|rror|failed" /tmp/rt.log | tr "\n" " ")"
