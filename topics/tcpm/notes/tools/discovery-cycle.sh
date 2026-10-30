#!/bin/bash
# Re-run USB PD attach + VDM discovery N times on the Orange Pi 5 USB-C port by
# forcing a port reset through port_type (dual -> sink -> dual) and count how
# often DP Alt Mode is discovered and configured.
# Usage: sudo discovery-cycle.sh N OUTDIR [late_svids_ms]
#   late_svids_ms: TEST builds only, sets tcpm test_late_svids_ms (the first
#   Discover SVIDs after each attach times out after that many ms).
# Disruptive: every cycle detaches the dock (USB3 hub, NIC, card reader, DP).
set -u
N=${1:-100}; OUT=${2:-/var/tmp/tcpm-cycles}; LATE=${3:-}
P=/sys/class/typec/port0
LOG=/sys/kernel/debug/usb/tcpm-6-0022/log
ALT=/sys/bus/typec/devices/port0-partner.0
mkdir -p "$OUT"
trap 'echo dual > $P/port_type' EXIT
if [ -n "$LATE" ]; then
	echo "$LATE" > /sys/module/tcpm/parameters/test_late_svids_ms || exit 1
fi
cat $LOG > "$OUT/pre.log"
# dock USB devices (everything behind the dock's USB2 and USB3 hubs on root ports 7-1/8-1)
dock_usb() { for d in /sys/bus/usb/devices/[78]-1 /sys/bus/usb/devices/[78]-1.*; do
	[ -f $d/idVendor ] && echo "$(basename $d)=$(cat $d/idVendor):$(cat $d/idProduct)"; done | sort | tr '\n' ' '; }
BASE=$(dock_usb); NB=$(echo $BASE | wc -w)
echo "baseline $NB: $BASE" | tee -a "$OUT/summary.txt"
pass=0; fail=0; usbfail=0
for i in $(seq 1 "$N"); do
	echo sink > $P/port_type
	# wait for the partner to go away
	for t in $(seq 1 30); do [ -e $P/port0-partner ] || break; sleep 0.1; done
	sleep 1
	echo dual > $P/port_type
	res=FAIL
	# up to 12 s for attach + discovery + Configure
	for t in $(seq 1 120); do
		if [ -e $ALT/displayport/configuration ] &&
		   grep -q '\[sink\]' $ALT/displayport/configuration 2>/dev/null; then
			res=PASS; break
		fi
		sleep 0.1
	done
	# wait up to 25 s for every dock USB device to re-enumerate
	# (extra devices plugged in meanwhile are ignored; only baseline devices count)
	missing() { comm -23 <(echo $BASE | tr ' ' '\n' | sort) <(dock_usb | tr ' ' '\n' | sort) | tr '\n' ' '; }
	for u in $(seq 1 250); do [ -z "$(missing)" ] && break; sleep 0.1; done
	NOW=$(dock_usb); nu=$(echo $NOW | wc -w); m=$(missing)
	if [ -z "$m" ]; then usb=ok; else usb="MISSING($m)"; usbfail=$((usbfail+1)); fi
	sleep 2
	cat $LOG > "$OUT/cycle-$i.log"
	dmesg | tail -n 60 | grep -E 'error -71|not accepting|can.t set config|USB disconnect|unable to enumerate' > "$OUT/cycle-$i.usberr" || true
	pr=$( [ -e $P/port0-partner ] && echo partner || echo nopartner )
	if [ $res = PASS ]; then pass=$((pass+1)); else fail=$((fail+1)); fi
	echo "$i $res $pr t=${t} usb=$nu/$NB $usb tu=$u timeouts=$(grep -c 'VDM response timeout\|TEST:' "$OUT/cycle-$i.log") ignored=$(grep -c 'Ignoring' "$OUT/cycle-$i.log")" | tee -a "$OUT/summary.txt"
done
[ -n "$LATE" ] && echo 0 > /sys/module/tcpm/parameters/test_late_svids_ms
echo "TOTAL N=$N pass=$pass fail=$fail usbfail=$usbfail late=${LATE:-0} tcpm=$(modinfo -n tcpm) srcver=$(cat /sys/module/tcpm/srcversion)" | tee -a "$OUT/summary.txt"
