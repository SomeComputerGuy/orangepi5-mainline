#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Power proxy for s2idle on a board without a power sensor: the SoC's TSADC zones read
# right after a long suspend-to-idle (a lower-power sleep leaves the die cooler), plus the
# awake-idle baseline before it. Run with and without a change and compare.
#   s2idle-temp.sh <tag> [sleep_s=300] [runs=2]
tag=${1:-t}; secs=${2:-300}; runs=${3:-2}; out=/var/tmp/susp-logs/temp-$tag.txt
zones() { for z in /sys/class/thermal/thermal_zone*; do printf "%s=%s " "$(cat $z/type)" "$(cat $z/temp)"; done; echo; }
echo s2idle > /sys/power/mem_sleep
{
echo "### $tag $(uname -r) $(date -Is) sleep=${secs}s"
sleep 60; echo "awake-idle: $(zones)"
for r in $(seq $runs); do
	python3 -I /var/tmp/rtc-set.py > /dev/null
	# hym8563 alarm: 1-minute resolution, aim at a full minute
	s=$(date +%S); s=${s#0}; w=$(( secs - s )); [ $w -lt 60 ] && w=$(( w + 60 ))
	echo 0 > /sys/class/rtc/rtc0/wakealarm
	rtcwake -m freeze -s $w > /dev/null 2>&1
	echo "after-s2idle-$r (${w}s): $(zones)"
	sleep 90
done
} > "$out" 2>&1
cat "$out"
