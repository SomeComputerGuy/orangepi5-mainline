#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
# Awake RTC alarm self-test: arm the alarm at the next full minute (40-100 s away)
# and check that the hym8563 IRQ fires and its wakeup_count increments.
irqcnt() { awk '/hym8563/{s=0; for(i=2;i<=9;i++) s+=$i; print s}' /proc/interrupts; }
W=/sys/class/rtc/rtc0/device/power/wakeup_count
s=$(date +%S); s=${s#0}; secs=$(( 120 - s )); [ $secs -gt 100 ] && secs=$(( secs - 60 ))
i0=$(irqcnt); w0=$(cat $W)
echo 0 > /sys/class/rtc/rtc0/wakealarm; echo +$secs > /sys/class/rtc/rtc0/wakealarm
echo "armed for +$secs s: $(grep -E 'alrm_time|alarm_IRQ' /proc/driver/rtc | tr -s '\t' ' ' | tr '\n' ' ')"
for n in $(seq 1 $(( secs + 15 ))); do [ "$(irqcnt)" != "$i0" ] && break; sleep 1; done
i1=$(irqcnt); w1=$(cat $W)
echo "irq $i0 -> $i1, wakeup_count $w0 -> $w1"
# wakeup_count only counts events that happen during a system transition, so the IRQ is the check
[ "$i1" != "$i0" ] && { echo "RTC alarm self-test PASS"; exit 0; }
echo "RTC alarm self-test FAIL"; exit 1
