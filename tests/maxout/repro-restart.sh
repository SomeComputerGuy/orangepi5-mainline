#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Start/stop the stream-A pipeline N times in a row and catch a start hang (no frame rendered in 15 s).
#   repro-restart.sh <variant: full|nonpu|nofifo|fakesink> [N=20] [secs per run=10] [end: int|eos]
# Needs weston on wayland-9. On a hang: thread stacks, open /dev/video* fds, dmesg tail -> ~/maxout/repro/hang-*.
V=${1:-full}; N=${2:-20}; RUN=${3:-10}; END=${4:-int}
D=$HOME/maxout/repro; mkdir -p $D; W="XDG_RUNTIME_DIR=/run/user/0 WAYLAND_DISPLAY=wayland-9"
A=http://${OPI5_HOST_IP:-172.31.55.1}:8099/jellyfish-250-mbps-4k-uhd-h264.mkv
source <(sed -n "/^dev_of/,/^demux_for/p" $HOME/maxout/maxout.sh)
DEC=$(dec_for h264); RGA3=$(conv_for rk3588-rga3); RGA2=$(conv_for rk3288-rga)
F=$D/npu.fifo; [ -p $F ] || mkfifo $F
( while [ ! -e $D/stop ]; do cat $F > /dev/null; done ) & RD=$!
case $V in
  full)     NPU="t. ! queue leaky=downstream max-size-buffers=2 ! videorate drop-only=true ! video/x-raw,framerate=15/1 ! $RGA3 ! video/x-raw,format=NV12,width=960,height=540 ! $RGA2 ! video/x-raw,format=RGB,width=224,height=224 ! filesink location=$F sync=false buffer-mode=unbuffered" ;;
  nofifo)   NPU="t. ! queue leaky=downstream max-size-buffers=2 ! videorate drop-only=true ! video/x-raw,framerate=15/1 ! $RGA3 ! video/x-raw,format=NV12,width=960,height=540 ! $RGA2 ! video/x-raw,format=RGB,width=224,height=224 ! fakesink sync=false" ;;
  nonpu)    NPU="" ;;
esac
SINK="fpsdisplaysink text-overlay=false sync=true signal-fps-measurements=true video-sink=\"${ASINK:-waylandsink fullscreen=true fullscreen-output=HDMI-A-1}\""
[ $V = fakesink ] && { SINK="fpsdisplaysink text-overlay=false sync=true signal-fps-measurements=true video-sink=fakevideosink"; NPU=""; }
echo "# $(date +%T) concurrentB=${CONCURRENT_B:-0} buffering=${BUFFERING:-true} asink=${ASINK:-wayland} bsink=${BSINK:-wayland} bout=${BOUT:-DP-1} variant=$V N=$N run=${RUN}s end=$END dec=$DEC ccu=$(cat /sys/module/rockchip_vdec/parameters/ccu_hw) pipeline=$(cat /sys/module/rockchip_vdec/parameters/pipeline)"
hangs=0
if [ -n "$CONCURRENT_B" ]; then   # stream B as in maxout (ToS HEVC -> DP), restarted on exit, runs alongside
  DECB=$(dec_for h265)
  ( while [ ! -e $D/stop ]; do sudo env $W gst-launch-1.0 -v souphttpsrc location=http://${OPI5_HOST_IP:-172.31.55.1}:8099/tears_of_steel_2160p_hevc.mp4 ! \
      queue2 use-buffering=${BUFFERING:-true} max-size-bytes=100000000 ! qtdemux ! h265parse ! queue ! $DECB ! queue ! \
      fpsdisplaysink text-overlay=false sync=true signal-fps-measurements=true video-sink="${BSINK:-waylandsink fullscreen=true fullscreen-output=${BOUT:-DP-1}}" \
      > $D/B.$(date +%s).log 2>&1 < /dev/null; done ) & BL=$!
  sleep 5
fi
for ((i=1; i<=N; i++)); do
  LOG=$D/$V.$i.log
  eval sudo env $W gst-launch-1.0 -v souphttpsrc location=$A ! queue2 use-buffering=${BUFFERING:-true} max-size-bytes=100000000 ! \
    matroskademux ! h264parse ! queue ! $DEC ! tee name=t t. ! queue ! $SINK $NPU > $LOG 2>&1 < /dev/null &
  sleep 1; P=$(pgrep -n -f "^gst-launch-1.0 .*jellyfish")
  ok=0; for ((s=0; s<15; s++)); do sleep 1; grep -q 'rendered: [1-9]' $LOG && { ok=1; break; }; done
  if [ $ok = 0 ]; then
    hangs=$((hangs+1)); H=$D/hang-$V-$i; mkdir -p $H
    for t in /proc/$P/task/*; do echo "== $(cat $t/comm) $(awk '{print $3}' $t/stat) wchan=$(sudo cat $t/wchan)"; sudo cat $t/stack; done > $H/stacks.txt 2>&1
    sudo ls -l /proc/$P/fd > $H/fds.txt 2>&1
    sudo dmesg | tail -40 > $H/dmesg.txt
    grep -E 'fdc38000|fdc40000|fdb60000|fdb70000|fdb80000' /proc/interrupts > $H/irqs.txt
    cat /sys/module/rockchip_vdec/parameters/stat_* > $H/vdec-stats.txt 2>/dev/null
    tr '\r' '\n' < $LOG | grep -v 'buffering\.\.\.' | tail -15 | cut -c1-200 > $H/tail.txt
    echo "run $i: HANG (evidence $H)"
  else
    echo "run $i: ok"
    if [ $END = eos ]; then lr=-1; still=0
      while [ -d /proc/$P ]; do sleep 1; r=$(tr '\r' '\n' < $LOG | grep -oE 'rendered: [0-9]+' | tail -1 | grep -oE '[0-9]+')
        if [ "$r" = "$lr" ]; then still=$((still+1)); else still=0; lr=$r; fi
        if [ $still -ge 10 ] && ! tr '\r' '\n' < $LOG | grep -q 'Got EOS'; then
          hangs=$((hangs+1)); H=$D/stall-$V-$i; mkdir -p $H; echo "run $i: STALL at frame $r ($(date +%T), evidence $H)"
          for t in /proc/$P/task/*; do echo "== $(cat $t/comm) $(sudo cat $t/stack | head -2 | tr '\n' ' ')"; done > $H/stacks.txt 2>&1
          for k in 1 2 3; do sudo grep -A2 -E '^plane\[' /sys/kernel/debug/dri/0/state | grep -E 'plane|fb=' | paste - - | tr -s '\t ' ' '; echo; sleep 1; done > $H/drm-planes.txt
          grep -E 'fdd90000|end0' /proc/interrupts > $H/irqs1.txt; sleep 2; grep -E 'fdd90000|end0' /proc/interrupts > $H/irqs2.txt
          ss -tn | grep 8099 > $H/sockets.txt; sudo dmesg | tail -30 > $H/dmesg.txt
          for f in $D/B.*.log; do echo "$f $(stat -c %y $f) $(tr '\r' '\n' < $f | grep -oE 'rendered: [0-9]+|Buffering, setting.*|Done buffering.*' | tail -2 | tr '\n' ' ')"; done > $H/b-state.txt
          tr '\r' '\n' < $LOG | grep -oE 'Buffering, setting.*|Done buffering.*|buffering\.\.\. [0-9]+%' | uniq | tail -5 > $H/a-buffering.txt
          break; fi
      done; else sleep $((RUN-s)); fi
  fi
  sudo kill -INT $P 2>/dev/null; for ((s=0; s<10; s++)); do [ -d /proc/$P ] || break; sleep 1; done
  [ -d /proc/$P ] && { echo "run $i: did not exit on SIGINT, killing"; sudo kill -9 $P; sleep 1; }
done
touch $D/stop; kill $RD 2>/dev/null; [ -n "$BL" ] && { sudo pkill -INT -f tears_of_steel; sleep 2; }; rm -f $D/stop
echo "# variant=$V hangs=$hangs/$N"
