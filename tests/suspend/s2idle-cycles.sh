#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
# Fast s2idle cycling proof: N cycles of real s2idle (default console, no
# pm_print_times), RTC wake, and device checks after every resume.
# usage: sudo [COPY_DIR=/mnt/extreme] s2idle-cycles.sh <N> [logdir]
# COPY_DIR: a directory on a mounted filesystem of the USB3 drive; each cycle
# starts a 256 MiB file copy into it just before suspend and checks the copy
# after resume (never writes the raw block device).
# Stops at the first failed check. A wedge shows up as a watchdog reboot (the
# log then ends without "cycle k: OK").
N=${1:-50} D=${2:-/var/tmp/susp-logs/cycles}
mkdir -p "$D"; L=$D/summary.txt
echo "### $(date -Is) start N=$N kernel=$(uname -v)" >> "$L"
echo s2idle > /sys/power/mem_sleep; echo none > /sys/power/pm_test
echo 0 > /sys/power/pm_print_times; echo 0 > /sys/power/pm_debug_messages
usb3_want=$(lsusb -t | grep -c "5000M")
dp_want=$(cat $(ls -d /sys/class/drm/card*-DP-1 | head -1)/status); hdmi_want=$(cat $(ls -d /sys/class/drm/card*-HDMI-A-1 | head -1)/status)
echo "baseline: usb3-links=$usb3_want DP-1=$dp_want HDMI-A-1=$hdmi_want" >> "$L"
for k in $(seq 1 "$N"); do
	python3 -I /var/tmp/rtc-set.py > /dev/null || { echo "cycle $k: rtc-set failed" >> "$L"; exit 1; }
	# hym8563 has 1-minute alarm resolution and rounds down: aim at the next full minute + 1
	s=$(date +%S); s=${s#0}; secs=$(( 120 - s )); [ $secs -gt 100 ] && secs=$(( secs - 60 ))
	echo "cycle $k start $(date +%T) sleep~$secs" > /dev/kmsg
	cp_pid=""
	if [ -n "$COPY_DIR" ]; then
		[ -f /var/tmp/cycles-src.bin ] || dd if=/dev/urandom of=/var/tmp/cycles-src.bin bs=1M count=256 status=none
		rm -f "$COPY_DIR/cycles-copy.bin"
		cp /var/tmp/cycles-src.bin "$COPY_DIR/cycles-copy.bin" & cp_pid=$!
		sleep 0.5
	fi
	t0=$(date +%s%N)
	echo 0 > /sys/class/rtc/rtc0/wakealarm
	rtcwake -m freeze -s $secs > /dev/null 2>&1; rc=$?
	ms=$(( ($(date +%s%N) - t0) / 1000000 ))
	sleep 4	# let USB re-enumerate and DP/HDMI settle
	irq=$(cat /sys/power/pm_wakeup_irq 2>/dev/null)
	fail=""
	[ $rc = 0 ] || fail="$fail rtcwake=$rc"
	u=$(lsusb -t | grep -c "5000M"); [ "$u" -ge "$usb3_want" ] || fail="$fail usb3=$u/$usb3_want"
	[ "$(cat $(ls -d /sys/class/drm/card*-DP-1 | head -1)/status)" = "$dp_want" ] || fail="$fail DP-1"
	[ "$(cat $(ls -d /sys/class/drm/card*-HDMI-A-1 | head -1)/status)" = "$hdmi_want" ] || fail="$fail HDMI"
	dd if=/dev/sda of=/dev/null bs=1M count=64 iflag=direct status=none skip=$((RANDOM % 2000)) || fail="$fail sata"
	ok=; for i in $(seq 10); do ping -c1 -W1 ${OPI5_HOST_IP:-172.31.55.1} > /dev/null && { ok=1; break; }; sleep 1; done; [ -n "$ok" ] || fail="$fail net"	# GbE renegotiates ~3 s
	if [ "$dp_want" = connected ]; then
		timeout 5 dd if=/dev/drm_dp_aux0 bs=16 count=1 status=none 2>/dev/null | od -An -tx1 | grep -q . || fail="$fail dp-aux"
	fi
	if [ -n "$cp_pid" ]; then
		wait $cp_pid || fail="$fail copy-failed"
		sync
		cmp -s /var/tmp/cycles-src.bin "$COPY_DIR/cycles-copy.bin" || fail="$fail copy-mismatch"
	fi
	e=$(dmesg | sed -n "/cycle $k start/,\$p" | grep -cE "AUX reply|failed to enable link|${XHC_OK:+NEVERMATCH}xHC error in resume|BUG|Oops|WARNING")
	[ "$e" = 0 ] || fail="$fail dmesg-errors=$e"
	if [ -n "$fail" ]; then echo "cycle $k: FAIL$fail (${ms} ms, irq $irq)" >> "$L"; exit 1; fi
	echo "cycle $k: OK (${ms} ms total, wake irq $irq)" >> "$L"
done
echo "### $(date -Is) done: $N/$N OK" >> "$L"
