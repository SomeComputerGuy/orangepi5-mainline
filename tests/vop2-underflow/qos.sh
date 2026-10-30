#!/bin/bash
# qos.sh <prio_value|show>  -- set/show VOP NoC QoS priority (m0 + m1)
for b in 0xfdf82000 0xfdf82200; do
  if [ "$1" != show ]; then sudo insmod /tmp/regpeek.ko waddr=$((b+8)) wval=$1 2>/dev/null; fi
  sudo insmod /tmp/regpeek.ko addr=$b len=0x20 2>/dev/null
done
sudo dmesg | grep regpeek | tail -4
