#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# "Max out everything at once" on the Orange Pi 5. Runs ON the board, unattended (uses sudo -n).
#   maxout.sh [SECS=900] [URL_A] [URL_B]       report: ~/maxout/report.txt, logs ~/maxout/run-MMDD-HHMM/
# All at the same time, for SECS:
#   HDMI: stream A (HTTP, default Jellyfish 250 Mbit/s H.264) -> rkvdec -> waylandsink fullscreen, looping in ONE pipeline
#         (stream.py, segment seeks), tee -> RGA3 -> RGA2 -> 224x224 RGB -> NPU (Teflon MobileNet v1), CPU cross-check
#   DP:   stream B (HTTP, default Tears of Steel 4K HEVC) -> rkvdec -> waylandsink fullscreen + HDMI audio,
#         tee -> RGA (hardware copy, dma-buf) -> fd over a unix socket -> VEPU580 HEVC encode (tools/rkvenc-enc -s, zero CPU copy)
#   webcam 4K30 MJPEG -> rkjpegd -> RGA -> VEPU580 HEVC QP19 -> 150-s segments on the SD card (dock) + NPU on the camera
#         (cam-record.sh), each closed segment decode-checked and copied SD <-> USB stick with sha256
#   storage: copy-agg.sh (sha256-verified copies SD <-> USB stick both ways), unless one is already running
#   GPU:  glmark2-es2-wayland windowed, restarted if it exits
#   monitor every 5 s; abort if any thermal zone > 100 C (ABORT_MC; trips: passive 85, critical 115). Side branches are leaky so they can't stall playback.
SECS=${1:-900}
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
CA=$(codec_of $A); CB=$(codec_of $B); DECA=$(dec_for $CA); DECB=$(dec_for $CB)
RGA3=$(conv_for rk3588-rga3); RGA2=$(conv_for rk3288-rga); HB=$(probe $B height); HB=${HB:-2160}
FPSB=$(probe $B r_frame_rate | awk -F/ '{printf "%d", $1/$2+0.5}')
say "# maxout $(date '+%F %T') $(uname -v) ${SECS}s"
say "# A=$A ($CA, $DECA) -> HDMI + NPU via $RGA3+$RGA2;  B=$B ($CB, $DECB, 3840x$HB@$FPSB) -> DP + audio + VEPU580"
[ -n "$DECA" ] && [ -n "$DECB" ] && [ -n "$RGA3" ] && [ -n "$RGA2" ] || { say "FATAL: element missing"; exit 1; }
[ -x $D/ddrbw ] || gcc -O2 -o $D/ddrbw $D/ddrbw.c

# --- weston (desktop shell; only one DRM master)
if ! pgrep -x weston >/dev/null; then
  sudo mkdir -p /run/user/0; sudo chmod 700 /run/user/0
  sudo env XDG_RUNTIME_DIR=/run/user/0 LIBSEAT_BACKEND=noop nohup weston --backend=drm --shell=desktop \
    --continue-without-input --idle-time=0 --socket=wayland-9 --log=$L/weston.log >/dev/null 2>&1 </dev/null &
  sleep 8; STARTED_WESTON=1
fi
pb() { sudo dmesg | grep -c POST_BUF_EMPTY; }
PB0=$(pb)
END=$(( $(date +%s) + SECS ))
left() { echo $(( END - $(date +%s) )); }
loop() { local i=0; while [ $(left) -gt 2 ]; do "$2" $i; i=$((i+1)); echo $i > $L/$1.runs; done; }

sudo env $W $PY $D/stream.py "$A" HDMI-A-1 $L/A.log --codec $CA --dec $DECA --npu $MODEL $LABELS --rga $RGA3 $RGA2 \
  --npu-fps 15 --secs $SECS > $L/A.out 2>&1 &
sudo env $W $PY $D/stream.py "$B" DP-1 $L/B.log --codec $CB --dec $DECB --audio plughw:hdmi0 --rga $RGA3 $RGA2 --secs $SECS \
  --enc "$D/tools/rkvenc-enc -e hevc -s $L/encB.sock -o /dev/null -w 3840 -h $HB -f ${FPSB:-30} -g 60 -b 40000000" --enc-sock $L/encB.sock \
  > $L/B.out 2>&1 &
sleep 3
bash $D/cam-record.sh $SECS 19 > $L/cam.out 2>&1 &
pgrep -f "copy-ag[g].sh" >/dev/null && say "# copy-agg already running (its log: ~/copyagg)" || { bash $D/copy-agg.sh $SECS 4 2 > $L/copyagg.out 2>&1 & }
gpu() { sudo env $W timeout $(left) glmark2-es2-wayland --size 960x540 --run-forever >>$L/glmark2.log 2>&1 </dev/null; }
loop gpu gpu & GL=$!
sudo $D/ddrbw $((SECS+5)) > $L/ddr.log 2>&1 &

# --- monitor
irqs() { awk 'BEGIN{m["fdc38000.video-codec"]="dec0";m["fdc40000.video-codec"]="dec1";m["fdbd0000.video-codec"]="enc0";
  m["fdbe0000.video-codec"]="enc1";m["fdab0000.npu"]="npu0";m["fdac0000.npu"]="npu1";m["fdad0000.npu"]="npu2";m["panthor-gpu"]="gpu";
  m["fdd90000.vop"]="vop";m["fdb60000.rga"]="rga3a";m["fdb70000.rga"]="rga3b";m["fdb80000.rga"]="rga2";m["fdb90000.video-codec"]="jpegd"}
  ($NF in m){s=0; for(i=2;i<=9;i++) s+=$i; c[m[$NF]]+=s} END{for(k in c) printf "irq_%s=%d ", k, c[k]}' /proc/interrupts; }
cpu() { awk '/^cpu /{print $2+$3+$4+$5+$6+$7+$8, $5+$6, $7+$8}' /proc/stat; }
nic() { awk '/end0:/{print $2, $4, $5}' /proc/net/dev; }
disk() { local d=$(basename $(readlink -f /dev/disk/by-label/$1 2>/dev/null) 2>/dev/null); awk -v d=$d '$3==d{print $6+$10}' /proc/diskstats; }
temps() { for z in /sys/class/thermal/thermal_zone*; do printf '%s=%d ' $(cat $z/type) $(( $(cat $z/temp)/1000 )); done; }
maxtemp() { cat /sys/class/thermal/thermal_zone*/temp | sort -n | tail -1; }
freqs() { for p in /sys/devices/system/cpu/cpufreq/policy*; do printf '%s=%d ' $(basename $p) $(( $(cat $p/scaling_cur_freq)/1000 )); done
          for f in /sys/class/devfreq/*; do printf '%s=%d ' $(basename $f) $(( $(cat $f/cur_freq)/1000000 )); done; }
M=$L/mon.log; c0=($(cpu)); n0=($(nic)); s0=$(disk OPI5SCRATCH-SD); u0=$(disk OPI5SCRATCH-USB); ABORT=
for ((t=5; t<=SECS; t+=5)); do
  sleep 5
  c1=($(cpu)); n1=($(nic)); s1=$(disk OPI5SCRATCH-SD); u1=$(disk OPI5SCRATCH-USB); dt=$((c1[0]-c0[0])); [ $dt -gt 0 ] || dt=1
  echo "t=$t busy=$((100-100*(c1[1]-c0[1])/dt))% irqsoft=$((100*(c1[2]-c0[2])/dt))% net=$(( (n1[0]-n0[0])*8/5/1000000 ))Mbit rx_err=${n1[1]} rx_drop=${n1[2]} sd=$(( (${s1:-0}-${s0:-0})*512/5/1000000 ))MB/s usb=$(( (${u1:-0}-${u0:-0})*512/5/1000000 ))MB/s pb=$(( $(pb)-PB0 )) $(temps)$(freqs)$(irqs)" >> $M
  c0=(${c1[@]}); n0=(${n1[@]}); s0=$s1; u0=$u1
  [ $(maxtemp) -gt ${ABORT_MC:-100000} ] && { ABORT="thermal abort at t=$t ($(maxtemp) m°C > ${ABORT_MC:-100000})"; say "$ABORT"; break; }
done
# --- stop cleanly (stream.py and cam-record stop themselves at SECS; this catches an abort)
kill $GL 2>/dev/null; sudo pkill -INT -x glmark2-es2-wayland
[ -n "$ABORT" ] && { sudo pkill -INT -f "maxout/stream[.]py"; pkill -f "cam-recor[d].sh"; }
sleep 10; sudo pkill -x ddrbw
for ((s=0; s<120; s++)); do pgrep -f "maxout/stream[.]py" >/dev/null || break; sleep 1; done
for ((s=0; s<600; s++)); do pgrep -f "cam-recor[d].sh" >/dev/null || break; sleep 1; done   # segment checks finish
[ -n "$STARTED_WESTON" ] && sudo pkill -x weston

# --- report
say "${ABORT:-ran full ${SECS}s}"
for s in A B; do say "stream $s: $(grep TOTAL $L/$s.log | cut -d' ' -f3-)  $(grep -E ' (ERROR|ENCDIED|NPUERROR)' $L/$s.log | head -2 | cut -c1-120 | tr '\n' '|')"; done
say "stream A per-s fps: $(awk '$2=="SEC"{split($5,f,"="); n++; s+=f[2]; if(min==""||f[2]<min)min=f[2]} END{printf "mean %.1f min %d over %d s", s/n, min, n}' $L/A.log)"
say "stream B per-s fps: $(awk '$2=="SEC"{split($5,f,"="); n++; s+=f[2]; if(min==""||f[2]<min)min=f[2]} END{printf "mean %.1f min %d over %d s", s/n, min, n}' $L/B.log)"
say "NPU on stream A: $(awk '$2=="SEC"{for(i=3;i<=NF;i++){split($i,kv,"="); if(kv[1]=="npu_inf/s"){s+=kv[2];n++} if(kv[1]=="npu_lat"){l+=kv[2]}}} END{printf "%.1f inf/s, %.1f ms", s/n, l/n}' $L/A.log); top labels: $(grep -oE 'npu_top=[^ (]+' $L/A.log | sort | uniq -c | sort -rn | head -4 | awk '{printf "%s %s; ", $2, $1}' | sed 's/npu_top=//g')"
say "$(grep '^camera NPU' ~/camrec/report.txt)"
say "B encoder: $(awk '$2=="SEC"{for(i=3;i<=NF;i++){split($i,kv,"="); if(kv[1]=="enc_fps"){s+=kv[2];n++}}} END{printf "%.1f fps mean", s/n}' $L/B.log) $(grep -oE 'enc_frames=[0-9]+ enc_drop=[0-9]+ enc_restarts=[0-9]+' $L/B.log | tail -1)"
say "camera: $(grep -E '^camera:|^camera per-s|^encoder:|^quality' ~/camrec/report.txt | tr '\n' ' ')"
say "camera segments: $(grep -c '^seg' ~/camrec/report.txt) checked, $(grep '^seg' ~/camrec/report.txt | grep -c CORRUPT) corrupt; $(grep '^seg' ~/camrec/report.txt | cut -c1-120 | tr '\n' '|')"
say "copy-agg: $(awk '$7=="ok"{c[$2]++; s[$2]+=$6} $7 ~ /CORRUPT/{bad++} END{for(k in c) printf "%s %d ok (%.1f MB/s); ", k, c[k], s[k]/c[k]; printf "CORRUPT %d", bad}' ~/copyagg/copies.log)"
say "GPU glmark2: $(grep -oE 'FPS: [0-9]+' $L/glmark2.log | awk '{s+=$2;n++} END{if(n)printf "mean %.0f fps over %d scenes",s/n,n}'), restarts $(cat $L/gpu.runs 2>/dev/null)"
say "DDR: $(awk '{r+=$2; w+=$4; n++; if($2>mr)mr=$2} END{if(n)printf "rd mean %.0f max %.0f MB/s, wr mean %.0f MB/s",r/n,mr,w/n}' $L/ddr.log)"
say "VOP POST_BUF_EMPTY during run: $(( $(pb)-PB0 ))"
say "max temp: $(grep -oE '[a-z0-9_-]+thermal=[0-9]+' $M | awk -F= '{if($2>m[$1])m[$1]=$2} END{for(k in m) printf "%s %d; ",k,m[k]}')"
say "--- per-minute summary (5-s samples; enc/dec/npu/gpu/jpegd = IRQs per s, pb = cumulative underflows)"
say "t_s busy% irqsoft% net_Mbit sd_MB/s usb_MB/s maxT_C cpu0/4/6_MHz gpu_MHz npu_MHz enc/s dec/s jpegd/s npu/s gpu/s pb"
awk '{for(i=1;i<=NF;i++){split($i,kv,"="); v[kv[1]]=kv[2]+0}
  mt=0; for(k in v) if (k ~ /thermal$/ && v[k]>mt) mt=v[k]
  t=v["t"]; e=v["irq_enc0"]+v["irq_enc1"]; dd=v["irq_dec0"]+v["irq_dec1"]; np=v["irq_npu0"]+v["irq_npu1"]+v["irq_npu2"]; g=v["irq_gpu"]; j=v["irq_jpegd"]
  if (t%60==0 && pt!="") printf "%d %d %d %d %d %d %d %d/%d/%d %d %d %.0f %.0f %.0f %.0f %.0f %d\n", t, v["busy"], v["irqsoft"], v["net"], v["sd"], v["usb"], mt,
     v["policy0"], v["policy4"], v["policy6"], v["fb000000.gpu"], v["fdab0000.npu"], (e-pe)/(t-pt), (dd-pd)/(t-pt), (j-pj)/(t-pt), (np-pn)/(t-pt), (g-pg)/(t-pt), v["pb"]
  if (t%60==0 || pt=="") {pt=t; pe=e; pd=dd; pn=np; pg=g; pj=j}
  delete v}' $M | tee -a $R
say "--- new kernel messages:"; sudo dmesg | awk -v t="$T0" '{x=$1; gsub(/[][]/,"",x); if (x+0>t) print}' | \
  grep -iE 'error|fault|timeout|fail|warn|POST_BUF|iommu|rocket|panthor|rkvdec|venc|reset|disconnect' | sed -E 's/^\[ *[0-9.]+\] //' | sort | uniq -c | sort -rn | head -20 >> $R
say "logs: $L"
