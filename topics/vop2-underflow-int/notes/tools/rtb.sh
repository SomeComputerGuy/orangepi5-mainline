#!/bin/bash
label=$1; shift
sudo ./planetest -t 4.5 "$@" > /tmp/rt.log 2>&1 &
sleep 1.2; (sudo ./ddrbw 3 | awk "{print \$2}" | tr "\n" " " > /tmp/bw.txt) & r=$(./irqrate.sh 3); wait
echo "[$label] irq/s: $r :: rdMB/s $(cat /tmp/bw.txt) :: $(grep -E "fps|rror|failed" /tmp/rt.log | tr "\n" " ")"
