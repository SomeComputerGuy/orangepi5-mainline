#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# ccu-repro.sh: minimal repro of the k4c/k4d regressions: a stream that passes alone, decoded at the same time
# as a stream that makes the hardware fail (a baseline failure). 5 runs per pair; md5 vs fluster's expected one.
R=~/.local/share/fluster/resources; T=/usr/share/fluster/test_suites; P=/sys/module/rockchip_vdec/parameters
E4=$(~/cq/elem.sh h264 rkvdec); E9=$(~/cq/elem.sh vp9 rkvdec); O=~/ccu/repro; mkdir -p $O; cd $O
exp() { python3 -c "import json; d=json.load(open('$T/$1')); print([v['result'] for v in d['test_vectors'] if v['name']=='$2'][0])"; }
f() { ls $R/$1/$2/* | grep -vE '\.(md5|yuv|txt)$' | head -1; }
h264() { gst-launch-1.0 -q filesrc location=$(f $1 $2) ! h264parse ! $E4 ! videoconvert ! video/x-raw,format=I420 ! fdsink fd=1 2>/dev/null | md5sum | cut -d' ' -f1; }
vp9() { gst-launch-1.0 -q filesrc location=$(f VP9-TEST-VECTORS $1) ! matroskademux ! vp9parse ! $E9 ! videoconvert ! video/x-raw,format=I420 ! fdsink fd=1 2>/dev/null | md5sum | cut -d' ' -f1; }
log() { echo "$*" | tee -a summary.txt; }
log "== $(date) $(sha256sum $(modinfo -n rockchip-vdec) | cut -c1-8) params $(cd $P; grep -H . pipeline ccu_hw | tr '\n' ' ')"
run() { # run <label> <expected> <cmd-good> <cmd-bad>
	local ok=0; for i in 1 2 3 4 5; do r=$( { $3 & $4 >/dev/null; wait; } | head -1); [ "$r" = "$2" ] && ok=$((ok+1)); done
	log "$1: $ok/5"; }
e1=$(exp h.264/JVT-AVC_V1.json HCBP1_HHI_A); e2=$(exp h.264/JVT-FR-EXT.json HCHP3_HHI_A); e3=$(exp vp9/VP9-TEST-VECTORS.json vp90-2-01-sharpness-7.webm)
run "HCBP1_HHI_A alone" $e1 "h264 JVT-AVC_V1 HCBP1_HHI_A" true
run "HCBP1_HHI_A + FM2_SVA_C" $e1 "h264 JVT-AVC_V1 HCBP1_HHI_A" "h264 JVT-AVC_V1 FM2_SVA_C"
run "HCBP1_HHI_A + FM1_FT_E" $e1 "h264 JVT-AVC_V1 HCBP1_HHI_A" "h264 JVT-AVC_V1 FM1_FT_E"
run "HCHP3_HHI_A + Hi422FREXT17_SONY_A" $e2 "h264 JVT-FR-EXT HCHP3_HHI_A" "h264 JVT-FR-EXT Hi422FREXT17_SONY_A"
run "sharpness-7 + size-08x08" $e3 "vp9 vp90-2-01-sharpness-7.webm" "vp9 vp90-2-02-size-08x08.webm"
log "dmesg: $(sudo -n dmesg | grep -c 'timed out') timeouts, $(sudo -n dmesg | grep -c 'resetting the core') resets since boot"
