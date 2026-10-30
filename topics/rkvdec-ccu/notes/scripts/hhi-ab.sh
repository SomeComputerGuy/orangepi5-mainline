#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# hhi-ab.sh: A/B the vectors that regressed or timed out with the CCU build (k4c), 5 runs each per mode,
# alone and two at a time; md5 of the I420 output vs fluster's expected md5. -> ~/ccu/hhi-ab/summary.txt
P=/sys/module/rockchip_vdec/parameters; R=~/.local/share/fluster/resources; O=~/ccu/hhi-ab; mkdir -p $O; cd $O
E=$(~/cq/elem.sh h264 rkvdec)
exp() { python3 -c "import json,sys; d=json.load(open('/usr/share/fluster/test_suites/h.264/$1.json')); print([v['result'] for v in d['test_vectors'] if v['name']=='$2'][0])"; }
md5() { gst-launch-1.0 -q filesrc location=$(ls $R/$1/$2/*.264 $R/$1/$2/*.jsv $R/$1/$2/*.26l $R/$1/$2/*.avc 2>/dev/null | head -1) ! h264parse ! $E ! videoconvert ! video/x-raw,format=I420 ! fdsink fd=1 2>/dev/null | md5sum | cut -d' ' -f1; }
setp() { for kv in "$@"; do echo ${kv#*=} | sudo -n tee $P/${kv%%=*} >/dev/null; done; }
log() { echo "$*" | tee -a summary.txt; }
V="JVT-AVC_V1/HCBP1_HHI_A JVT-AVC_V1/HCBP2_HHI_A JVT-AVC_V1/HCMP1_HHI_A JVT-FR-EXT/HCHP3_HHI_A JVT-FR-EXT/HCHP2_HHI_A JVT-FR-EXT/HCAFF1_HHI_B"
log "== $(date) $(sha256sum $(modinfo -n rockchip-vdec) | cut -c1-8)"; sudo -n dmesg | tail -1 > dmesg-start
for mode in "pipeline=1 ccu_hw=1 fieldpair=1" "pipeline=1 ccu_hw=1 fieldpair=0" "pipeline=0 ccu_hw=1" "pipeline=0 ccu_hw=0"; do
	setp $mode; log "-- $mode"
	for v in $V; do
		s=${v%/*}; n=${v#*/}; e=$(exp $s $n 2>/dev/null) || continue; ok=0
		for i in 1 2 3 4 5; do [ "$(md5 $s $n)" = "$e" ] && ok=$((ok+1)); done
		log "$n: $ok/5 alone   poc_alias=$(cat $P/stat_poc_alias) overlap=$(cat $P/stat_overlap)"
	done
	ok=0; for i in 1 2 3; do a=$(md5 JVT-AVC_V1 HCBP2_HHI_A & md5 JVT-AVC_V1 HCMP1_HHI_A & wait); \
		[ "$a" = "$(printf '%s\n%s' "$(exp JVT-AVC_V1 HCBP2_HHI_A)" "$(exp JVT-AVC_V1 HCMP1_HHI_A)")" ] || \
		[ "$a" = "$(printf '%s\n%s' "$(exp JVT-AVC_V1 HCMP1_HHI_A)" "$(exp JVT-AVC_V1 HCBP2_HHI_A)")" ] && ok=$((ok+1)); done
	log "HCBP2+HCMP1 together: $ok/3"
done
setp pipeline=1 ccu_hw=1 fieldpair=1
sudo -n dmesg | sed -n "/$(cut -c2-13 dmesg-start | sed 's/[]./\\&/g')/,\$p" | grep -iE "rkvdec|ccu|iommu" > dmesg.txt
log "dmesg: $(grep -c 'timed out' dmesg.txt) timeouts, $(grep -c 'resetting' dmesg.txt) resets (dmesg.txt)"
