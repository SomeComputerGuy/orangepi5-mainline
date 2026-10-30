#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Runtime PM check for the OHCI root hubs (no USB 1.1 device can be plugged remotely):
# N times force each OHCI root hub to resume (power/control=on) and let it autosuspend again
# (power/control=auto, short autosuspend delay), checking every transition and dmesg.
# usage: sudo ohci-rpm-cycles.sh [N=20]
N=${1:-20}
hubs=$(for d in /sys/bus/usb/devices/usb*; do grep -q "OHCI" $d/product 2>/dev/null && echo $d; done)
[ -n "$hubs" ] || { echo "no OHCI root hubs"; exit 1; }
wait_state() {	# <dev> <state> <timeout s>
	for _ in $(seq $(( $3 * 10 ))); do
		[ "$(cat $1/power/runtime_status)" = "$2" ] && return 0; sleep 0.1
	done
	return 1
}
echo "OHCI root hubs: $(for h in $hubs; do echo -n "$(basename $h)($(cat $h/serial)) "; done)"
declare -A delay ctl
for h in $hubs; do delay[$h]=$(cat $h/power/autosuspend_delay_ms); ctl[$h]=$(cat $h/power/control); done
echo "OHCI-RPM-START" > /dev/kmsg
fail=0
for k in $(seq $N); do
	for h in $hubs; do
		echo 200 > $h/power/autosuspend_delay_ms
		echo on > $h/power/control
		wait_state $h active 5 || { echo "cycle $k $(basename $h): did not resume"; fail=1; }
		echo auto > $h/power/control
		wait_state $h suspended 5 || { echo "cycle $k $(basename $h): did not autosuspend"; fail=1; }
	done
done
for h in $hubs; do echo ${delay[$h]} > $h/power/autosuspend_delay_ms; echo ${ctl[$h]} > $h/power/control; done
e=$(dmesg | sed -n '/OHCI-RPM-START/,$p' | grep -ciE "ohci.*(error|fail|won't|unable)|BUG|Oops|WARNING")
for h in $hubs; do echo "$(basename $h): status=$(cat $h/power/runtime_status) active_ms=$(cat $h/power/runtime_active_time) suspended_ms=$(cat $h/power/runtime_suspended_time)"; done
[ $fail = 0 ] && [ "$e" = 0 ] && { echo "OHCI runtime PM: $N/$N cycles OK"; exit 0; }
echo "OHCI runtime PM: FAIL (transition failures=$fail, dmesg errors=$e)"; exit 1
