#!/bin/bash
# usage: susp-run.sh <tag> <s2idle|deep> <pm_test> [rtcwake_seconds]
tag=$1 ms=$2 pt=$3 rw=$4
L=/var/tmp/susp-logs; mkdir -p $L; out=$L/$tag.log
{
echo "### $tag mem_sleep=$ms pm_test=$pt rtcwake=$rw $(date -Is)"
echo $ms > /sys/power/mem_sleep; echo $pt > /sys/power/pm_test
echo N > /sys/module/printk/parameters/console_suspend
echo ${PRINT_TIMES:-1} > /sys/power/pm_print_times; echo 1 > /sys/power/pm_debug_messages
[ -n "$LOCKUP" ] && { echo 10 > /proc/sys/kernel/watchdog_thresh; echo 15 > /proc/sys/kernel/hung_task_timeout_secs; echo 1 > /proc/sys/kernel/softlockup_all_cpu_backtrace; echo 1 > /proc/sys/kernel/hardlockup_all_cpu_backtrace; echo 1 > /proc/sys/kernel/hung_task_all_cpu_backtrace 2>/dev/null; }
echo Y > /sys/module/printk/parameters/ignore_loglevel
[ -n "$INITCALL_DEBUG" ] && echo Y > /sys/module/kernel/parameters/initcall_debug
if [ -n "$QUIET" ]; then echo N > /sys/module/printk/parameters/ignore_loglevel; dmesg -n 3; else dmesg -n 8; fi
echo "SUSPTEST-START $tag" > /dev/kmsg
sync; sleep 1
t0=$(date +%s%N)
if [ -n "$rw" ]; then
  echo 0 > /sys/class/rtc/rtc0/wakealarm
  if [ $ms = deep ]; then rtcwake -m mem -s $rw; else rtcwake -m freeze -s $rw; fi
else
  echo mem > /sys/power/state
fi
rc=$?
echo "rc=$rc elapsed_ms=$(( ($(date +%s%N)-t0)/1000000 ))"
echo "SUSPTEST-END $tag" > /dev/kmsg
echo none > /sys/power/pm_test
echo N > /sys/module/kernel/parameters/initcall_debug
dmesg | sed -n "/SUSPTEST-START $tag/,\$p"
} > $out 2>&1
