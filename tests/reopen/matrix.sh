#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Reopen matrix: block A streams steadily (output checked) while block B cycles
# open -> stream K frames -> close as fast as it can, for every pair (A, B), including A == B
# (a second context on the same block). Runs ON the board from ~/reopen (mx.py, npu-loop.py,
# venc-cycle next to it).
#
#   matrix.sh prep                      make the test media and reference checksums (once per boot)
#   matrix.sh pair A B VARIANT [N]       one pair; VARIANT: normal | kill | abort | restart
#   matrix.sh chunk NAME "A:B:V[:N] ..."  several pairs, one results table (results/NAME/table.md)
#   matrix.sh all [N]                    print the chunk plan for every pair (<= 45 min each)
#
# Variants for B: normal = EOS after K frames and close; kill = SIGKILL mid-stream; abort = close
# with buffers still queued (decoders: pipeline to NULL mid-stream; encoders: exit with jobs in
# flight); restart = STREAMOFF/STREAMON without closing (decoders: flushing seek; encoders: -k).
# A must not stall (gap > 2 x period), mismatch its reference, error or make the kernel log a
# warning; B must never fail to open or start, and its output must match its reference too.
set -u
D=$(cd "$(dirname "$0")" && pwd); M=$D/media; R=$D/results; mkdir -p $M $R
export GST_REGISTRY=/tmp/mx-reg.$(cut -c1-8 /proc/sys/kernel/random/boot_id).bin
export GST_DEBUG_NO_COLOR=1
NPUPY="env PYTHONPATH=$HOME/npu-venv/lib/python3.14/site-packages python3 $D/npu-loop.py"
MODEL=$HOME/npu/models/mobilenet_v1_1.0_224_quant.tflite
DEMO=$HOME/demo

# ---- devices, resolved by name every boot (probe order changes)
vdev() { for d in /sys/class/video4linux/video*; do grep -q -- "$1" $d/name 2>/dev/null && { echo /dev/$(basename $d); return; }; done; }
vdev_path() { for d in /sys/class/video4linux/video*; do readlink -f $d/device | grep -q -- "$1" && { echo /dev/$(basename $d); return; }; done; }
el_dev() { gst-inspect-1.0 "$1" 2>/dev/null | grep -oE '/dev/video[0-9]+' | head -1; }
dec_el() {   # dec_el CODEC DEVNAME
  for e in $(gst-inspect-1.0 v4l2codecs | grep -oE "v4l2sl[a-z0-9]*${1}dec" | sort -u); do
    d=$(el_dev $e); [ -n "$d" ] && grep -q -- "$2" /sys/class/video4linux/$(basename $d)/name && { echo $e; return; }; done; }
conv_el() {  # conv_el DEVICE-PATH-SUBSTRING
  for e in $(gst-inspect-1.0 video4linux2 | grep -oE 'v4l2[a-z0-9]*convert' | sort -u); do
    d=$(el_dev $e); [ -n "$d" ] && readlink -f /sys/class/video4linux/$(basename $d)/device | grep -q -- "$1" && { echo $e; return; }; done; }
cam_dev() { for d in /dev/v4l/by-id/*video-index0; do readlink -f $d; return; done; }

CHK="video/x-raw,format=NV12 ! fakesink name=chk sync=false"   # mx.py: CRC32 of the visible pixels of each frame
gdec() {  # gdec FILE DEMUX PARSE ELEMENT
  echo "filesrc location=$1 ! $2 ! $3 ! $4 ! identity eos-after={K} ! $CHK"; }

# ---- block table: KIND (gst|venc|cmd|npu), steady/cycle descriptions, period (s), frames per cycle
declare -A KIND DESC PER KF KA NOTE
define_blocks() {
  local RK=rkvdec HA=vpu121-dec
  local e
  # 4K (the original failure: 4K H.264 on rkvdec). A restarts every KA frames (its reference length).
  e=$(dec_el h264 $RK); KIND[rkvdec-h264]=gst; DESC[rkvdec-h264]=$(gdec $DEMO/jellyfish-120-mbps-4k-uhd-h264.mkv matroskademux h264parse "$e"); KF[rkvdec-h264]=10; KA[rkvdec-h264]=600
  e=$(dec_el h265 $RK); KIND[rkvdec-hevc]=gst; DESC[rkvdec-hevc]=$(gdec $DEMO/yacht_hevc_2160p120_loop.mp4 qtdemux h265parse "$e"); KF[rkvdec-hevc]=10; KA[rkvdec-hevc]=600
  e=$(dec_el vp9 $RK);  KIND[rkvdec-vp9]=gst;  DESC[rkvdec-vp9]=$(gdec $DEMO/yacht_vp9_2160p120.webm matroskademux vp9parse "$e"); KF[rkvdec-vp9]=10; KA[rkvdec-vp9]=600
  e=$(dec_el h264 $HA); KIND[hantro-h264]=gst; DESC[hantro-h264]=$(gdec $DEMO/yacht_h264_1080p120.mp4 qtdemux h264parse "$e"); KF[hantro-h264]=30
  e=$(dec_el vp8 $HA);  KIND[hantro-vp8]=gst;  DESC[hantro-vp8]=$(gdec $DEMO/yacht_vp8_1080p120.webm matroskademux identity "$e"); KF[hantro-vp8]=30
  e=$(dec_el mpeg2 $HA); KIND[hantro-mpeg2]=gst; DESC[hantro-mpeg2]=$(gdec $DEMO/yacht_mpeg2_1080p120.mpg parsebin identity "$e"); KF[hantro-mpeg2]=30
  e=$(dec_el av1 av1-vpu); KIND[av1]=gst; DESC[av1]=$(gdec $DEMO/yacht_av1_1080p120.mkv matroskademux av1parse "$e"); KF[av1]=30
  KIND[jpegdec]=gst; DESC[jpegdec]=$(gdec $M/mjpeg_1080.avi avidemux jpegparse v4l2jpegdec | sed "s|video/x-raw,format=NV12 ! fakesink|video/x-raw ! fakesink|"); KF[jpegdec]=30
  local r3 r2; r3=$(conv_el rk3588-rga3); r2=$(conv_el rk3288-rga)
  for x in rga3:$r3 rga2:$r2; do
    KIND[${x%%:*}]=gst; KF[${x%%:*}]=30
    DESC[${x%%:*}]="videotestsrc pattern=smpte num-buffers=600 ! video/x-raw,format=NV12,width=1920,height=1080,framerate=60/1 ! identity eos-after={K} ! ${x#*:} ! video/x-raw,format=NV12,width=1280,height=720 ! $CHK"
  done
  KIND[jpegenc]=gst; KF[jpegenc]=30
  DESC[jpegenc]="videotestsrc pattern=smpte num-buffers=600 ! video/x-raw,format=NV12,width=1280,height=720,framerate=30/1 ! identity eos-after={K} ! v4l2jpegenc ! jpegdec ! videoconvert ! $CHK"
  local cam; cam=$(cam_dev)
  KIND[camera]=gst; KF[camera]=10; NOTE[camera]="UVC MJPEG 1080p30, frame timing only (live: no md5)"
  DESC[camera]="v4l2src device=$cam num-buffers=-1 ! image/jpeg,width=1920,height=1080,framerate=30/1 ! identity eos-after={K} ! fakesink name=chk sync=false"
  local venc v121; venc=$(vdev rockchip-venc); v121=$(vdev rk3588-vpu121-enc)   # H.264: "vpu121-enc"; "vepu121-enc" is the JPEG encoder
  local VA="$D/venc-cycle -i $DEMO/yacht_1080p.nv12 -o /dev/null -w 1920 -h 1080 -g 30 -q 30 -j 2 -f 60"
  KIND[vepu580-h264]=venc; DESC[vepu580-h264]="$VA -d $venc -e h264"; KF[vepu580-h264]=30
  KIND[vepu580-hevc]=venc; DESC[vepu580-hevc]="$VA -d $venc -e hevc"; KF[vepu580-hevc]=30
  KIND[vepu121-h264]=venc; DESC[vepu121-h264]="$VA -d $v121 -e h264 -p 77"; KF[vepu121-h264]=30
  KIND[iep]=cmd; KF[iep]=1
  DESC[iep]="$HOME/maxout/iep-test -d $(vdev rockchip-iep) -i $M/iep_1080.nv12 -o \$OUT -w 1920 -h 1080 -f nv12 -F tb -m ma -n 10"
  KIND[npu]=npu; KF[npu]=10
  KIND[gpu]=cmd; KF[gpu]=1; NOTE[gpu]="glmark2 off-screen, exit status + FPS only (no image check)"
  DESC[gpu]="glmark2-es2-drm --off-screen -s 640x360 -b texture:duration=1"
}
BLOCKS="rkvdec-h264 rkvdec-hevc rkvdec-vp9 hantro-h264 hantro-vp8 hantro-mpeg2 av1 jpegdec rga3 rga2 jpegenc camera vepu580-h264 vepu580-hevc vepu121-h264 iep npu gpu"

ref_of() { echo $M/ref.$1; }
md5arg() { [ -s $M/ref.$1 ] && echo --md5 $M/ref.$1; }
per_of() { cat $M/period.$1 2>/dev/null || echo 0.1; }

# ---- prep: media, references, solo periods (99th percentile frame interval, alone)
prep() {  # prep [BLOCKS]
  define_blocks
  [ -s $M/mjpeg_1080.avi ] || ffmpeg -v error -y -f rawvideo -pix_fmt nv12 -s 1920x1080 -r 30 -i $DEMO/yacht_1080p.nv12 \
      -frames:v 300 -c:v mjpeg -q:v 3 -pix_fmt yuvj420p $M/mjpeg_1080.avi
  [ -s $M/iep_1080.nv12 ] || head -c $((1920*1080*3/2*10)) $DEMO/yacht_1080p.nv12 > $M/iep_1080.nv12
  for b in ${1:-$BLOCKS}; do
    case ${KIND[$b]} in
      gst) [ $b = camera ] && { echo 0.0333 > $M/period.$b; continue; }
           python3 $D/mx.py ref "${DESC[$b]}" $(ref_of $b) --ka ${KA[$b]:--1} > $M/refrun.$b.json
           python3 $D/mx.py ref "${DESC[$b]}" $(ref_of $b).k --ka ${KF[$b]} > $M/refrun.$b.k.json
           # solo period: the steady role alone for one run (stop after 8 s)
           rm -f /tmp/mx.stop; ( sleep 8; touch /tmp/mx.stop ) &
           python3 $D/mx.py steady "${DESC[$b]}" --ref $(ref_of $b) --period 10 --stop /tmp/mx.stop --ka ${KA[$b]:--1} > $M/solo.$b.json 2>/dev/null
           python3 -c "import json; d=json.load(open('$M/solo.$b.json')); print(max(d['max_gap_ms'],20)/1000)" > $M/period.$b ;;
      venc) python3 $D/mx.py vref "${DESC[$b]} -n 600" $(ref_of $b) > $M/refrun.$b.json; echo $(awk 'BEGIN{print 1/60}') > $M/period.$b ;;
      cmd) [ $b = iep ] && { eval "${DESC[$b]/\$OUT/$M/iep.out}" >/dev/null 2>&1; md5sum $M/iep.out | cut -d' ' -f1 > $(ref_of $b); }
           s=$(date +%s.%N); eval "${DESC[$b]/\$OUT/\/dev\/null}" >/dev/null 2>&1; e=$(date +%s.%N)
           awk -v s=$s -v e=$e 'BEGIN{print e-s}' > $M/period.$b ;;
      npu) $NPUPY ref $MODEL > $M/refrun.$b.json; echo 0.1 > $M/period.$b ;;
    esac
    echo "prep $b: kind=${KIND[$b]} period=$(per_of $b) $(cat $M/refrun.$b.json 2>/dev/null | cut -c1-120)"
  done
}

# ---- steady A in the background; prints its JSON into $1 when the stop file appears
start_steady() {  # start_steady BLOCK OUTFILE STOPFILE
  local b=$1 o=$2 s=$3 p; p=$(per_of $b)
  case ${KIND[$b]} in
    gst)  python3 $D/mx.py steady "${DESC[$b]}" --ref $(ref_of $b) --period $p --stop $s --ka ${KA[$b]:--1} > $o 2>$o.log & ;;
    venc) python3 $D/mx.py vsteady "${DESC[$b]} -R" --ref $(ref_of $b) --period $p --stop $s --wrap 600 > $o 2>$o.log & ;;
    cmd)  python3 $D/mx.py csteady "${DESC[$b]}" --period $p --stop $s $(md5arg $b) > $o 2>$o.log & ;;
    npu)  $NPUPY steady $MODEL --stop $s --period 0.1 > $o 2>$o.log & ;;
  esac
  STEADY_PID=$!
}

run_cycle() {  # run_cycle BLOCK VARIANT N  -> JSON on stdout
  local b=$1 v=$2 n=$3 k=${KF[$1]}
  case ${KIND[$b]} in
    gst)  local gv=$v; [ $v = abort ] && gv=nullmid; [ $v = restart ] && gv=flush
          python3 $D/mx.py cycle "${DESC[$b]}" --ref $(ref_of $b).k --frames $k --cycles $n --variant $gv ;;
    venc) python3 $D/mx.py vcycle "${DESC[$b]}" --ref $(ref_of $b) --frames $k --cycles $n --variant $v ;;
    cmd)  case $v in
            kill) python3 $D/mx.py ccycle "${DESC[$b]}" --cycles $n --kill 1.0 ;;
            restart) [ $b = iep ] && python3 $D/mx.py ccycle "${DESC[$b]/-n 10/-n 10 -c 20}" --cycles $((n / 20 + 1)) \
                       || echo '{"role":"ccycle","skipped":"no restart variant"}' ;;
            *) python3 $D/mx.py ccycle "${DESC[$b]}" --cycles $n $(md5arg $b) ;;
          esac ;;
    npu)  case $v in kill) $NPUPY cycle $MODEL --cycles $n --frames $k --kill ;;
            *) $NPUPY cycle $MODEL --cycles $n --frames $k ;; esac ;;
  esac
}

kmsgs() { sudo dmesg | awk -v t="$1" '{x=$1; gsub(/[][]/,"",x); if (x+0>t) print}' | \
  grep -iE 'warn|error|fault|timed out|timeout|hung|bug|oops|call trace|reset|stall|fail' | grep -v -E 'usb 7-1|uvcvideo|cannot get freq'; }

evidence() {  # evidence DIR : kernel/device state at a failure
  local h=$1; mkdir -p $h
  for p in $(pgrep -f "mx.py|venc-cycle|npu-loop|iep-test|glmark2"); do
    for t in /proc/$p/task/*; do echo "== $p $(cat $t/comm 2>/dev/null) $(awk '{print $3}' $t/stat 2>/dev/null) $(sudo cat $t/wchan 2>/dev/null)"; sudo cat $t/stack 2>/dev/null; done
  done > $h/stacks.txt
  for d in fdc38000.video-codec fdc40000.video-codec fdbd0000.video-codec fdbe0000.video-codec fdb50000.video-codec \
           fdba0000.video-codec fdb90000.video-codec fdb60000.rga fdb70000.rga fdb80000.rga fdbb0000.deinterlace; do
    p=/sys/bus/platform/devices/$d/power; [ -d $p ] && echo "$d $(cat $p/runtime_status) usage=$(cat $p/runtime_usage 2>/dev/null) active_ms=$(cat $p/runtime_active_time)"
  done > $h/runtime-pm.txt
  grep -E 'video-codec|rga|npu|iommu|deinterlace|jpeg' /proc/interrupts > $h/irqs.txt
  cat /sys/module/rockchip_vdec/parameters/* > $h/vdec-params.txt 2>/dev/null
  sudo dmesg | tail -80 > $h/dmesg.txt
  sudo cat /sys/kernel/debug/dri/0/state > $h/drm-state.txt 2>/dev/null
}

pair() {  # pair A B VARIANT N TABLE
  local a=$1 b=$2 v=$3 n=${4:-200} tab=$5 t0 s=/tmp/mx.stop.$$ ao bo h ok=PASS
  h=$R/$(date +%H%M%S)-$a--$b-$v; mkdir -p $h; ao=$h/A.json; bo=$h/B.json
  rm -f $s; t0=$(cut -d' ' -f1 /proc/uptime)
  start_steady $a $ao $s; sleep 3
  if ! kill -0 $STEADY_PID 2>/dev/null; then ok="A-DIED"; fi
  run_cycle $b $v $n > $bo 2>$h/B.log
  sleep 2; touch $s
  for ((i=0; i<60; i++)); do kill -0 $STEADY_PID 2>/dev/null || break; sleep 1; done
  kill -0 $STEADY_PID 2>/dev/null && { ok=A-HUNG; evidence $h/evidence; pkill -9 -P $STEADY_PID; kill -9 $STEADY_PID; }
  kmsgs $t0 > $h/kernel.txt
  local row; row=$(python3 - "$ao" "$bo" "$h/kernel.txt" <<'EOF'
import json, sys
def j(p):
    try: return json.loads(open(p).read().strip().splitlines()[-1])
    except Exception as e: return {'errors': ['no result: %s' % e]}
A, B = j(sys.argv[1]), j(sys.argv[2]); k = open(sys.argv[3]).read().strip().splitlines()
bf = sum(B.get(x, 0) for x in ('fail_open', 'fail_start', 'bad_md5', 'bad_hash', 'short'))
af = sum(A.get(x, 0) for x in ('stalls', 'bad_md5', 'bad_hash')) + len(A.get('errors', []))
verdict = 'PASS' if not bf and not af and not k and 'cycles' in B and not B.get('skipped') else ('SKIP' if B.get('skipped') else 'FAIL')
print('|'.join(map(str, [verdict, B.get('cycles', 0), B.get('fail_open', 0), B.get('fail_start', 0),
      B.get('bad_md5', B.get('bad_hash', 0)), A.get('frames', A.get('runs', 0)), A.get('stalls', 0),
      A.get('max_gap_ms', A.get('max_run_ms', '')), A.get('bad_md5', A.get('bad_hash', 0)), len(k),
      '; '.join((B.get('errors', []) + A.get('errors', []) + k)[:3]).replace('|', '/')[:200]])))
EOF
)
  [ "$ok" != PASS ] && row="$ok|${row#*|}"
  [ "${row%%|*}" != PASS ] && [ ! -d $h/evidence ] && evidence $h/evidence
  echo "| $a | $b | $v | ${row//|/ | } | $(basename $h) |" | tee -a $tab
}

hdr() { echo "| A (steady) | B (cycling) | variant | verdict | B cycles | B open fail | B start fail | B bad md5 | A frames | A stalls | A max gap ms | A bad md5 | kernel msgs | first errors | evidence |"
        echo "|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|"; }

case ${1:-} in
  prep) prep "${2:-}" ;;
  pair) define_blocks; tab=$R/pairs.md; [ -s $tab ] || hdr > $tab; pair $2 $3 $4 ${5:-200} $tab ;;
  chunk) define_blocks; tab=$R/$2/table.md; mkdir -p $R/$2; [ -s $tab ] || hdr > $tab
         echo "# $(date '+%F %T') $(uname -v) $(cat /sys/module/rockchip_vdec/parameters/pipeline 2>/dev/null | sed 's/^/ccu-pipeline=/')" >> $R/$2/info.txt
         for spec in $3; do IFS=: read a b v n <<< "$spec"; pair $a $b $v ${n:-200} $tab; done; cat $tab ;;
  desc) define_blocks; echo "${DESC[$2]}" ;;
  kf) define_blocks; echo "${KF[$2]}" ;;
  all) n=${2:-200}; for a in $BLOCKS; do for b in $BLOCKS; do for v in normal kill abort restart; do echo "$a:$b:$v:$n"; done; done; done ;;
  *) sed -n '2,20p' $0 ;;
esac
