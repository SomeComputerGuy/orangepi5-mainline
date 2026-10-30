#!/bin/bash
# Runs ON the board, unattended, after modesweep.sh: every codec x resolution x frame rate through every
# capable hardware decoder (bit-exact vs ffmpeg, fps, shown on HDMI and DP), every hardware encoder
# (PSNR, decoded back, shown), v4l2-compliance streaming of every format on every node, and fluster.
# Report: ~/codecsweep/report.txt
D=$HOME/codecsweep; W=$D/work; R=$D/report.txt; mkdir -p $W; : > $R
SRC=$HOME/demo/yacht_2160p.nv12; DEMO=$HOME/demo
# vqcmp.sh (same directory): timestamp-free PSNR / bit-exact comparisons, see its header
VQ=$(readlink -f $(dirname $0))/vqcmp.sh
say() { echo "$*" | tee -a $R; }
pb() { dmesg | grep -c POST_BUF_EMPTY; }
node() { for d in /sys/class/video4linux/video*; do grep -q "$1" $d/name && { echo /dev/$(basename $d); return; }; done; }
elem() { for e in $(gst-inspect-1.0 v4l2codecs 2>/dev/null | grep -oE "v4l2sl[a-z0-9]*${1}dec" | sort -u); do
  dev=$(gst-inspect-1.0 $e 2>/dev/null | grep -oE '/dev/video[0-9]+' | head -1)
  [ -n "$dev" ] && grep -q "$2" /sys/class/video4linux/$(basename $dev)/name && { echo $e; return; }; done; }
HDMI=$(modetest -M rockchip -c 2>/dev/null | awk '$4=="HDMI-A-1" && $3=="connected"{print $1}')
DP=$(modetest -M rockchip -c 2>/dev/null | awk '$4=="DP-1" && $3=="connected"{print $1}')
say "# codec sweep $(date '+%F %T')  kernel $(uname -v)  HDMI=$HDMI DP=$DP"

# ---- sources: NV12 at each resolution (240 frames of UVG YachtRide)
RES="640x360 1280x720 1920x1080 2560x1440 3840x2160"
for r in $RES; do [ -s $W/src_$r.nv12 ] || ffmpeg -nostdin -hide_banner -loglevel error -y -f rawvideo -pix_fmt nv12 -s 3840x2160 -i $SRC \
  -frames:v 240 -vf scale=${r/x/:} -f rawvideo -pix_fmt nv12 $W/src_$r.nv12; done

# ---- decoders: per codec, which hardware decoders, max resolution
declare -A DECS=([h264]="rkvdec:3840x2160 vpu121-dec:1920x1080" [h265]="rkvdec:3840x2160" [vp9]="rkvdec:3840x2160"
                 [av1]="av1:3840x2160" [vp8]="vpu121-dec:1920x1080" [mpeg2]="vpu121-dec:1920x1080")
declare -A ENC=([h264]="-c:v libx264 -preset veryfast -crf 20 -g 60" [h265]="-c:v libx265 -preset ultrafast -crf 22 -x265-params keyint=60:log-level=error"
                [vp9]="-c:v libvpx-vp9 -deadline realtime -cpu-used 8 -row-mt 1 -b:v 20M -g 60" [av1]="-c:v libaom-av1 -usage realtime -cpu-used 8 -row-mt 1 -b:v 10M -g 60"
                [vp8]="-c:v libvpx -deadline realtime -cpu-used 8 -b:v 10M -g 60" [mpeg2]="-c:v mpeg2video -q:v 3 -g 15 -bf 2")
declare -A EXT=([h264]=mkv [h265]=mkv [vp9]=webm [av1]=mkv [vp8]=webm [mpeg2]=mkv)
declare -A PARSE=([h264]="matroskademux ! h264parse" [h265]="matroskademux ! h265parse" [vp9]="matroskademux ! vp9parse"
                  [av1]="matroskademux ! av1parse" [vp8]="matroskademux" [mpeg2]="matroskademux ! mpegvideoparse")
px() { local a=${1%x*} b=${1#*x}; echo $((a*b)); }

hwcheck() {   # hwcheck <label> <file> <parse> <element> <WxH>
  local n=30 fs ok=0 i t0 t1 fps b a
  timeout 120 gst-launch-1.0 -q filesrc location=$2 ! $3 ! $4 ! videoconvert ! video/x-raw,format=I420 ! identity eos-after=$((n+10)) ! filesink location=$W/hw.yuv </dev/null >/dev/null 2>&1
  timeout 120 ffmpeg -nostdin -hide_banner -loglevel error -y -i $2 -frames:v $n -f rawvideo -pix_fmt yuv420p $W/sw.yuv
  fs=$(( $(stat -c %s $W/sw.yuv 2>/dev/null || echo 0) / n ))
  [ $fs -gt 0 ] && for i in $(seq 0 $((n-1))); do cmp -s <(dd if=$W/hw.yuv bs=$fs skip=$i count=1 2>/dev/null) <(dd if=$W/sw.yuv bs=$fs skip=$i count=1 2>/dev/null) && ok=$((ok+1)); done
  t0=$(date +%s.%N); timeout 120 gst-launch-1.0 -q filesrc location=$2 ! $3 ! $4 ! fakevideosink sync=false </dev/null >/dev/null 2>&1; t1=$(date +%s.%N)
  fps=$(echo "240 / ($t1 - $t0)" | bc -l | cut -c1-6)
  b=$(pb)
  [ -n "$HDMI" ] && timeout 6 gst-launch-1.0 -q filesrc location=$2 ! $3 ! $4 ! kmssink connector-id=$HDMI plane-id=59 </dev/null >/dev/null 2>&1
  [ -n "$DP" ] && timeout 6 gst-launch-1.0 -q filesrc location=$2 ! $3 ! $4 ! kmssink connector-id=$DP plane-id=65 </dev/null >/dev/null 2>&1
  a=$(pb)
  p=""; [ $ok -lt $n ] && p="psnr_vs_ffmpeg=$(cd $W && $VQ psnr $W/hw.yuv $W/sw.yuv $5 $n | grep -oE 'average:[0-9.inf]+')"
  printf '%-44s bitexact=%2s/%s  fps=%-7s display_underflow=%s %s\n' "$1" $ok $n "$fps" $((a-b)) "$p" | tee -a $R
  rm -f $W/hw.yuv $W/sw.yuv
}

say "== decoders (reference: ffmpeg software encodes; 240 frames; bit-exact = first 30 frames vs ffmpeg decode)"
for c in h264 h265 vp9 av1 vp8 mpeg2; do for r in $RES; do for f in 30 60 120; do
  [ $c = mpeg2 ] && [ $f = 120 ] && continue          # MPEG-2 has no 120 fps frame rate code
  src=$W/ref_${c}_${r}_${f}.${EXT[$c]}
  [ -s $src ] || timeout 900 ffmpeg -nostdin -hide_banner -loglevel error -y -f rawvideo -pix_fmt nv12 -s $r -r $f -i $W/src_$r.nv12 ${ENC[$c]} $src
  [ -s $src ] || { say "$c $r@$f: reference encode FAILED"; continue; }
  for dm in ${DECS[$c]}; do drv=${dm%%:*}; max=${dm#*:}
    [ $(px $r) -le $(px $max) ] || continue
    e=$(elem $c $drv); [ -n "$e" ] || { say "$c on $drv: no GStreamer element"; continue; }
    hwcheck "$c $r@$f $drv" $src "${PARSE[$c]}" $e $r
  done
done; done; done

say "== encoders (240 frames per resolution; PSNR vs source; decoded back on hardware and shown)"
# PSNR of an encoder's raw elementary stream (.es) against the NV12 source, all 240 frames, matched by
# frame index. (The old version compared a "-r 60 -c copy" .mkv remux, whose 1 ms timestamps made
# framesync pair every third frame with the wrong source frame, and ffmpeg can't probe H.264 .es files.)
psnr() { (cd $W && $VQ psnr $1 $3 $2 | grep -oE "average:[0-9.inf]+" | head -1); }
for r in $RES; do w=${r%x*}; h=${r#*x}
  for c in h265 h264; do
    o=$W/venc_${c}_$r; t0=$(date +%s.%N)
    timeout 300 $DEMO/rkvenc-enc -e $([ $c = h265 ] && echo hevc || echo h264) -i $W/src_$r.nv12 -o $o.es -w $w -h $h -f 60 -g 60 -q 26 </dev/null > $o.log 2>&1; rc=$?; t1=$(date +%s.%N)
    ffmpeg -nostdin -hide_banner -loglevel error -y -f $([ $c = h265 ] && echo hevc || echo h264) -r 60 -i $o.es -c copy $o.mkv
    say "VEPU580 $c $r: rc=$rc enc_fps=$(echo "240/($t1-$t0)" | bc -l | cut -c1-6) bytes=$(stat -c %s $o.es 2>/dev/null) PSNR $(psnr $o.es $r $W/src_$r.nv12)"
    [ -s $o.mkv ] && hwcheck "  VEPU580 $c $r -> rkvdec" $o.mkv "${PARSE[$c]}" $(elem $c rkvdec) $r
  done
  if [ $(px $r) -le $(px 1920x1080) ]; then
    o=$W/vepu2_$r; t0=$(date +%s.%N)
    timeout 300 $DEMO/v4l2-h264-slenc -d $(node vpu121-enc) -i $W/src_$r.nv12 -o $o.es -W $w -H $h -r 60 -g 60 </dev/null > $o.log 2>&1; rc=$?; t1=$(date +%s.%N)
    ffmpeg -nostdin -hide_banner -loglevel error -y -f h264 -r 60 -i $o.es -c copy $o.mkv
    say "VEPU2 h264 $r: rc=$rc enc_fps=$(echo "240/($t1-$t0)" | bc -l | cut -c1-6) bytes=$(stat -c %s $o.es 2>/dev/null) PSNR $(psnr $o.es $r $W/src_$r.nv12)"
    [ -s $o.mkv ] && hwcheck "  VEPU2 h264 $r -> Hantro G1" $o.mkv "${PARSE[h264]}" $(elem h264 vpu121-dec) $r
  fi
  # VEPU121 JPEG encode -> MJPEG file -> rkjpegd decode (PSNR vs source; HW JPEG decode is not bit-exact by design)
  o=$W/jpeg_$r.mjpeg
  timeout 120 gst-launch-1.0 -q filesrc location=$W/src_$r.nv12 ! rawvideoparse format=nv12 width=$w height=$h framerate=60/1 ! v4l2jpegenc ! jpegparse ! filesink location=$o </dev/null >/dev/null 2>&1; rc=$?
  timeout 120 gst-launch-1.0 -q filesrc location=$o ! jpegparse ! v4l2jpegdec ! videoconvert ! video/x-raw,format=I420 ! filesink location=$W/jdec.yuv </dev/null >/dev/null 2>&1; rc2=$?
  p=$(cd $W && $VQ psnr $W/jdec.yuv $W/src_$r.nv12 $r 60 | grep -oE "average:[0-9.inf]+")
  b=$(pb); [ -n "$HDMI" ] && timeout 6 gst-launch-1.0 -q filesrc location=$o ! jpegparse ! v4l2jpegdec ! kmssink connector-id=$HDMI plane-id=59 </dev/null >/dev/null 2>&1
  [ -n "$DP" ] && timeout 6 gst-launch-1.0 -q filesrc location=$o ! jpegparse ! v4l2jpegdec ! kmssink connector-id=$DP plane-id=65 </dev/null >/dev/null 2>&1
  say "VEPU121 JPEG $r -> rkjpegd: enc_rc=$rc dec_rc=$rc2 bytes=$(stat -c %s $o 2>/dev/null) PSNR $p display_underflow=$(( $(pb) - b ))"
  rm -f $W/jdec.yuv
done
# rkjpegd with every chroma subsampling (ffmpeg mjpeg 4:2:0 / 4:2:2 / 4:4:4, 1080p)
for s in yuvj420p yuvj422p yuvj444p; do
  o=$W/ff_$s.mjpeg; ffmpeg -nostdin -hide_banner -loglevel error -y -f rawvideo -pix_fmt nv12 -s 1920x1080 -i $W/src_1920x1080.nv12 -frames:v 60 -c:v mjpeg -pix_fmt $s -q:v 3 -f mjpeg $o
  timeout 60 gst-launch-1.0 -q filesrc location=$o ! jpegparse ! v4l2jpegdec ! fakevideosink </dev/null >/dev/null 2>&1
  say "rkjpegd ffmpeg-MJPEG $s 1080p: rc=$?"
done

say "== v4l2-compliance, streaming every format on every node (-s -f)"
for d in /sys/class/video4linux/video*; do n=$(cat $d/name); case "$n" in *Aluratek*) continue;; esac
  say "$(printf '%-34s' "$n") $(timeout 900 v4l2-compliance -d /dev/$(basename $d) -s -f 2>&1 | grep -E '^Total' | tail -1)"
done

say "== fluster (-j2)"
cd $HOME/vp9conf
fluster download VP8-TEST-VECTORS VP9-TEST-VECTORS JVT-AVC_V1 JCT-VC-HEVC_V1 AV1-TEST-VECTORS >/dev/null 2>&1
for t in "GStreamer-VP8-V4L2SL VP8-TEST-VECTORS" "GStreamer-VP9-V4L2SL VP9-TEST-VECTORS" "GStreamer-H.264-V4L2SL JVT-AVC_V1" \
         "GStreamer-H.265-V4L2SL JCT-VC-HEVC_V1" "GStreamer-AV1-V4L2SL AV1-TEST-VECTORS"; do
  set -- $t; timeout 2400 fluster run -d $1 -ts $2 -j 2 -t 90 -s -so sweep-$2.md > sweep-$2.log 2>&1 </dev/null
  say "$1 / $2: $(grep -m1 'Ran ' sweep-$2.log)"
done

say "== summary"
say "decode tests not 30/30 bit-exact (MPEG-2 excluded: not bit-exact by spec): $(grep -E 'bitexact=' $R | grep -v '^mpeg2' | grep -vc 'bitexact=30/30')"
say "MPEG-2 decode tests below 55 dB vs ffmpeg: $(grep -E '^mpeg2.*bitexact=' $R | grep -vE 'bitexact=30/30' | awk -F'average:' '$2 < 55' | wc -l)"
say "tests with display underflow: $(grep -E 'display_underflow=[1-9]' $R | wc -l)"
say "kernel Oops/BUG/SError this boot: $(dmesg | grep -cE 'Oops|BUG:|SError|Internal error')"
say "DONE $(date '+%F %T')"
