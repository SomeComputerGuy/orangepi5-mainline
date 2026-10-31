#!/bin/sh
# SPDX-License-Identifier: GPL-2.0
# usage: modeset.sh <mode> <secs> [crc]: show modetest pattern on DP-1 and sample sink CRC
MODE=$1; T=${2:-8}
(sleep $T) | modetest -M rockchip -s 86@84:$MODE > /tmp/mt.log 2>&1 &
sleep 4
[ -n "$3" ] && sh /tmp/crc.sh 6
wait
grep -iE "setting mode|failed|error" /tmp/mt.log | head -3
