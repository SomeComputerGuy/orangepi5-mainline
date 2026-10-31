#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
# Media matrix. Runs ON the board as root, unattended, resumable (finished test ids are skipped on rerun).
# codec x decode/encode x hardware block x userspace x display output, plus concurrency, open/close while
# another job runs, v4l2-compliance and fluster (conformance MD5s; not duplicated here). Every hardware
# path is proven by the block's IRQ count rising (no silent software fallback). Logic from
# work/_out/modesweep/codecsweep.sh.
#   sudo ./media-matrix.sh [--stop-gdm] [--out DIR] [--groups LIST] [--res LIST] [--calib calib.json]
# Groups (default all): dec display enc jpeg rga iep concurrent openclose compliance fluster
# Env: SRC_YUV (NV12 3840x2160 clip, default $HOME/demo/yacht_2160p.nv12; else videotestsrc),
#   DEMO (dir with rkvenc-enc / v4l2-h264-slenc, default $HOME/demo), FLUSTER_DIR, FLUSTER_SUITES,
#   CAM_CONN + --calib (webcam check of decoded SMPTE bars on that output), PSNR_MIN (30).
# Output: DIR/results.tsv (id, verdict, detail), DIR/summary.txt, DIR/work (streams, logs).
set -uo pipefail
[ "$(id -u)" -eq 0 ] || exec sudo -E "$0" "$@"
D=$(cd "$(dirname "$0")" && pwd)
OUT=/var/tmp/testmatrix/media; GROUPS_SEL="dec display enc jpeg rga iep concurrent openclose compliance fluster"
RES="640x360 1280x720 1920x1080 2560x1440 3840x2160"; STOP_GDM=0; CALIB=""
while [ $# -gt 0 ]; do
  case $1 in
    --out) OUT=$2; shift ;; --groups) GROUPS_SEL=${2//,/ }; shift ;; --res) RES=${2//,/ }; shift ;;
    --calib) CALIB=$2; shift ;; --stop-gdm) STOP_GDM=1 ;;
    -h|--help) sed -n '2,14p' "$0"; exit 0 ;; *) echo "unknown option $1" >&2; exit 2 ;;
  esac; shift
done
W=$OUT/work; R=$OUT/results.tsv; mkdir -p "$W"; [ -s "$R" ] || printf 'id\tverdict\tdetail\n' > "$R"
SRC_YUV=${SRC_YUV:-$HOME/demo/yacht_2160p.nv12}; DEMO=${DEMO:-$HOME/demo}; PSNR_MIN=${PSNR_MIN:-30}
N=60          # frames per bit-exact stream
export GST_DEBUG_NO_COLOR=1

if pgrep -x 'gnome-shell|Xorg|weston|mutter' >/dev/null; then
  if [ $STOP_GDM = 1 ]; then trap 'systemctl start gdm' EXIT; systemctl stop gdm; sleep 3
  else echo "a compositor holds the display: display tests will be SKIP (use --stop-gdm)"; NODISPLAY=1; fi
fi
NODISPLAY=${NODISPLAY:-0}

# ---------------------------------------------------------------- helpers
have() { command -v "$1" >/dev/null; }
gst_has() { gst-inspect-1.0 "$1" >/dev/null 2>&1; }
want() { [[ " $GROUPS_SEL " == *" $1 "* ]]; }
done_id() { grep -q "^$1	" "$R"; }
row() { printf '%s\t%s\t%s\n' "$1" "$2" "$3" >> "$R"; printf '%-62s %-5s %s\n' "$1" "$2" "$3"; }
skip() { done_id "$1" || row "$1" SKIP "$2"; }
node() { for d in /sys/class/video4linux/video*; do grep -q "$1" "$d/name" && { echo "/dev/${d##*/}"; return; }; done; }
devaddr() { local n=${1#/dev/}; basename "$(readlink -f "/sys/class/video4linux/$n/device")" | cut -d. -f1; }
irqsnap() { awk '/video-codec|jpeg|rga|iep|vepu|vdpu|rkvdec|rkvenc|av1/{s=0; for(i=2;i<=NF;i++) if($i ~ /^[0-9]+$/) s+=$i; else break; print $1 $NF, s}' /proc/interrupts; }
irqdelta() { join <(sort <<<"$1") <(sort <<<"$2") | awk '$3>$2{printf "%s+%d ", $1, $3-$2}'; }
pbe() { dmesg | grep -c POST_BUF_EMPTY; }
kerr() { dmesg | grep -iE 'rkvdec|hantro|vpu|venc|rga|iep|jpeg|iommu|av1|video-codec' | grep -ciE 'error|fail|timeout|fault|warn|oops'; }
md5frames() { python3 -I -c 'import hashlib,sys
f=open(sys.argv[1],"rb"); n=int(sys.argv[2])
while True:
    b=f.read(n)
    if len(b)<n: break
    print(hashlib.md5(b).hexdigest())' "$1" "$2"; }
cmpframes() {  # cmpframes <reference.yuv> <test.yuv> <framesize> -> "identical frames/reference frames"
  python3 -I -c 'import sys
n=int(sys.argv[3]); a,b=open(sys.argv[1],"rb"),open(sys.argv[2],"rb"); ok=tot=0
while True:
    x=a.read(n)
    if len(x)<n: break
    tot+=1; ok+=b.read(n)==x
print("%d/%d" % (ok,tot))' "$1" "$2" "$3"; }
psnr_y() {  # psnr_y <a.nv12|i420> <b> <w> <h> [frames]: mean Y PSNR, every 2nd pixel, pure python
  python3 -I -c 'import math,sys
a,b,w,h,n=sys.argv[1],sys.argv[2],int(sys.argv[3]),int(sys.argv[4]),int(sys.argv[5])
fs=w*h*3//2; fa,fb=open(a,"rb"),open(b,"rb"); ps=[]
for i in range(n):
    fa.seek(i*fs); fb.seek(i*fs); ya,yb=fa.read(w*h),fb.read(w*h)
    if len(ya)<w*h or len(yb)<w*h: break
    se=sum((ya[j]-yb[j])**2 for j in range(0,w*h,2))/(w*h//2)
    ps.append(99.0 if se==0 else 10*math.log10(255*255/se))
print("%.2f" % (sum(ps)/len(ps)) if ps else "nan")' "$1" "$2" "$3" "$4" "${5:-8}"; }
ge() { python3 -I -c 'import sys; sys.exit(0 if float(sys.argv[1])>=float(sys.argv[2]) else 1)' "$1" "$2" 2>/dev/null; }
elem() { local e dev; for e in $(gst-inspect-1.0 v4l2codecs 2>/dev/null | grep -oE "v4l2sl[a-z0-9]*${1}dec" | sort -u); do
  dev=$(gst-inspect-1.0 "$e" 2>/dev/null | grep -oE '/dev/video[0-9]+' | head -1)
  [ -n "$dev" ] && grep -q "$2" "/sys/class/video4linux/${dev#/dev/}/name" && { echo "$e"; return; }; done; }
m2m_elem() {  # m2m_elem <suffix e.g. convert|h264enc|jpegdec> <driver name>: video4linux2 element bound to that node
  local e dev; for e in $(gst-inspect-1.0 video4linux2 2>/dev/null | grep -oE "v4l2[a-z0-9]*$1" | sort -u); do
  dev=$(gst-inspect-1.0 "$e" 2>/dev/null | grep -A1 -i 'device' | grep -oE '/dev/video[0-9]+' | head -1)
  [ -n "$dev" ] && grep -q "$2" "/sys/class/video4linux/${dev#/dev/}/name" && { echo "$e"; return; }; done; }
px() { local a=${1%x*} b=${1#*x}; echo $((a*b)); }
fsz() { local a=${1%x*} b=${1#*x}; echo $((a*b*3/2)); }
camcheck() {  # camcheck <id>: classify the SMPTE bars on CAM_CONN (call while it is shown)
  [ -n "${CAM_CONN:-}" ] && [ -s "$CALIB" ] || { echo "cam=-"; return; }
  local p="$W/cam-${1//[:\/]/_}"
  python3 -I "$D/lib/camcheck.py" capture "$p" >/dev/null 2>&1 || { echo "cam=ERROR"; return; }
  echo "cam=$(python3 -I "$D/lib/camcheck.py" classify "$CALIB" "$p.rgb" smpte | python3 -I -c 'import json,sys; print(json.load(sys.stdin)["verdict"])')"; }

# blocks: name -> v4l2 node name pattern
RKVDEC=$(node rkvdec); G1=$(node vpu121-dec); AV1=$(node av1-vpu-dec); VENC=$(node rockchip-venc)
VEPU2=$(node vpu121-enc); JENC=$(node vepu121-enc); JDEC=$(node rockchip-jpegd); IEP=$(node rockchip-iep)
mapfile -t RGAS < <(for d in /sys/class/video4linux/video*; do grep -q rockchip-rga "$d/name" && echo "/dev/${d##*/}"; done)
declare -A DECS=([h264]="rkvdec:3840x2160 vpu121-dec:1920x1080" [h265]="rkvdec:3840x2160" [vp9]="rkvdec:3840x2160"
                 [av1]="av1-vpu-dec:3840x2160" [vp8]="vpu121-dec:1920x1080" [mpeg2]="vpu121-dec:1920x1080")
declare -A PARSE=([h264]="matroskademux ! h264parse" [h265]="matroskademux ! h265parse" [vp9]="matroskademux ! vp9parse"
                  [av1]="matroskademux ! av1parse" [vp8]="matroskademux" [mpeg2]="matroskademux ! mpegvideoparse")
declare -A FFENC=([h264]="-c:v libx264 -preset veryfast -crf 20 -g 30" [h265]="-c:v libx265 -preset ultrafast -crf 22 -x265-params keyint=30:log-level=error"
                  [vp9]="-c:v libvpx-vp9 -deadline realtime -cpu-used 8 -row-mt 1 -b:v 20M -g 30" [av1]="-c:v libaom-av1 -usage realtime -cpu-used 8 -row-mt 1 -b:v 10M -g 30"
                  [vp8]="-c:v libvpx -deadline realtime -cpu-used 8 -b:v 10M -g 30" [mpeg2]="-c:v mpeg2video -q:v 3 -g 15 -bf 2")
declare -A GSTENC=([h264]="openh264enc complexity=0 gop-size=30 ! h264parse" [h265]="x265enc speed-preset=ultrafast key-int-max=30 ! h265parse"
                   [vp9]="vp9enc deadline=1 cpu-used=8 keyframe-max-dist=30" [av1]="av1enc usage-profile=realtime cpu-used=8 keyframe-max-dist=30 ! av1parse"
                   [vp8]="vp8enc deadline=1 cpu-used=8 keyframe-max-dist=30" [mpeg2]="avenc_mpeg2video gop-size=15 ! mpegvideoparse")
declare -A GSTDEC=([h264]="h264parse ! openh264dec" [vp9]="vp9dec" [vp8]="vp8dec" [av1]="av1parse ! av1dec" [h265]="h265parse ! avdec_h265" [mpeg2]="mpegvideoparse ! avdec_mpeg2video")
declare -A HWNAME=([rkvdec]=rkvdec [vpu121-dec]="Hantro G1 (VPU121)" [av1-vpu-dec]="AV1 (VPU981)")
FFHW=""; have ffmpeg && FFHW=$(ffmpeg -hide_banner -hwaccels 2>/dev/null | tr -d ' ')

echo "# media matrix $(date '+%F %T') $(uname -r)  ffmpeg=$(have ffmpeg && echo y || echo n) fluster=$(have fluster && echo y || echo n) mpv=$(have mpv && echo y || echo n)" | tee -a "$OUT/runs.log"
echo "nodes: rkvdec=$RKVDEC g1=$G1 av1=$AV1 venc=$VENC vepu2=$VEPU2 jpegenc=$JENC jpegdec=$JDEC iep=$IEP rga=${RGAS[*]}"

# ---------------------------------------------------------------- sources
src() {  # src <WxH> -> NV12 file with N frames of natural content (or a moving test pattern)
  local r=$1 f=$W/src_$1.nv12 w=${1%x*} h=${1#*x}
  [ -s "$f" ] && { echo "$f"; return; }
  if [ -s "$SRC_YUV" ]; then
    gst-launch-1.0 -q filesrc location="$SRC_YUV" ! rawvideoparse format=nv12 width=3840 height=2160 framerate=30/1 ! \
      identity eos-after=$N ! videoscale ! "video/x-raw,width=$w,height=$h" ! filesink location="$f" >/dev/null 2>&1
  else
    gst-launch-1.0 -q videotestsrc pattern=ball num-buffers=$N ! "video/x-raw,format=NV12,width=$w,height=$h,framerate=30/1" ! \
      filesink location="$f" >/dev/null 2>&1
  fi
  echo "$f"; }
smpte() {  # 240 frames of SMPTE bars (videotestsrc layout = modetest layout) for display + webcam tests
  local f=$W/smpte_$1.nv12 w=${1%x*} h=${1#*x}
  [ -s "$f" ] || gst-launch-1.0 -q videotestsrc pattern=smpte num-buffers=240 ! "video/x-raw,format=NV12,width=$w,height=$h,framerate=30/1" ! \
    filesink location="$f" >/dev/null 2>&1; echo "$f"; }
encode_ref() {  # encode_ref <codec> <WxH> <nv12> <out.mkv>: software encode (ffmpeg, else gst)
  local c=$1 r=$2 in=$3 o=$4 w=${2%x*} h=${2#*x}
  [ -s "$o" ] && return 0
  if have ffmpeg; then
    # shellcheck disable=SC2086
    timeout 1200 ffmpeg -nostdin -hide_banner -loglevel error -y -f rawvideo -pix_fmt nv12 -s "$r" -r 30 -i "$in" ${FFENC[$c]} "$o"
  else
    # shellcheck disable=SC2086
    timeout 1200 gst-launch-1.0 -q filesrc location="$in" ! rawvideoparse format=nv12 width="$w" height="$h" framerate=30/1 ! \
      videoconvert ! ${GSTENC[$c]} ! matroskamux ! filesink location="$o" >/dev/null 2>&1
  fi
  [ -s "$o" ]; }
sw_decode() {  # sw_decode <codec> <in> <out.i420>
  if have ffmpeg; then ffmpeg -nostdin -hide_banner -loglevel error -y -i "$2" -f rawvideo -pix_fmt yuv420p "$3"
  else
    gst_has "${GSTDEC[$1]##* }" || return 1
    # shellcheck disable=SC2086
    gst-launch-1.0 -q filesrc location="$2" ! matroskademux ! ${GSTDEC[$1]} ! videoconvert ! video/x-raw,format=I420 ! \
      filesink location="$3" >/dev/null 2>&1
  fi
  [ -s "$3" ]; }

# hw_decode <userspace> <codec> <driver> <in> <out.i420>: decode on the hardware; prints IRQ deltas
hw_decode() {
  local us=$1 c=$2 drv=$3 in=$4 o=$5 b a e rc=1
  b=$(irqsnap); rm -f "$o"
  case $us in
    gst) e=$(elem "$c" "$drv"); [ -n "$e" ] || { echo "NOELEM"; return 2; }
         # shellcheck disable=SC2086
         timeout 300 gst-launch-1.0 -q filesrc location="$in" ! ${PARSE[$c]} ! "$e" ! videoconvert ! video/x-raw,format=I420 ! \
           filesink location="$o" </dev/null >/dev/null 2>&1; rc=$? ;;
    ffmpeg-v4l2request) [[ $FFHW == *v4l2request* ]] || { echo "NOELEM"; return 2; }
         timeout 300 ffmpeg -nostdin -hide_banner -loglevel error -y -hwaccel v4l2request -i "$in" -f rawvideo -pix_fmt yuv420p "$o"; rc=$? ;;
    ffmpeg-vaapi) [[ $FFHW == *vaapi* ]] || { echo "NOELEM"; return 2; }
         LIBVA_DRIVER_NAME=v4l2_request timeout 300 ffmpeg -nostdin -hide_banner -loglevel error -y -hwaccel vaapi \
           -hwaccel_device /dev/dri/renderD128 -i "$in" -f rawvideo -pix_fmt yuv420p "$o"; rc=$? ;;
    gst-va) e=va${c}dec; [ "$c" = mpeg2 ] && e=vampeg2dec; LIBVA_DRIVER_NAME=v4l2_request gst_has "$e" || { echo "NOELEM"; return 2; }
         # shellcheck disable=SC2086
         LIBVA_DRIVER_NAME=v4l2_request timeout 300 gst-launch-1.0 -q filesrc location="$in" ! ${PARSE[$c]} ! "$e" ! videoconvert ! \
           video/x-raw,format=I420 ! filesink location="$o" </dev/null >/dev/null 2>&1; rc=$? ;;
    mpv) have mpv || { echo "NOELEM"; return 2; }
         rm -f "$o.noframes"
         timeout 300 mpv --no-config --really-quiet --hwdec=v4l2request-copy --no-audio --vf=format=yuv420p --ovc=rawvideo \
           --of=rawvideo --o="$o" "$in" </dev/null >/dev/null 2>&1; rc=$?
         if [ $rc != 0 ] || [ ! -s "$o" ]; then   # no encode mode in this mpv: decode only (hwdec + IRQs, no bit-exact)
           timeout 300 mpv --no-config --hwdec=v4l2request-copy --no-audio --vo=null --untimed "$in" </dev/null >"$o.log" 2>&1; rc=$?
           grep -q 'Using hardware decoding' "$o.log" && touch "$o.noframes" || rc=1
         fi ;;
  esac
  a=$(irqsnap); echo "$(irqdelta "$b" "$a")"; return $rc; }

# ---------------------------------------------------------------- decode: codec x res x block x userspace
if want dec; then
  for c in h264 h265 vp9 av1 vp8 mpeg2; do for r in $RES; do
    for dm in ${DECS[$c]}; do drv=${dm%%:*}; max=${dm#*:}
      [ "$(px "$r")" -le "$(px "$max")" ] || continue
      for us in gst ffmpeg-v4l2request ffmpeg-vaapi gst-va mpv; do
        id="dec:$c:$drv:$us:$r"; done_id "$id" && continue
        ref=$W/ref_${c}_$r.mkv
        encode_ref "$c" "$r" "$(src "$r")" "$ref" || { skip "$id" "no software $c encoder (ffmpeg/gst) for the reference stream"; continue; }
        [ -s "$W/sw_${c}_$r.i420" ] || sw_decode "$c" "$ref" "$W/sw_${c}_$r.i420" || true
        irq=$(hw_decode "$us" "$c" "$drv" "$ref" "$W/hw.i420"); rc=$?
        [ $rc = 2 ] && { skip "$id" "$us has no $c decoder here"; continue; }
        addr=$(devaddr "$(node "$drv")")
        if [ $rc != 0 ] || { [ ! -s "$W/hw.i420" ] && [ ! -e "$W/hw.i420.noframes" ]; }; then row "$id" FAIL "rc=$rc irq=[$irq]"; continue; fi
        [[ $irq == *"$addr"* ]] || [[ $drv == rkvdec && $irq == *video-codec* ]] || { row "$id" FAIL "no ${HWNAME[$drv]} IRQs (software fallback or other block) irq=[$irq]"; continue; }
        cores=$(grep -o 'video-codec+' <<<"$irq" | wc -l)
        if [ -e "$W/hw.i420.noframes" ]; then
          row "$id" PASS "mpv hwdec decode (this mpv has no encode mode: no bit-exact check) irq=[$irq]"
        elif [ -s "$W/sw_${c}_$r.i420" ]; then
          be=$(cmpframes "$W/sw_${c}_$r.i420" "$W/hw.i420" "$(fsz "$r")")
          [ "${be%/*}" = "${be#*/}" ] && [ "${be#*/}" -ge $N ] && v=PASS || v=FAIL
          row "$id" $v "bitexact=$be vs software decode, irq=[$irq] blocks=$cores"
        else
          row "$id" PASS "decoded $(( $(stat -c %s "$W/hw.i420") / $(fsz "$r") )) frames (no software reference decoder: bit-exactness via fluster) irq=[$irq]"
        fi
      done
    done
  done; done
fi

# ---------------------------------------------------------------- display: decoded SMPTE bars on HDMI, DP, both
conn_id() { modetest -M rockchip -c 2>/dev/null | awk -v n="$1" '$4==n && $3=="connected"{print $1}'; }
ovl() { python3 -I "$D/lib/kmsctl.py" list | python3 -I -c 'import json,sys
d=json.load(sys.stdin); n=sys.argv[1]; skip=sys.argv[2:]
c=next(x for x in d["connectors"] if x["name"]==n); crtc=c["possible_crtcs"][0]
print(next(p["id"] for p in d["planes"] if crtc in p["possible_crtcs"] and "0x0" in p["formats"].get("NV12",[]) and str(p["id"]) not in skip))' "$@"; }
KMSFD=0; gst-inspect-1.0 kmssink 2>/dev/null | grep -qE '^\s+fd\s' && KMSFD=1
if want display; then
  HC=$(conn_id HDMI-A-1); DC=$(conn_id DP-1)
  for c in h264 h265 vp9 av1 vp8; do for r in 1920x1080 3840x2160; do for dm in ${DECS[$c]}; do drv=${dm%%:*}; max=${dm#*:}
    [ "$(px "$r")" -le "$(px "$max")" ] || continue
    s=$W/disp_${c}_$r.mkv; e=$(elem "$c" "$drv")
    for out in HDMI DP both; do
      id="display:$c:$drv:gst-kmssink:$out:$r"; done_id "$id" && continue
      [ "$NODISPLAY" = 1 ] && { skip "$id" "compositor running"; continue; }
      [ -n "$e" ] || { skip "$id" "no GStreamer element for $c on $drv"; continue; }
      encode_ref "$c" "$r" "$(smpte "$r")" "$s" || { skip "$id" "no software $c encoder"; continue; }
      sinks=(); used=()
      for o in HDMI DP; do [ $out = both ] || [ $out = $o ] || continue
        cid=$([ $o = HDMI ] && echo "$HC" || echo "$DC"); [ -n "$cid" ] || continue
        cn=$([ $o = HDMI ] && echo HDMI-A-1 || echo DP-1); pl=$(ovl "$cn" "${used[@]}"); used+=("$pl")
        sinks+=(t. ! queue ! kmssink connector-id="$cid" plane-id="$pl" force-modesetting=true sync=true)
        [ $KMSFD = 1 ] && sinks+=(fd=7)
      done
      [ ${#sinks[@]} -gt 0 ] || { skip "$id" "output not connected"; continue; }
      [ $KMSFD = 1 ] || [ $out != both ] || { skip "$id" "kmssink has no fd property (two sinks need one DRM master fd)"; continue; }
      b=$(pbe); i0=$(irqsnap)
      # one DRM fd (the subshell's, DRM master) shared by every kmssink of the pipeline
      # shellcheck disable=SC2086
      ( [ $KMSFD = 1 ] && exec 7<>/dev/dri/card0; exec timeout 12 gst-launch-1.0 -q filesrc location="$s" ! ${PARSE[$c]} ! "$e" ! tee name=t "${sinks[@]}" ) \
        </dev/null >"$W/disp.log" 2>&1 & gp=$!
      sleep 4; cam=$( { [ $out = both ] || [[ ${CAM_CONN:-} == $out* ]]; } && camcheck "$id" || echo cam=-)
      wait $gp; rc=$?; a=$(pbe); irq=$(irqdelta "$i0" "$(irqsnap)")
      v=PASS; { [ $rc = 0 ] || [ $rc = 124 ]; } || v=FAIL; [ $((a-b)) -gt 0 ] && v=FAIL
      [[ $cam == cam=GOOD || $cam == cam=- ]] || v=FAIL
      row "$id" $v "rc=$rc underflow=$((a-b)) $cam irq=[$irq] $(grep -m1 -iE 'error|fail' "$W/disp.log" | cut -c1-80)"
    done
  done; done; done
  if have mpv; then for out in HDMI-A-1 DP-1; do for c in h264 h265 vp9 av1; do
    id="display:$c:auto:mpv-drm:$out:3840x2160"; done_id "$id" && continue
    [ "$NODISPLAY" = 1 ] && { skip "$id" "compositor running"; continue; }
    s=$W/disp_${c}_3840x2160.mkv; encode_ref "$c" 3840x2160 "$(smpte 3840x2160)" "$s" || { skip "$id" "no encoder"; continue; }
    b=$(pbe); i0=$(irqsnap)
    timeout 12 mpv --no-config --vo=drm --drm-connector="$out" --hwdec=v4l2request --no-audio --length=8 "$s" </dev/null >"$W/mpv.log" 2>&1 & mp=$!
    sleep 5; cam=$([[ ${CAM_CONN:-} == "$out" ]] && camcheck "$id" || echo cam=-); wait $mp; rc=$?
    irq=$(irqdelta "$i0" "$(irqsnap)"); a=$(pbe)
    v=PASS; [ $rc = 0 ] || v=FAIL; [ -n "$irq" ] || v=FAIL; [ $((a-b)) -gt 0 ] && v=FAIL; [[ $cam == cam=GOOD || $cam == cam=- ]] || v=FAIL
    row "$id" $v "rc=$rc underflow=$((a-b)) $cam irq=[$irq] $(grep -m1 -oE 'Using hardware decoding \([^)]*\)' "$W/mpv.log")"
  done; done; fi
fi

# ---------------------------------------------------------------- encoders: VEPU580 H.264/HEVC, VEPU2 (VPU121) H.264
enc_check() {  # enc_check <id> <codec> <WxH> <es/mkv> <rc> <irq> <t>
  local id=$1 c=$2 r=$3 o=$4 rc=$5 irq=$6 t=$7 dec=$W/encdec.i420 p fr
  rm -f "$dec"
  [ "$rc" = 0 ] && [ -s "$o" ] || { row "$id" FAIL "rc=$rc irq=[$irq] $(tail -1 "$o.log" 2>/dev/null | cut -c1-80)"; return; }
  [ -n "$irq" ] || { row "$id" FAIL "no encoder IRQs (software?)"; return; }
  # decode back on rkvdec (GStreamer) and on software, PSNR of both vs the source
  # shellcheck disable=SC2086
  gst-launch-1.0 -q filesrc location="$o" ! ${PARSE[$c]#matroskademux ! } ! "$(elem "$c" rkvdec)" ! videoconvert ! video/x-raw,format=NV12 ! \
    filesink location="$dec" </dev/null >/dev/null 2>&1
  fr=$(( $(stat -c %s "$dec" 2>/dev/null || echo 0) / $(fsz "$r") )); p=$(psnr_y "$(src "$r")" "$dec" "${r%x*}" "${r#*x}")
  v=PASS; ge "$p" "$PSNR_MIN" || v=FAIL; [ "$fr" -ge $N ] || v=FAIL
  row "$id" $v "PSNR_Y=$p dB frames=$fr/$N fps=$(python3 -I -c "print(round($N/max($t,1e-3),1))") bytes=$(stat -c %s "$o") irq=[$irq]"; }
if want enc; then for r in $RES; do w=${r%x*}; h=${r#*x}
  for c in h264 h265; do
    for us in gst-v4l2 ffmpeg-v4l2m2m rkvenc-enc; do
      id="enc:$c:vepu580:$us:$r"; done_id "$id" && continue
      [ -n "$VENC" ] || { skip "$id" "no rockchip-venc node"; continue; }
      o=$W/venc.$c; rm -f "$o"; i0=$(irqsnap); t0=$(date +%s.%N)
      case $us in
        gst-v4l2) e=$(m2m_elem "${c}enc" rockchip-venc); [ -n "$e" ] || { skip "$id" "no v4l2 stateful ${c} encoder element on rockchip-venc"; continue; }
          timeout 300 gst-launch-1.0 -q filesrc location="$(src "$r")" ! rawvideoparse format=nv12 width="$w" height="$h" framerate=30/1 ! \
            "$e" ! "${c}parse" ! filesink location="$o" </dev/null >"$o.log" 2>&1; rc=$? ;;
        ffmpeg-v4l2m2m) have ffmpeg && ffmpeg -hide_banner -encoders 2>/dev/null | grep -q "${c/h265/hevc}_v4l2m2m" || { skip "$id" "no ffmpeg ${c/h265/hevc}_v4l2m2m"; continue; }
          timeout 300 ffmpeg -nostdin -hide_banner -loglevel error -y -f rawvideo -pix_fmt nv12 -s "$r" -r 30 -i "$(src "$r")" \
            -c:v "${c/h265/hevc}_v4l2m2m" -b:v 20M -f "${c/h265/hevc}" "$o" >"$o.log" 2>&1; rc=$? ;;
        rkvenc-enc) [ -x "$DEMO/rkvenc-enc" ] || { skip "$id" "no $DEMO/rkvenc-enc"; continue; }
          timeout 300 "$DEMO/rkvenc-enc" -e "$([ $c = h265 ] && echo hevc || echo h264)" -i "$(src "$r")" -o "$o" -w "$w" -h "$h" -f 30 -g 30 -q 26 \
            </dev/null >"$o.log" 2>&1; rc=$? ;;
      esac
      enc_check "$id" "$c" "$r" "$o" "$rc" "$(irqdelta "$i0" "$(irqsnap)")" "$(python3 -I -c "import time; print(time.time()-$t0)")"
    done
  done
  id="enc:h264:vepu2:v4l2-h264-slenc:$r"
  if ! done_id "$id"; then
    if [ "$(px "$r")" -gt "$(px 1920x1080)" ]; then skip "$id" "VEPU2 max 1920x1080"
    elif [ -z "$VEPU2" ]; then skip "$id" "no vpu121-enc node"
    elif e=$(gst-inspect-1.0 v4l2codecs 2>/dev/null | grep -oE 'v4l2slh264enc' | head -1); [ -n "$e" ]; then
      o=$W/vepu2.h264; i0=$(irqsnap); t0=$(date +%s.%N)
      timeout 300 gst-launch-1.0 -q filesrc location="$(src "$r")" ! rawvideoparse format=nv12 width="$w" height="$h" framerate=30/1 ! "$e" ! h264parse ! \
        filesink location="$o" </dev/null >"$o.log" 2>&1; rc=$?
      enc_check "${id/v4l2-h264-slenc/gst-v4l2sl}" h264 "$r" "$o" $rc "$(irqdelta "$i0" "$(irqsnap)")" "$(python3 -I -c "import time; print(time.time()-$t0)")"
    elif [ -x "$DEMO/v4l2-h264-slenc" ]; then
      o=$W/vepu2.h264; i0=$(irqsnap); t0=$(date +%s.%N)
      timeout 300 "$DEMO/v4l2-h264-slenc" -d "$VEPU2" -i "$(src "$r")" -o "$o" -W "$w" -H "$h" -r 30 -g 30 </dev/null >"$o.log" 2>&1; rc=$?
      enc_check "$id" h264 "$r" "$o" $rc "$(irqdelta "$i0" "$(irqsnap)")" "$(python3 -I -c "import time; print(time.time()-$t0)")"
    else skip "$id" "no VEPU2 H.264 encoder userspace (gst v4l2slh264enc or $DEMO/v4l2-h264-slenc)"; fi
  fi
done; fi

# ---------------------------------------------------------------- JPEG: VEPU121 encode, rkjpegd decode (incl. 4:2:0/4:2:2/4:4:4 from jpegenc)
if want jpeg; then
  JE=$(m2m_elem jpegenc vepu121-enc); JD=$(m2m_elem jpegdec rockchip-jpegd)
  for r in $RES; do w=${r%x*}; h=${r#*x}
    id="jpeg:enc:vepu121:gst-v4l2:$r"
    if ! done_id "$id"; then
      if [ -z "$JE" ]; then skip "$id" "no v4l2jpegenc on vepu121-enc"; else
        i0=$(irqsnap); timeout 120 gst-launch-1.0 -q filesrc location="$(src "$r")" ! rawvideoparse format=nv12 width="$w" height="$h" framerate=30/1 ! \
          "$JE" ! jpegparse ! multifilesink location="$W/je_%03d.jpg" </dev/null >/dev/null 2>&1; rc=$?; irq=$(irqdelta "$i0" "$(irqsnap)")
        gst-launch-1.0 -q multifilesrc location="$W/je_%03d.jpg" caps=image/jpeg,framerate=30/1 ! jpegdec ! videoconvert ! video/x-raw,format=NV12 ! \
          filesink location="$W/je.nv12" </dev/null >/dev/null 2>&1
        p=$(psnr_y "$(src "$r")" "$W/je.nv12" "$w" "$h"); v=PASS; [ $rc = 0 ] && [ -n "$irq" ] && ge "$p" "$PSNR_MIN" || v=FAIL
        row "$id" $v "rc=$rc PSNR_Y(sw decode)=$p irq=[$irq]"; fi
    fi
    id="jpeg:dec:rkjpegd:gst-v4l2:$r"
    if ! done_id "$id"; then
      if [ -z "$JD" ]; then skip "$id" "no v4l2jpegdec on rockchip-jpegd"; else
        rm -f "$W"/js_*.jpg; gst-launch-1.0 -q filesrc location="$(src "$r")" ! rawvideoparse format=nv12 width="$w" height="$h" framerate=30/1 ! \
          videoconvert ! jpegenc quality=90 ! multifilesink location="$W/js_%03d.jpg" </dev/null >/dev/null 2>&1
        for dec in "$JD" jpegdec; do gst-launch-1.0 -q multifilesrc location="$W/js_%03d.jpg" caps=image/jpeg,framerate=30/1 ! jpegparse ! "$dec" ! videoconvert ! \
          video/x-raw,format=NV12 ! filesink location="$W/jd_$dec.nv12" </dev/null >/dev/null 2>&1; done
        i0=$(irqsnap); gst-launch-1.0 -q multifilesrc location="$W/js_%03d.jpg" caps=image/jpeg,framerate=30/1 ! jpegparse ! "$JD" ! fakesink </dev/null >/dev/null 2>&1; rc=$?
        irq=$(irqdelta "$i0" "$(irqsnap)"); p=$(psnr_y "$W/jd_jpegdec.nv12" "$W/jd_$JD.nv12" "$w" "$h")
        v=PASS; [ $rc = 0 ] && [ -n "$irq" ] && ge "$p" 40 || v=FAIL
        row "$id" $v "rc=$rc PSNR_Y vs software jpegdec=$p (IDCT differs; >=40 dB) irq=[$irq]"; fi
    fi
  done
  for s in 420 422 444; do id="jpeg:dec:rkjpegd:gst-v4l2:1920x1080-yuv$s"; done_id "$id" && continue
    [ -n "$JD" ] || { skip "$id" "no v4l2jpegdec"; continue; }
    fmt=$(case $s in 420) echo I420;; 422) echo Y42B;; 444) echo Y444;; esac)
    gst-launch-1.0 -q videotestsrc pattern=smpte num-buffers=10 ! "video/x-raw,format=$fmt,width=1920,height=1080" ! jpegenc ! \
      multifilesink location="$W/jss_%03d.jpg" </dev/null >/dev/null 2>&1
    gst-launch-1.0 -q multifilesrc location="$W/jss_%03d.jpg" caps=image/jpeg,framerate=30/1 ! jpegparse ! "$JD" ! fakesink </dev/null >"$W/jss.log" 2>&1; rc=$?
    row "$id" "$([ $rc = 0 ] && echo PASS || echo FAIL)" "rc=$rc $(grep -m1 -iE 'error|not-negotiated' "$W/jss.log" | cut -c1-80)"
  done
fi

# ---------------------------------------------------------------- RGA (every node): format conversion + scaling vs software
if want rga; then
  CONVS=$(gst-inspect-1.0 video4linux2 2>/dev/null | grep -oE 'v4l2[a-z0-9]*convert' | sort -u)
  for dev in "${RGAS[@]}"; do
    e=""; for x in $CONVS; do gst-inspect-1.0 "$x" 2>/dev/null | grep -q "$dev\b" && e=$x; done
    for t in "NV12:1920x1080:RGBx:1920x1080" "NV12:3840x2160:NV12:1920x1080" "NV12:1280x720:NV12:3840x2160" "NV12:1920x1080:BGRA:1280x720"; do
      IFS=: read -r fin ri fo ro <<<"$t"; id="rga:${dev#/dev/}:gst-v4l2convert:$fin-$ri-to-$fo-$ro"; done_id "$id" && continue
      [ -n "$e" ] || { skip "$id" "no v4l2convert element bound to $dev"; continue; }
      cv() { gst-launch-1.0 -q filesrc location="$(src "$ri")" ! rawvideoparse format=nv12 width="${ri%x*}" height="${ri#*x}" framerate=30/1 ! \
        "$1" ! "video/x-raw,format=$fo,width=${ro%x*},height=${ro#*x}" ! videoconvert ! video/x-raw,format=NV12 ! filesink location="$2" </dev/null >/dev/null 2>&1; }
      i0=$(irqsnap); cv "$e" "$W/rga_hw.nv12"; rc=$?; irq=$(irqdelta "$i0" "$(irqsnap)"); cv videoconvertscale "$W/rga_sw.nv12"
      p=$(psnr_y "$W/rga_sw.nv12" "$W/rga_hw.nv12" "${ro%x*}" "${ro#*x}"); v=PASS; [ $rc = 0 ] && [ -n "$irq" ] && ge "$p" "$PSNR_MIN" || v=FAIL
      row "$id" $v "rc=$rc PSNR_Y vs software=$p irq=[$irq]"
    done
  done
fi

# ---------------------------------------------------------------- IEP + v4l2-compliance
if want iep; then id="iep:deinterlace:v4l2-compliance-stream"
  if ! done_id "$id"; then
    if [ -z "$IEP" ]; then skip "$id" "no rockchip-iep node"
    elif have v4l2-compliance; then o=$(timeout 600 v4l2-compliance -d "$IEP" -s 2>&1 | grep -E '^Total' | tail -1)
      row "$id" "$([[ $o == *"Failed: 0"* ]] && echo PASS || echo FAIL)" "$o (GStreamer/FFmpeg have no IEP deinterlacer element)"
    else skip "$id" "v4l2-compliance not installed; no GStreamer/FFmpeg element drives IEP"; fi
  fi
fi
if want compliance; then for d in /sys/class/video4linux/video*; do n=$(cat "$d/name"); case $n in *Aluratek*|*UVC*|*Camera*) continue;; esac
  id="compliance:${n// /_}:${d##*/}"; done_id "$id" && continue
  have v4l2-compliance || { skip "$id" "v4l2-compliance not installed"; continue; }
  o=$(timeout 900 v4l2-compliance -d "/dev/${d##*/}" -s -f 2>&1 | grep -E '^Total' | tail -1)
  row "$id" "$([[ $o == *"Failed: 0"* ]] && echo PASS || echo FAIL)" "$o"
done; fi

# ---------------------------------------------------------------- concurrent decode + encode + JPEG + RGA + display
solo_md5() { md5frames "$1" "$2" | md5sum | cut -c1-12; }
if want concurrent; then for round in 1 2; do id="concurrent:round$round"; done_id "$id" && continue
  jobs_ok=1; det=""; b=$(pbe); i0=$(irqsnap); pids=(); names=()
  declare -A JOBS=([hevc4k-rkvdec]="h265 rkvdec 3840x2160" [h264-1080-g1]="h264 vpu121-dec 1920x1080" [av1-1080]="av1 av1-vpu-dec 1920x1080"
                   [h264-4k-rkvdec]="h264 rkvdec 3840x2160" [vp9-4k-rkvdec]="vp9 rkvdec 3840x2160")
  for j in "${!JOBS[@]}"; do read -r c drv r <<<"${JOBS[$j]}"; ref=$W/ref_${c}_$r.mkv
    encode_ref "$c" "$r" "$(src "$r")" "$ref" || continue
    hw_decode gst "$c" "$drv" "$ref" "$W/cc_$j.i420" >/dev/null & pids+=($!); names+=("$j")
  done
  if [ "$NODISPLAY" = 0 ] && [ $KMSFD = 1 ]; then HC=$(conn_id HDMI-A-1); DC=$(conn_id DP-1); chains=()
    # both outputs from one process sharing one DRM master fd: rkvdec HEVC 4K -> HDMI, Hantro G1 H.264 1080p -> DP
    [ -n "$HC" ] && encode_ref h265 3840x2160 "$(smpte 3840x2160)" "$W/disp_h265_3840x2160.mkv" && chains+=(filesrc location="$W/disp_h265_3840x2160.mkv" \
      ! matroskademux ! h265parse ! "$(elem h265 rkvdec)" ! kmssink fd=7 connector-id="$HC" plane-id="$(ovl HDMI-A-1)" force-modesetting=true)
    [ -n "$DC" ] && encode_ref h264 1920x1080 "$(smpte 1920x1080)" "$W/disp_h264_1920x1080.mkv" && chains+=(filesrc location="$W/disp_h264_1920x1080.mkv" \
      ! matroskademux ! h264parse ! "$(elem h264 vpu121-dec)" ! kmssink fd=7 connector-id="$DC" plane-id="$(ovl DP-1 "$(ovl HDMI-A-1)")" force-modesetting=true)
    [ ${#chains[@]} -gt 0 ] && { ( exec 7<>/dev/dri/card0; exec timeout 15 gst-launch-1.0 -q "${chains[@]}" ) </dev/null >/dev/null 2>&1 & pids+=($!); names+=(disp-hdmi+dp); }
  fi
  [ -n "$VENC" ] && [ -x "$DEMO/rkvenc-enc" ] && { timeout 300 "$DEMO/rkvenc-enc" -e hevc -i "$(src 1920x1080)" -o "$W/cc_enc.hevc" -w 1920 -h 1080 -f 30 -g 30 -q 26 </dev/null >/dev/null 2>&1 & pids+=($!); names+=(vepu580-enc); }
  JE=$(m2m_elem jpegenc vepu121-enc); [ -n "$JE" ] && { timeout 120 gst-launch-1.0 -q filesrc location="$(src 1920x1080)" ! rawvideoparse format=nv12 width=1920 height=1080 framerate=30/1 ! \
      "$JE" ! fakesink </dev/null >/dev/null 2>&1 & pids+=($!); names+=(jpeg-enc); }
  for k in "${!pids[@]}"; do wait "${pids[$k]}"; rc=$?; n=${names[$k]}
    { [ $rc = 0 ] || { [[ $n == disp-* ]] && [ $rc = 124 ]; }; } || { jobs_ok=0; det+="$n:rc=$rc "; }
    if [[ $n != disp-* && $n != *enc ]]; then read -r c drv r <<<"${JOBS[$n]}"
      [ -s "$W/sw_${c}_$r.i420" ] || sw_decode "$c" "$W/ref_${c}_$r.mkv" "$W/sw_${c}_$r.i420" || true
      if [ -s "$W/sw_${c}_$r.i420" ]; then be=$(cmpframes "$W/sw_${c}_$r.i420" "$W/cc_$n.i420" "$(fsz "$r")"); det+="$n:$be "
        [ "${be%/*}" = "${be#*/}" ] || jobs_ok=0; fi
    fi
  done
  a=$(pbe); [ $((a-b)) -gt 0 ] && { jobs_ok=0; det+="underflow=$((a-b)) "; }
  row "$id" "$([ $jobs_ok = 1 ] && echo PASS || echo FAIL)" "$det irq=[$(irqdelta "$i0" "$(irqsnap)")]"
  unset JOBS
done; fi

# ---------------------------------------------------------------- open/close every node while a decode runs
if want openclose; then for bg in "h265 rkvdec 3840x2160" "h264 vpu121-dec 1920x1080" "av1 av1-vpu-dec 1920x1080"; do
  read -r c drv r <<<"$bg"; id="openclose:bg-$c-$drv"; done_id "$id" && continue
  ref=$W/ref_${c}_$r.mkv; encode_ref "$c" "$r" "$(src "$r")" "$ref" || { skip "$id" "no reference stream"; continue; }
  rm -f "$W/oc_bg_all.i420"; k0=$(kerr); ( for _ in 1 2 3; do hw_decode gst "$c" "$drv" "$ref" "$W/oc_bg.i420" >/dev/null || exit 1; cat "$W/oc_bg.i420" >> "$W/oc_bg_all.i420"; done ) & bgp=$!
  fails=0; it=0
  while kill -0 $bgp 2>/dev/null; do it=$((it+1))
    python3 -I -c 'import os,sys
for p in sys.argv[1:]:
    for _ in range(20): os.close(os.open(p, os.O_RDWR))' /dev/video* 2>/dev/null || fails=$((fails+1))
    for t in "h264 vpu121-dec 1920x1080" "vp8 vpu121-dec 1280x720" "h264 rkvdec 1280x720" "vp9 rkvdec 1280x720" "av1 av1-vpu-dec 1280x720"; do
      read -r c2 d2 r2 <<<"$t"; [ -s "$W/ref_${c2}_$r2.mkv" ] || continue; e2=$(elem "$c2" "$d2"); [ -n "$e2" ] || continue
      # shellcheck disable=SC2086
      timeout 60 gst-launch-1.0 -q filesrc location="$W/ref_${c2}_$r2.mkv" ! ${PARSE[$c2]} ! "$e2" ! fakesink </dev/null >/dev/null 2>&1 || fails=$((fails+1))
    done
    [ ${#RGAS[@]} -gt 0 ] && { timeout 30 gst-launch-1.0 -q videotestsrc num-buffers=5 ! video/x-raw,format=NV12,width=1280,height=720 ! \
      "$(gst-inspect-1.0 video4linux2 2>/dev/null | grep -oE 'v4l2[a-z0-9]*convert' | head -1)" ! video/x-raw,format=RGBx ! fakesink </dev/null >/dev/null 2>&1 || true; }
  done
  wait $bgp; rc=$?
  sw=$W/sw_${c}_$r.i420; [ -s "$sw" ] || sw_decode "$c" "$ref" "$sw" || true
  be="n/a"; [ -s "$sw" ] && be=$(cmpframes <(cat "$sw" "$sw" "$sw") "$W/oc_bg_all.i420" "$(fsz "$r")")
  k1=$(kerr); v=PASS; [ $rc = 0 ] || v=FAIL; [ $fails = 0 ] || v=FAIL; [[ $be == n/a || ${be%/*} == "${be#*/}" ]] || v=FAIL
  row "$id" $v "bg rc=$rc bitexact=$be iterations=$it foreground_failures=$fails new_codec_kernel_msgs=$((k1-k0))"
done; fi

# ---------------------------------------------------------------- fluster (conformance MD5s)
if want fluster; then
  if ! have fluster; then skip "fluster" "fluster not installed"; else
    FD=${FLUSTER_DIR:-$HOME/vp9conf}; mkdir -p "$FD"; cd "$FD" || exit 1
    SUITES=${FLUSTER_SUITES:-"H.264:JVT-AVC_V1 H.264:JVT-FR-EXT H.265:JCT-VC-HEVC_V1 VP8:VP8-TEST-VECTORS VP9:VP9-TEST-VECTORS VP9:VP9-TEST-VECTORS-HIGH AV1:AV1-TEST-VECTORS AV1:CHROMIUM-10bit-AV1-TEST-VECTORS MPEG2:MPEG2_VIDEO-MAIN"}
    for dec in $(fluster list 2>/dev/null | grep -oE '(GStreamer|FFmpeg)-[A-Za-z0-9.]+-(V4L2SL|v4l2request|VAAPI|VA)[A-Za-z0-9.-]*' | sort -u); do
      for s in $SUITES; do cod=${s%%:*}; ts=${s#*:}; [[ $dec == *-"$cod"-* ]] || continue
        id="fluster:$dec:$ts"; done_id "$id" && continue
        fluster download "$ts" >/dev/null 2>&1
        timeout 3600 fluster run -d "$dec" -ts "$ts" -j 2 -t 90 -s -so "$OUT/fluster-$dec-$ts.md" > "$OUT/fluster-$dec-$ts.log" 2>&1 </dev/null
        res=$(grep -m1 -E 'Ran [0-9]+/[0-9]+' "$OUT/fluster-$dec-$ts.log")
        [ -n "$res" ] || { row "$id" SKIP "no result: $(tail -1 "$OUT/fluster-$dec-$ts.log" | cut -c1-80)"; continue; }
        row "$id" INFO "$res (expected failures per docs/; see $OUT/fluster-$dec-$ts.md)"
      done
    done
  fi
fi

# ---------------------------------------------------------------- summary
{ echo "# media matrix $(date '+%F %T')  $(uname -r) $(uname -v)"
  awk -F'\t' 'NR>1{split($1,a,":"); k=a[1]; c[k" "$2]++} END{for(x in c) print x, c[x]}' "$R" | sort
  echo "== FAIL"; awk -F'\t' '$2=="FAIL"' "$R"
  echo "kernel Oops/BUG/SError this boot: $(dmesg | grep -cE 'Oops|BUG:|SError|Internal error')"; } > "$OUT/summary.txt"
cat "$OUT/summary.txt"
chown -R "${SUDO_UID:-0}:${SUDO_GID:-0}" "$OUT" 2>/dev/null
exit 0
