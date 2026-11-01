#!/bin/sh
# SPDX-License-Identifier: GPL-2.0
# DIAGNOSTIC (needs the diag rockchipdrm/dw-hdmi-qp builds with diag_action params):
# get a "No Signal" 4096 FRL state (YUV420 TMDS first), keep it, apply one in-place action, check lock + camera.
# usage: recover-test.sh <outdir> <module/parameters/param=value> [...]  e.g. rockchipdrm/parameters/diag_action=1
. /var/tmp/wedge/seq.sh
out=$1; shift; mkdir -p "$out"
L=/var/tmp/testmatrix/lib
hold() { sleep 600 | KMSCTL_PROBE=1 python3 -I $L/kmsctl.py show --head "conn=HDMI-A-1,$1,pattern=bars" > "$out/kms-$2.json" 2>&1 & sleep 9; }
stop() { pkill -f "kmsctl.py show"; sleep 2; }
locked() { python3 -I /var/tmp/wedge/hdmiregs.py | awk '/VIDEO_INTERFACE_STATUS0/ {print $4}'; }
cam() { python3 -I -c "import sys; sys.path.insert(0,'$L'); import camcheck,json; cal=json.load(open('/var/tmp/wo/r1/calib.json')); r=camcheck.classify(cal, camcheck.load(camcheck.capture('$out/$1')), 'bars'); print('$1', r['verdict'])"; }
for act in "$@"; do
	n=0
	while :; do
		n=$((n+1)); [ $n -gt 8 ] && { echo "$act: no failing FRL state in 8 tries"; break; }
		hold "$T4096,$B8,$Y420,$LIN" y; stop
		hold "$T4096,$B10,$AUTO,$AFBC30" f
		s=$(locked)
		echo "try $n: FRL VIF_STATUS0=$s"
		case $s in 0x0004*) stop; continue;; esac
		cam "$(echo $act | tr / _)-before"
		dmesg -C
		# act = module/param=value
		echo ${act#*=} > /sys/module/${act%=*}; echo "action $act rc=$?"
		sleep 4
		echo "after $act: VIF_STATUS0=$(locked)"; python3 -I /var/tmp/wedge/hdmiregs.py > "$out/$(echo $act | tr / _)-after.regs"
		cam "$(echo $act | tr / _)-after"
		dmesg | grep DIAG | tail -3 | cut -c1-220
		stop
		break
	done
done
