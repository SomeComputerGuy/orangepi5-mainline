#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# "Max out everything at once" on the Orange Pi 5. Runs ON the board, unattended, as the desktop user (uses sudo -n):
#   HDMI: stream A (HTTP) -> rkvdec -> waylandsink HDMI-A-1, tee -> RGA (2 stages) -> RGB 224x224 @15 fps -> NPU (Teflon)
#   DP:   stream B (HTTP) -> rkvdec -> waylandsink DP-1 (+ HDMI audio), tee -> raw NV12 -> VEPU580 HEVC encode (rkvenc-enc)
#   GPU:  glmark2-es2-wayland windowed, run forever
#   monitor every 5 s: temps, cpufreq, devfreq, CPU/irq/softirq, NIC, VOP underflows, IRQ rates, DDR bandwidth
# usage: maxout.sh [SECS=300] [URL_A] [URL_B]      report: ~/maxout/report.txt
# Needs: ~/maxout/{npu_analyze.py,ddrbw.c}, ~/demo/rkvenc-enc, ~/npu-venv, ~/npu/models. Abort if any zone > 95 C.
SECS=${1:-300}
BASE=http://${OPI5_HOST_IP:-172.31.55.1}:8099
A=${2:-$BASE/jellyfish-250-mbps-4k-uhd-h264.mkv}
B=${3:-$BASE/tears_of_steel_2160p_hevc.mp4}
D=$HOME/maxout; L=$D/run-$(date +%m%d-%H%M); mkdir -p $L; R=$D/report.txt; : > $R
say() { echo "$*" | tee -a $R; }
W="XDG_RUNTIME_DIR=/run/user/0 WAYLAND_DISPLAY=wayland-9"
PY="env PYTHONPATH=$HOME/npu-venv/lib/python3.14/site-packages python3"
MODEL=$HOME/npu/models/mobilenet_v1_1.0_224_quant.tflite; LABELS=$HOME/npu/models/imagenet_labels.txt
T0=$(cut -d' ' -f1 /proc/uptime)

# --- element selection by device name (names follow probe order, see GSTREAMER-FOLLOWUPS 3/8)
dev_of() { gst-inspect-1.0 "$1" 2>/dev/null | grep -oE '/dev/video[0-9]+' | head -1; }
is_dev() { local d; d=$(dev_of "$1"); [ -n "$d" ] && grep -q "$2" /sys/class/video4linux/$(basename $d)/name; }
dec_for() { for e in $(gst-inspect-1.0 v4l2codecs | grep -oE "v4l2sl[a-z0-9]*${1}dec" | sort -u); do is_dev $e rkvdec && { echo $e; return; }; done; }
conv_for() { for e in $(gst-inspect-1.0 video4linux2 | grep -oE 'v4l2[a-z0-9]*convert' | sort -u); do
  d=$(dev_of $e); [ -n "$d" ] && readlink -f /sys/class/video4linux/$(basename $d)/device | grep -q "$1" && { echo $e; return; }; done; }
demux_for() { case $1 in *.mkv) echo matroskademux;; *) echo qtdemux;; esac; }
probe() { ffprobe -v error -select_streams v:0 -show_entries stream=$2 -of csv=p=0 "$1"; }
codec_of() { [ "$(probe $1 codec_name)" = hevc ] && echo h265 || echo h264; }
height_of() { probe $1 height; }
FPSB=$(probe $B r_frame_rate | awk -F/ '{printf "%d", $1/$2+0.5}')
CA=$(codec_of $A); CB=$(codec_of $B); DECA=$(dec_for $CA); DECB=$(dec_for $CB)
RGA3=$(conv_for rk3588-rga3); RGA2=$(conv_for rk3288-rga); HB=$(height_of $B); HB=${HB:-2160}
say "# maxout $(date '+%F %T') $(uname -v) ${SECS}s"
say "# A=$A ($CA, $DECA) -> HDMI + NPU via $RGA3 + $RGA2;  B=$B ($CB, $DECB, 3840x$HB) -> DP + VEPU580"
[ -n "$DECA" ] && [ -n "$DECB" ] && [ -n "$RGA3" ] && [ -n "$RGA2" ] || { say "FATAL: element missing"; exit 1; }

# --- one-time: DDR PMU tool
[ -x $D/ddrbw ] || gcc -O2 -o $D/ddrbw $D/ddrbw.c

# --- weston (desktop shell; only one DRM master)
sudo pkill -INT -x gst-launch-1.0 2>/dev/null; sleep 1
printf '\e[?25l' | sudo tee /dev/tty1 >/dev/null 2>&1   # hide fbcon cursor (dp-smooth cause 2)
if ! pgrep -x weston >/dev/null; then
  sudo mkdir -p /run/user/0; sudo chmod 700 /run/user/0
  sudo env XDG_RUNTIME_DIR=/run/user/0 LIBSEAT_BACKEND=noop nohup weston --backend=drm --shell=desktop \
    --continue-without-input --idle-time=0 --socket=wayland-9 --log=$L/weston.log >/dev/null 2>&1 </dev/null &
  sleep 8; STARTED_WESTON=1
fi

pb() { sudo dmesg | grep -c POST_BUF_EMPTY; }
PB0=$(pb)
mkfifo $L/npu.fifo $L/enc.fifo
END=$(( $(date +%s) + SECS ))
left() { echo $(( END - $(date +%s) )); }
# loop <name> <function>: rerun the function (arg = iteration) until END; restarts counted in $L/<name>.runs
loop() { local i=0; while [ $(left) -gt 2 ]; do "$2" $i; i=$((i+1)); echo $i > $L/$1.runs; done; }
playA() {   # HDMI + NPU branch (two RGA stages: RGA3 max downscale is 1/8, 3840 -> 224 is 1/17)
  sudo env $W timeout $(left) gst-launch-1.0 -v souphttpsrc location="$A" ! queue2 use-buffering=true max-size-bytes=100000000 ! \
  $(demux_for $A) ! ${CA}parse ! queue ! $DECA ! tee name=t \
  t. ! queue ! fpsdisplaysink name=fpsA text-overlay=false sync=true signal-fps-measurements=true \
       video-sink="waylandsink fullscreen=true fullscreen-output=HDMI-A-1" \
  t. ! queue leaky=downstream max-size-buffers=2 ! videorate drop-only=true ! video/x-raw,framerate=15/1 ! \
       $RGA3 ! video/x-raw,format=NV12,width=960,height=540,colorimetry=bt709 ! $RGA2 ! video/x-raw,format=RGB,width=224,height=224 ! \
       filesink location=$L/npu.fifo sync=false buffer-mode=unbuffered >$L/A.$1.log 2>&1 </dev/null; }
playB() {   # DP + HDMI audio + raw NV12 into the encoder FIFO
  sudo env $W timeout $(left) gst-launch-1.0 -v souphttpsrc location="$B" ! queue2 use-buffering=true max-size-bytes=100000000 ! \
  $(demux_for $B) name=d d. ! ${CB}parse ! queue ! $DECB ! tee name=t \
  t. ! queue ! fpsdisplaysink name=fpsB text-overlay=false sync=true signal-fps-measurements=true \
       video-sink="waylandsink fullscreen=true fullscreen-output=DP-1" \
  t. ! queue leaky=downstream max-size-buffers=4 ! video/x-raw,format=NV12 ! filesink location=$L/enc.fifo sync=false buffer-mode=unbuffered \
  d. ! queue ! decodebin ! audioconvert ! audioresample ! alsasink device=plughw:hdmi0 \
  >$L/B.$1.log 2>&1 </dev/null; }
encB() { sudo timeout $(( $(left) + 5 )) ~/demo/rkvenc-enc -e hevc -i $L/enc.fifo -o /dev/null -w 3840 -h $HB -n 1000000 \
  -f ${FPSB:-30} -g 60 -b 40000000 >$L/enc.$1.log 2>&1; }
gpu() { sudo env $W timeout $(left) glmark2-es2-wayland --size 960x540 --run-forever >>$L/glmark2.log 2>&1 </dev/null; }
LOOPS=()
$PY $D/npu_analyze.py $MODEL $LABELS $L/npu.log --fifo $L/npu.fifo --stopfile $L/stop 2>$L/npu.err &
NPID=$!
loop A playA & LOOPS+=($!)
loop enc encB & LOOPS+=($!)
loop B playB & LOOPS+=($!)
sleep 3
loop gpu gpu & LOOPS+=($!)
sudo $D/ddrbw $((SECS+5)) > $L/ddr.log 2>&1 &
DPID=$!

# --- monitor
irqs() { awk 'BEGIN{m["fdc38000.video-codec"]="dec0";m["fdc40000.video-codec"]="dec1";m["fdbd0000.video-codec"]="enc0";
  m["fdbe0000.video-codec"]="enc1";m["fdab0000.npu"]="npu0";m["fdac0000.npu"]="npu1";m["fdad0000.npu"]="npu2";m["panthor-gpu"]="gpu";
  m["fdd90000.vop"]="vop";m["fdb60000.rga"]="rga3a";m["fdb70000.rga"]="rga3b";m["fdb80000.rga"]="rga2"}
  ($NF in m){s=0; for(i=2;i<=9;i++) s+=$i; c[m[$NF]]+=s} END{for(k in c) printf "irq_%s=%d ", k, c[k]}' /proc/interrupts; }
cpu() { awk '/^cpu /{print $2+$3+$4+$5+$6+$7+$8, $5+$6, $7+$8}' /proc/stat; }
nic() { awk '/end0:/{print $2, $4, $5}' /proc/net/dev; }
temps() { for z in /sys/class/thermal/thermal_zone*; do printf '%s=%d ' $(cat $z/type) $(( $(cat $z/temp)/1000 )); done; }
maxtemp() { cat /sys/class/thermal/thermal_zone*/temp | sort -n | tail -1; }
freqs() { for p in /sys/devices/system/cpu/cpufreq/policy*; do printf '%s=%d ' $(basename $p) $(( $(cat $p/scaling_cur_freq)/1000 )); done
          for f in /sys/class/devfreq/*; do printf '%s=%d ' $(basename $f) $(( $(cat $f/cur_freq)/1000000 )); done; }
M=$L/mon.log; c0=($(cpu)); n0=($(nic)); ABORT=
for ((t=5; t<=SECS; t+=5)); do
  sleep 5
  c1=($(cpu)); n1=($(nic)); dt=$((c1[0]-c0[0])); [ $dt -gt 0 ] || dt=1
  echo "t=$t busy=$((100-100*(c1[1]-c0[1])/dt))% irqsoft=$((100*(c1[2]-c0[2])/dt))% net=$(( (n1[0]-n0[0])*8/5/1000000 ))Mbit rx_err=${n1[1]} rx_drop=${n1[2]} pb=$(( $(pb)-PB0 )) $(temps)$(freqs)$(irqs)" >> $M
  c0=(${c1[@]}); n0=(${n1[@]})
  [ $(maxtemp) -gt 95000 ] && { ABORT="thermal abort at t=$t ($(maxtemp))"; break; }
done
# --- stop cleanly
touch $L/stop; kill "${LOOPS[@]}" 2>/dev/null
sudo pkill -INT -x gst-launch-1.0; sudo pkill -INT -x glmark2-es2-wayland; sleep 4
sudo pkill -x gst-launch-1.0; sudo pkill -x rkvenc-enc; sudo pkill -x glmark2-es2-wayland; sudo pkill -x ddrbw
sleep 1; kill $NPID 2>/dev/null; wait $NPID 2>/dev/null
[ -n "$STARTED_WESTON" ] && sudo pkill -x weston
printf '\e[?25h' | sudo tee /dev/tty1 >/dev/null 2>&1

# --- report
say "${ABORT:-ran full ${SECS}s}"
lastfps() { grep -oE 'rendered: [0-9]+, dropped: [0-9]+' $1 | tail -1 | grep -oE '[0-9]+' | tr '\n' ' '; }
for s in A B; do
  tot=$(for f in $L/$s.*.log; do lastfps $f; echo; done | awk '{r+=$1; d+=$2; n++} END{printf "rendered %d dropped %d over %d runs", r, d, n}')
  say "stream $s: $tot; per run: $(for f in $L/$s.*.log; do printf '[%s] ' "$(lastfps $f)"; done) $(cat $L/$s.*.log | grep -m1 -oE 'ERROR.*' | cut -c1-100)"
done
say "NPU: $(tail -1 $L/npu.log)  mean inf/s $(awk '/^SEC/{split($3,a,"=");s+=a[2];n++} END{if(n)printf "%.1f",s/n}' $L/npu.log)  lat $(awk '/^SEC/{split($4,a,"=");s+=a[2];n++} END{if(n)printf "%.1f ms",s/n}' $L/npu.log)"
say "NPU top labels: $(grep '^SEC' $L/npu.log | sed -E 's/.* top=//; s/,.*|\(.*//' | sort | uniq -c | sort -rn | head -5 | tr '\n' ';')"
say "encoder: $(cat $L/enc.*.log | awk '/^encoded/{f+=$2; t+=$5; n++} /feedback errors/{e+=$3} END{printf "%d frames in %.0f s = %.1f fps over %d runs, feedback errors %d", f, t, (t?f/t:0), n, e}')"
say "restarts (runs): A=$(cat $L/A.runs 2>/dev/null) B=$(cat $L/B.runs 2>/dev/null) enc=$(cat $L/enc.runs 2>/dev/null) gpu=$(cat $L/gpu.runs 2>/dev/null) npu-reopens=$(grep -c REOPEN $L/npu.log)"
say "GPU glmark2: $(grep -oE 'FPS: [0-9]+' $L/glmark2.log | awk '{s+=$2;n++} END{if(n)printf "mean %.0f fps over %d scenes",s/n,n}')"
say "DDR: $(awk '{r+=$2; w+=$4; n++; if($2>mr)mr=$2} END{if(n)printf "rd mean %.0f max %.0f MB/s, wr mean %.0f MB/s",r/n,mr,w/n}' $L/ddr.log)"
say "VOP POST_BUF_EMPTY during run: $(( $(pb)-PB0 ))"
say "max temp: $(grep -oE '[a-z0-9_-]+thermal=[0-9]+' $M | awk -F= '{if($2>m[$1])m[$1]=$2} END{for(k in m) printf "%s %d; ",k,m[k]}')"
say "--- per-minute summary (5-s samples; enc/dec/npu/gpu = IRQs per s, pb = cumulative underflows)"
say "t_s busy% irqsoft% net_Mbit maxT_C cpu4/6_MHz gpu_MHz npu_MHz enc/s dec/s npu/s gpu/s pb"
awk '{for(i=1;i<=NF;i++){split($i,kv,"="); v[kv[1]]=kv[2]+0}
  mt=0; for(k in v) if (k ~ /thermal$/ && v[k]>mt) mt=v[k]
  t=v["t"]; e=v["irq_enc0"]+v["irq_enc1"]; dd=v["irq_dec0"]+v["irq_dec1"]; np=v["irq_npu0"]+v["irq_npu1"]+v["irq_npu2"]; g=v["irq_gpu"]
  if (t%60==0 && pt!="") printf "%d %d %d %d %d %d/%d %d %d %.0f %.0f %.0f %.0f %d\n", t, v["busy"], v["irqsoft"], v["net"], mt,
     v["policy4"], v["policy6"], v["fb000000.gpu"], v["fdab0000.npu"], (e-pe)/(t-pt), (dd-pd)/(t-pt), (np-pn)/(t-pt), (g-pg)/(t-pt), v["pb"]
  if (t%60==0 || pt=="") {pt=t; pe=e; pd=dd; pn=np; pg=g}
  delete v}' $M | tee -a $R
say "--- new kernel messages:"; sudo dmesg | awk -v t="$T0" '{x=$1; gsub(/[][]/,"",x); if (x+0>t) print}' | \
  grep -iE 'error|fault|timeout|fail|warn|POST_BUF|iommu|rocket|panthor|rkvdec|venc' | sed -E 's/^\[ *[0-9.]+\] //' | sort | uniq -c | sort -rn | head -20 >> $R
say "logs: $L"
