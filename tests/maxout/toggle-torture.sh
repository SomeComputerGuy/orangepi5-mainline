#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Abusive start/stop of every media device on the Orange Pi 5. Runs ON the board, unattended.
#   toggle-torture.sh [N=50] [device ...]      (default: all devices)  report: ~/torture/report.txt
# Each cycle: start the device's workload (1 instance, or 2 concurrently every 5th cycle), let it run a random
# 0.2-3 s (0.2 s often lands mid-preroll / mid-setup), then kill it with a random SIGINT/SIGTERM/SIGKILL.
# Then check: the process exits within 5 s (else: stuck -> evidence), no process still holds the /dev node,
# no new kernel errors (timeout, IOMMU fault, Oops, SError, BUG, WARNING, busy, hung task), and a short known-good
# job (md5 vs. the cycle-0 reference) completes; its open-to-first-output time must be < 2 s (logged).
# Devices: rkvdec-h264 rkvdec-hevc rkvdec-vp9 (+ rkvdec-*-noccu when the CCU module with ccu_hw/pipeline params is loaded), g1-h264 g1-vp8 g1-mpeg2, av1,
#          venc-h264 venc-hevc (VEPU580), jpegenc (VEPU121), jpegdec (rkjpegd), iep, rga3, rga2, npu,
#          disp-hdmi disp-dp (waylandsink under weston; weston is started if not running).
# Never rmmods, never reads regmap debugfs. The CCU module parameters are restored at the end.
N=${1:-50}; shift
ALL="rkvdec-h264 rkvdec-hevc rkvdec-vp9 g1-h264 g1-vp8 g1-mpeg2 av1 venc-h264 venc-hevc jpegenc jpegdec iep rga3 rga2 npu disp-hdmi disp-dp"   # iep is driven with work/_out/iep2/tools/iep-test (GStreamer cannot deinterlace, GSTREAMER-FOLLOWUPS 2)
DEVS=${*:-$ALL}
T=$HOME/torture; mkdir -p $T; R=$T/report.txt; : > $R
C=$HOME/demo; W="XDG_RUNTIME_DIR=/run/user/0 WAYLAND_DISPLAY=wayland-9"
PY="env PYTHONPATH=$HOME/npu-venv/lib/python3.14/site-packages python3"
VP=/sys/module/rockchip_vdec/parameters
say() { echo "$*" | tee -a $R; }

dev_of() { gst-inspect-1.0 "$1" 2>/dev/null | grep -oE '/dev/video[0-9]+' | head -1; }
devname() { cat /sys/class/video4linux/$(basename $1)/name; }
dec_for() { for e in $(gst-inspect-1.0 v4l2codecs | grep -oE "v4l2sl[a-z0-9]*${1}dec" | sort -u); do
  d=$(dev_of $e); [ -n "$d" ] && devname $d | grep -q "$2" && { echo $e; return; }; done; }
conv_for() { for e in $(gst-inspect-1.0 video4linux2 | grep -oE 'v4l2[a-z0-9]*convert' | sort -u); do
  d=$(dev_of $e); [ -n "$d" ] && readlink -f /sys/class/video4linux/$(basename $d)/device | grep -q "$1" && { echo $e; return; }; done; }
node() { for d in /sys/class/video4linux/video*; do grep -q "$1" $d/name && { echo /dev/$(basename $d); return; }; done; }

# ---- weston for the display tests
if ! pgrep -x weston >/dev/null; then
  sudo mkdir -p /run/user/0; sudo chmod 700 /run/user/0
  sudo env XDG_RUNTIME_DIR=/run/user/0 LIBSEAT_BACKEND=noop nohup weston --backend=drm --shell=desktop \
    --continue-without-input --idle-time=0 --socket=wayland-9 --log=$T/weston.log >/dev/null 2>&1 </dev/null &
  sleep 8; STARTED_WESTON=1
fi
# ---- reference inputs
[ -s $T/ref.jpg ] || gst-launch-1.0 -q filesrc location=$C/yacht_1080p.nv12 ! rawvideoparse format=nv12 width=1920 height=1080 framerate=30/1 ! \
  identity eos-after=1 ! jpegenc ! filesink location=$T/ref.jpg
[ -s $T/ref10.nv12 ] || head -c $((1920*1080*3/2*10)) $C/yacht_1080p.nv12 > $T/ref10.nv12
[ -s $T/ref.mjpeg ] || gst-launch-1.0 -q filesrc location=$C/yacht_1080p.nv12 ! rawvideoparse format=nv12 width=1920 height=1080 framerate=30/1 ! \
  identity eos-after=60 ! jpegenc ! avimux ! filesink location=$T/ref.avi

H264=$(dec_for h264 rkvdec); H265=$(dec_for h265 rkvdec); VP9=$(dec_for vp9 rkvdec)
G1H264=$(dec_for h264 vpu121-dec); G1VP8=$(dec_for vp8 vpu121-dec); G1MP2=$(dec_for mpeg2 vpu121-dec); AV1=$(dec_for av1 av1)
RGA3=$(conv_for rk3588-rga3); RGA2=$(conv_for rk3288-rga); IEP=$(conv_for iep)
VENC=$(node rockchip-venc); IEPDEV=$(node rockchip-iep)
NV12_1080="filesrc location=$C/yacht_1080p.nv12 ! rawvideoparse format=nv12 width=1920 height=1080 framerate=120/1"
say "# toggle-torture $(date '+%F %T') $(uname -v) N=$N"
say "# h264=$H264 h265=$H265 vp9=$VP9 g1=$G1H264/$G1VP8/$G1MP2 av1=$AV1 rga3=$RGA3 rga2=$RGA2 iep=$IEP venc=$VENC"

# work <dev> <mode: long|check> <out>: long = runs until killed (looping input); check = short known-good job -> out
work() {
  local dev=${1%-noccu} m=$2 o=$3 n=30 sink
  [ $m = long ] && { n=100000; o=/dev/null; }
  sink="identity eos-after=$n ! filesink location=$o"
  case $dev in
  rkvdec-h264) gst-launch-1.0 -q filesrc location=$C/yacht_h264_2160p120.mp4 ! qtdemux ! h264parse ! $H264 ! $sink ;;
  rkvdec-hevc) gst-launch-1.0 -q filesrc location=$C/yacht_hevc_2160p120.mp4 ! qtdemux ! h265parse ! $H265 ! $sink ;;
  rkvdec-vp9)  gst-launch-1.0 -q filesrc location=$C/yacht_vp9_2160p120.webm ! matroskademux ! vp9parse ! $VP9 ! $sink ;;
  g1-h264)     gst-launch-1.0 -q filesrc location=$C/yacht_h264_1080p120.mp4 ! qtdemux ! h264parse ! $G1H264 ! $sink ;;
  g1-vp8)      gst-launch-1.0 -q filesrc location=$C/yacht_vp8_1080p120.webm ! matroskademux ! $G1VP8 ! $sink ;;
  g1-mpeg2)    gst-launch-1.0 -q filesrc location=$C/yacht_mpeg2_1080p120.mpg ! mpegpsdemux ! mpegvideoparse ! $G1MP2 ! $sink ;;
  av1)         gst-launch-1.0 -q filesrc location=$C/yacht_av1_1080p120.mkv ! matroskademux ! av1parse ! $AV1 ! $sink ;;
  venc-h264|venc-hevc)
    local e=${dev#venc-} in=$T/ref10.nv12 fr=10; [ $m = long ] && { in=$C/yacht_1080p.nv12; fr=600; }
    $C/rkvenc-enc -e $e -d $VENC -i $in -o $o -w 1920 -h 1080 -n $fr -f 30 -g 30 -q 30 > /dev/null 2>&1 ;;
  jpegenc)     gst-launch-1.0 -q $NV12_1080 ! identity eos-after=$n ! v4l2jpegenc ! filesink location=$o ;;
  jpegdec)     gst-launch-1.0 -q filesrc location=$T/ref.avi ! avidemux ! jpegparse ! v4l2jpegdec ! $sink ;;
  iep)         # the device directly (GStreamer can't drive IEP2 deinterlacing): interlaced TB NV12 1080, motion-adaptive
               if [ $m = long ]; then $HOME/maxout/iep-test -d $IEPDEV -i $T/ref10.nv12 -o - -w 1920 -h 1080 -F tb -m ma -l 100000 >/dev/null 2>&1
               else $HOME/maxout/iep-test -d $IEPDEV -i $T/ref10.nv12 -o $o -w 1920 -h 1080 -F tb -m ma -n 10 >/dev/null 2>&1; fi ;;
  rga3)        gst-launch-1.0 -q $NV12_1080 ! $RGA3 ! video/x-raw,format=NV12,width=960,height=540 ! $sink ;;
  rga2)        gst-launch-1.0 -q $NV12_1080 ! $RGA2 ! video/x-raw,format=RGB,width=640,height=360 ! $sink ;;
  npu)         if [ $m = long ]; then $PY $HOME/npu/scripts/classify.py $HOME/npu/models/mobilenet_v1_1.0_224_quant.tflite \
                   $HOME/npu/models/imagenet_labels.txt $HOME/npu/models/grace_hopper.bmp --delegate /usr/lib/teflon/libteflon.so --runs 100000 >/dev/null 2>&1
               else $PY $HOME/npu/scripts/classify.py $HOME/npu/models/mobilenet_v1_1.0_224_quant.tflite \
                   $HOME/npu/models/imagenet_labels.txt $HOME/npu/models/grace_hopper.bmp --delegate /usr/lib/teflon/libteflon.so --runs 1 --save-out $o.npy >/dev/null 2>&1 && mv $o.npy $o; fi ;;
  disp-hdmi|disp-dp)
    local out=HDMI-A-1; [ $dev = disp-dp ] && out=DP-1
    sudo env $W gst-launch-1.0 -q filesrc location=$C/yacht_hevc_2160p120.mp4 ! qtdemux ! h265parse ! $H265 ! identity eos-after=$n ! \
      waylandsink fullscreen=true fullscreen-output=$out > /dev/null 2>&1 && echo shown > $o ;;
  esac
}
devnode() {   # the /dev node(s) a device's workload uses (for leftover-holder checks)
  case ${1%-noccu} in
  rkvdec-*) dev_of $H264 ;; g1-*) dev_of $G1H264 ;; av1) dev_of $AV1 ;; venc-*) echo $VENC ;;
  jpegenc) node vepu121-enc ;; jpegdec) node rockchip-jpegd ;; iep) node rockchip-iep ;; rga3) dev_of $RGA3 ;; rga2) dev_of $RGA2 ;;
  npu) ls /dev/accel/accel* 2>/dev/null ;; disp-*) dev_of $H265 ;;
  esac; }
kerr() { sudo dmesg | awk -v t="$1" '{x=$1; gsub(/[][]/,"",x); if (x+0>t) print}' | \
  grep -iE 'timeout|timed out|fault|oops|serror|BUG|WARNING|busy|hung task|Unable to handle|error' | grep -v 'POST_BUF_EMPTY' ; }
now() { cut -d' ' -f1 /proc/uptime; }
evidence() {  # evidence <dir> <pid...>
  local h=$1; shift; mkdir -p $h
  for p in "$@"; do [ -d /proc/$p ] || continue
    for t in /proc/$p/task/*; do echo "== $p $(cat $t/comm 2>/dev/null) $(awk '{print $3}' $t/stat 2>/dev/null) wchan=$(sudo cat $t/wchan 2>/dev/null)"; sudo cat $t/stack 2>/dev/null; done
    sudo ls -l /proc/$p/fd 2>/dev/null | grep -E 'video|media|accel|dri'
  done > $h/stacks.txt
  sudo dmesg | tail -60 > $h/dmesg.txt; ps -eo pid,stat,wchan:30,cmd | grep -vE '\[|ps -eo' > $h/ps.txt
}

declare -A REF
for dev in $DEVS; do
  [ -e $VP/ccu_hw ] && case $dev in *-noccu) echo 0 | sudo tee $VP/pipeline $VP/ccu_hw >/dev/null ;; rkvdec-*) echo 1 | sudo tee $VP/pipeline $VP/ccu_hw >/dev/null ;; esac
  rm -f $T/ref.$dev; t1=$(date +%s.%N); timeout 30 bash -c "$(declare -f work); $(declare -p C T H264 H265 VP9 G1H264 G1VP8 G1MP2 AV1 RGA3 RGA2 IEP IEPDEV VENC NV12_1080 PY W); work $dev check $T/ref.$dev"
  REF[$dev]=$(md5sum < $T/ref.$dev 2>/dev/null | cut -c1-32)
  [ -s $T/ref.$dev ] || { say "$dev: SKIP (reference job failed)"; continue; }
  pass=0; fail=0; first=""; slow=0; maxopen=0
  for ((i=1; i<=N; i++)); do
    t0=$(now); k=$((RANDOM % 3)); sig=(INT TERM KILL); sig=${sig[$k]}
    inst=1; [ $((i % 5)) = 0 ] && inst=2
    pids=()
    for ((j=0; j<inst; j++)); do
      setsid bash -c "$(declare -f work); $(declare -p C T H264 H265 VP9 G1H264 G1VP8 G1MP2 AV1 RGA3 RGA2 IEP IEPDEV VENC NV12_1080 PY W); work $dev long" </dev/null >/dev/null 2>&1 &
      pids+=($!)
    done
    sleep $(awk -v r=$RANDOM 'BEGIN{printf "%.2f", 0.2 + 2.8*r/32767}')
    for p in "${pids[@]}"; do sudo pkill -$sig -s $p 2>/dev/null; done   # whole session: the gst/python/encoder child
    bad=""
    for ((s=0; s<50; s++)); do alive=0; for p in "${pids[@]}"; do pgrep -s $p >/dev/null && alive=1; done; [ $alive = 0 ] && break; sleep 0.1; done
    if [ $alive = 1 ]; then
      bad="stuck after SIG$sig"; evidence $T/fail-$dev-$i $(for p in "${pids[@]}"; do pgrep -s $p; done)
      for p in "${pids[@]}"; do sudo pkill -KILL -s $p; done; sleep 1
    fi
    case $dev in disp-*) lo=$(pgrep -f 'fullscreen-output=' | tr '\n' ' '); [ -n "$lo" ] && { bad="$bad; leftover display client $lo (sudo pty)"; sudo pkill -KILL -f 'fullscreen-output='; sleep 1; } ;; esac
    for nd in $(devnode $dev); do h=$(sudo fuser $nd 2>/dev/null | tr -s ' '); [ -n "$h" ] && [ "$dev" != disp-hdmi ] && [ "$dev" != disp-dp ] && bad="$bad; $nd still held by$h"; done
    o=$T/out.$dev; rm -f $o; t1=$(date +%s.%N)
    timeout 30 bash -c "$(declare -f work); $(declare -p C T H264 H265 VP9 G1H264 G1VP8 G1MP2 AV1 RGA3 RGA2 IEP IEPDEV VENC NV12_1080 PY W); work $dev check $o"
    dt=$(awk -v a=$t1 -v b=$(date +%s.%N) 'BEGIN{printf "%.2f", b-a}')
    m=$(md5sum < $o 2>/dev/null | cut -c1-32)
    [ "$m" = "${REF[$dev]}" ] || bad="$bad; check job md5 $m != ref ${REF[$dev]} (${dt}s)"
    ke=$(kerr $t0); [ -n "$ke" ] && bad="$bad; kernel: $(echo "$ke" | head -3 | sed -E 's/^\[ *[0-9.]+\] //' | tr '\n' '|')"
    awk -v d=$dt -v m=$maxopen 'BEGIN{exit !(d>m)}' && maxopen=$dt
    if [ -z "$bad" ]; then pass=$((pass+1)); else
      fail=$((fail+1)); [ -z "$first" ] && { first="cycle $i (SIG$sig, $inst inst): $bad"; [ -d $T/fail-$dev-$i ] || evidence $T/fail-$dev-$i; }
      echo "$dev cycle $i: $bad" >> $T/failures.log
    fi
  done
  say "$dev: pass $pass / $N, fail $fail, slowest known-good check job (whole job, incl. open) ${maxopen}s${first:+; first failure: $first (evidence $T/fail-$dev-*)}"
done
[ -e $VP/ccu_hw ] && echo 1 | sudo tee $VP/pipeline $VP/ccu_hw >/dev/null
[ -n "$STARTED_WESTON" ] && sudo pkill -x weston
say "DONE $(date '+%F %T')"
