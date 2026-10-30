#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# ccu-verify.sh: board checks for the rkvdec CCU (frame-parallel) driver, after the reboot.
#   1. driver/DT state  2. bit-exactness (every frame, framemd5 vs FFmpeg software)
#   3. single-stream fps A/B (pipeline / cache / ccu_hw module parameters)  4. two streams
# Usage: ccu-verify.sh [quick]   (quick: HEVC only)
# Results in ~/ccu/run-<time>/summary.txt
set -u
HERE=$(dirname $(readlink -f $0))
P=/sys/module/rockchip_vdec/parameters
D=~/ccu/run-$(date +%m%d-%H%M); mkdir -p $D; cd $D
log() { echo "$*" | tee -a summary.txt; }
setp() { for kv in "$@"; do echo ${kv#*=} | sudo -n tee $P/${kv%%=*} >/dev/null; done; }
stats() { echo "jobs=$(cat $P/stat_jobs) overlap=$(cat $P/stat_overlap)"; }
irqs() { grep -E 'fdc38000|fdc40000' /proc/interrupts | awk '{s=0; for(i=2;i<=9;i++) s+=$i; printf "%s ", s}'; }
. $HERE/ccu-lib.sh

log "== $(date) $(uname -v)"
log "rockchip-vdec: $(modinfo -n rockchip-vdec)  v4l2-mem2mem: $(modinfo -n v4l2-mem2mem)"
sudo -n dmesg | grep -iE 'rkvdec|vdec|ccu' > dmesg-boot.txt
log "CCU in use: $(grep -c 'decoding with the CCU' dmesg-boot.txt); elements h265=$E5 h264=$E4 vp9=$E9"
log "params: $(cd $P && grep -H . * | tr '\n' ' ')"
grep -iE 'error|fail|warn' dmesg-boot.txt | head -5 | tee -a summary.txt

CODECS="5 4 9"; [ "${1:-}" = quick ] && CODECS=5
for c in $CODECS; do
	log "-- codec $c (5=HEVC 4=H.264 9=VP9), 3840x2160 600 frames"
	setp pipeline=1 cache=1 ccu_hw=1; i0=$(irqs); s0=$(stats)
	log "pipeline=1 cache=1: $(exact $c p1c1)   [$s0 -> $(stats); core irqs $i0-> $(irqs)]"
	log "pipeline=1 cache=1: $(fps $c) fps   [$(stats)]"
	setp pipeline=0;          log "pipeline=0 cache=1: $(fps $c) fps"
	setp cache=0;             log "pipeline=0 cache=0: $(fps $c) fps"
	setp ccu_hw=0;            log "pipeline=0 cache=0 ccu_hw=0 (old behaviour): $(fps $c) fps"
	setp pipeline=1 ccu_hw=1; log "pipeline=1 cache=0: $(fps $c) fps"
	[ $c = 9 ] || log "pipeline=1 cache=0: $(exact $c p1c0)"
	setp pipeline=1 cache=1 ccu_hw=1
done

log "-- two HEVC streams at once (pipeline=1 cache=1)"
t0=$(date +%s.%N)
gst-launch-1.0 -q $(src 5) ! fakevideosink sync=false >/dev/null 2>&1 & p1=$!
gst-launch-1.0 -q $(src 5) ! videoconvert ! video/x-raw,format=I420 ! fdsink fd=1 2>/dev/null |
	ffmpeg -nostdin -v error -f rawvideo -pix_fmt yuv420p -s 3840x2160 -i - -f framemd5 t5-2str.md5 & p2=$!
wait $p1; t1=$(date +%s.%N); wait $p2
log "stream 1: $(echo "600/($t1-$t0)" | bc -l | cut -c1-5) fps; stream 2 (with md5, CPU-bound): $(paste -d' ' <(grep -v "^#" $HOME/ccu/ref5.md5 | awk -F, '{print $NF}') <(grep -v '^#' t5-2str.md5 | awk -F, '{print $NF}') | awk '$1==$2' | wc -l)/600 bit-exact"
t0=$(date +%s.%N)
for i in 1 2; do gst-launch-1.0 -q $(src 5) ! fakevideosink sync=false >/dev/null 2>&1 & done; wait
log "2 x HEVC decode-only: $(echo "1200/($(date +%s.%N)-$t0)" | bc -l | cut -c1-5) fps total"
setp pipeline=0; t0=$(date +%s.%N)
for i in 1 2; do gst-launch-1.0 -q $(src 5) ! fakevideosink sync=false >/dev/null 2>&1 & done; wait
log "2 x HEVC decode-only, pipeline=0: $(echo "1200/($(date +%s.%N)-$t0)" | bc -l | cut -c1-5) fps total"
setp pipeline=1
sudo -n dmesg | grep -iE 'rkvdec|vdec|iommu|timed out|ccu' | tail -20 > dmesg-after.txt
log "dmesg after: $(grep -ciE 'timed out|fault|error' dmesg-after.txt) error lines (dmesg-after.txt)"
log "DONE $(date)"
