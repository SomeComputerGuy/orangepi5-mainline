#!/bin/sh
# SPDX-License-Identifier: GPL-2.0
# DIAGNOSTIC: hold a mode on HDMI-A-1, then apply register pokes one by one, camera after each.
# usage: poke-test.sh <outdir> "<kmsctl spec>" "<off> <val> [mask]" ...
out=$1; spec=$2; shift 2
mkdir -p "$out"
sleep 400 | python3 -I /var/tmp/testmatrix/lib/kmsctl.py show --hold 300 --head "conn=HDMI-A-1,$spec,pattern=bars" > "$out/kms.json" 2>&1 &
kp=$!
sleep 8
cap() { python3 -I -c "import sys; sys.path.insert(0,'/var/tmp/testmatrix/lib'); import camcheck,json; cal=json.load(open('/var/tmp/wo/r1/calib.json')); r=camcheck.classify(cal, camcheck.load(camcheck.capture('$out/$1')), 'bars'); print('$1', r['verdict'])"; python3 -I /var/tmp/wedge/hdmiregs.py > "$out/$1.regs"; }
cap p0
i=1
for p in "$@"; do
	python3 -I /var/tmp/wedge/hdmipoke.py $p | tee -a "$out/pokes.txt"
	sleep 6
	cap p$i
	i=$((i+1))
done
pkill -f "kmsctl.py show --hold 300"; sleep 1
