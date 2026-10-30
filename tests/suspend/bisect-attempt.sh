#!/bin/bash
# One bisect attempt for the fast-s2idle resume wedge (bug 3).
# usage: sudo bisect-attempt.sh <tag> <events> <phases> <invert> "<match>" [delay_ms]
#   events 1=suspend 2=resume 3=both; phases 0=normal only 1=all; match "" = all devices
# PASS: /var/tmp/susp-logs/<tag>.log ends with rc=0 and "resume_delay: done ...".
# FAIL: board wedges after wake; dw_wdt resets it ~44 s later (look at the serial log).
set -e
tag=$1 ev=$2 ph=$3 inv=$4 m=$5 d=${6:-20}
M=/sys/module/resume_delay/parameters
lsmod | grep -q '^resume_delay ' || insmod /var/tmp/resume_delay.ko
echo "$ev" > $M/events; echo "$ph" > $M/phases; echo "$inv" > $M/invert
echo "$d" > $M/delay_ms; printf '%s\n' "$m" > $M/match   # always write (an empty write would keep the old value)
echo "BISECT $tag events=$ev phases=$ph invert=$inv delay=$d match='$m'" | tee -a /var/tmp/susp-logs/bisect.txt > /dev/kmsg
# hym8563 needs a valid time (no backup battery)
python3 -I /var/tmp/rtc-set.py >/dev/null	# also fixes the weekday the hym8563 alarm matches
PRINT_TIMES=0 /var/tmp/susp-run.sh "$tag" s2idle none 120
grep -q rc=0 /var/tmp/susp-logs/$tag.log && echo "$tag PASS" | tee -a /var/tmp/susp-logs/bisect.txt
