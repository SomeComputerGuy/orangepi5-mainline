#!/bin/bash
# rt.sh <label> <planetest args>: run 4.5 s, print VOP irq/s for 3 s in the middle
label=$1; shift
sudo ./planetest -t 4.5 "$@" > /tmp/rt.log 2>&1 &
sleep 1.2; r=$(./irqrate.sh 3); wait
echo "[$label] irq/s: $r :: $(grep -E "fps|rror|failed" /tmp/rt.log | tr "\n" " ")"
