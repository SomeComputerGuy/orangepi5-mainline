#!/bin/bash
# Live decode / encode->playback demo on the Orange Pi 5 (runs on the board).
#   demo.sh <step>      steps: list | dec-hevc | dec-vp9 | dec-h264 | dec-av1 | g1-h264 | g1-vp8 |
#                              g1-mpeg2 | enc-hevc | enc-h264 | enc-vepu2 | jpeg | dual
# Clips live in ~/demo (reference encodes of UVG "YachtRide" 3840x2160@120, CC BY-NC 3.0,
# Ultra Video Group, Tampere University).
set -uo pipefail
D=~/demo
OUT=$D/out; mkdir -p "$OUT"

# Connector / plane ids (the DRM ids are stable, /dev/video numbers are not)
conn() { sudo modetest -M rockchip -c 2>/dev/null | awk -v n="$1" '$4==n && $3=="connected"{print $1; exit}'; }
HDMI=$(conn HDMI-A-1); DP=$(conn DP-1)
PLANE_HDMI=59 PLANE_DP=65          # Esmart windows: NV12/NV15 capable, either CRTC

# GStreamer stateless decoder element for a given codec on a given driver
elem() {   # elem <codec: h264|h265|vp8|vp9|av1|mpeg2> <driver name substring>
  for e in $(gst-inspect-1.0 v4l2codecs 2>/dev/null | grep -oE "v4l2sl[a-z0-9]*${1}dec" | sort -u); do
    dev=$(gst-inspect-1.0 "$e" 2>/dev/null | grep -oE '/dev/video[0-9]+' | head -1)
    [ -n "$dev" ] && grep -q "$2" "/sys/class/video4linux/$(basename "$dev")/name" && { echo "$e"; return; }
  done
}
node() { for d in /sys/class/video4linux/video*; do grep -q "$1" "$d/name" && { echo "/dev/$(basename "$d")"; return; }; done; }

play() {   # play <label> <file> <demux+parse> <decoder element> [connector] [plane]
  local label=$1 f=$2 dmx=$3 dec=$4 c=${5:-$HDMI} p=${6:-$PLANE_HDMI}
  echo "=== $label: $(basename "$f") via $dec -> connector $c"
  local t0; t0=$(cut -d' ' -f1 /proc/uptime)
  sudo gst-launch-1.0 -q filesrc location="$f" ! $dmx ! "$dec" ! \
    fpsdisplaysink text-overlay=false signal-fps-measurements=true sync=true \
      video-sink="kmssink connector-id=$c plane-id=$p" -v 2>&1 |
    grep -oE 'rendered: [0-9]+, dropped: [0-9]+, (current|average): [0-9.]+' | tail -1
  sudo dmesg | awk -v t="$t0" '{gsub(/[][]/,"",$1); if ($1+0>t) print}' |
    grep -iE 'POST_BUF|rkvdec|hantro|venc|error|timeout' | sed -E 's/^[0-9.]+ //' | sort | uniq -c | head -5
}

mux() { ffmpeg -hide_banner -loglevel error -y -r "$2" -i "$1" -c copy "$3"; }   # raw ES -> mkv

case "${1:-list}" in
list)
  echo "HDMI connector: $HDMI  DP connector: ${DP:-none}"
  for c in h265 h264 vp9 vp8 av1 mpeg2; do printf '%-6s rkvdec=%-22s hantro=%-22s av1=%s\n' $c \
    "$(elem $c rkvdec)" "$(elem $c vpu121-dec)" "$(elem $c av1)"; done
  echo "venc=$(node rockchip-venc) vepu2-h264=$(node vpu121-enc) jpegenc=$(node vepu121-enc) jpegd=$(node rockchip-jpegd)" ;;
dec-hevc)  play "rkvdec HEVC 4K120" $D/yacht_hevc_2160p120.mp4 "qtdemux ! h265parse" "$(elem h265 rkvdec)" ;;
dec-vp9)   play "rkvdec VP9 4K120"  $D/yacht_vp9_2160p120.webm "matroskademux ! vp9parse" "$(elem vp9 rkvdec)" ;;
dec-h264)  play "rkvdec H.264 4K120" $D/yacht_h264_2160p120.mp4 "qtdemux ! h264parse" "$(elem h264 rkvdec)" ;;
dec-av1)   play "AV1 VPU AV1 1080p120" $D/yacht_av1_1080p120.mkv "matroskademux ! av1parse" "$(elem av1 av1)" ;;
g1-h264)   play "Hantro G1 H.264 1080p120" $D/yacht_h264_1080p120.mp4 "qtdemux ! h264parse" "$(elem h264 vpu121-dec)" ;;
g1-vp8)    play "Hantro G1 VP8 1080p120" $D/yacht_vp8_1080p120.webm "matroskademux" "$(elem vp8 vpu121-dec)" ;;
g1-mpeg2)  play "Hantro G1 MPEG-2 1080p120" $D/yacht_mpeg2_1080p120.mpg "mpegpsdemux ! mpegvideoparse" "$(elem mpeg2 vpu121-dec)" ;;
enc-hevc)  # VEPU580 HEVC 4K CBR 60 Mbit/s, then play it back on rkvdec
  echo "=== VEPU580 HEVC encode 3840x2160, 600 frames"
  time $D/rkvenc-enc -e hevc -i $D/yacht_2160p.nv12 -o $OUT/venc.hevc -w 3840 -h 2160 -f 120 -g 120 -b 60000000 -t
  mux $OUT/venc.hevc 120 $OUT/venc_hevc.mkv
  play "VEPU580 HEVC -> rkvdec" $OUT/venc_hevc.mkv "matroskademux ! h265parse" "$(elem h265 rkvdec)" ;;
enc-h264)  # VEPU580 H.264 4K
  echo "=== VEPU580 H.264 encode 3840x2160, 600 frames"
  time $D/rkvenc-enc -e h264 -i $D/yacht_2160p.nv12 -o $OUT/venc.h264 -w 3840 -h 2160 -f 120 -g 120 -b 80000000
  mux $OUT/venc.h264 120 $OUT/venc_h264.mkv
  play "VEPU580 H.264 -> rkvdec" $OUT/venc_h264.mkv "matroskademux ! h264parse" "$(elem h264 rkvdec)" ;;
enc-vepu2) # VPU121 (VEPU2) H.264 1080p, played back on the Hantro G1 decoder
  echo "=== VEPU2 H.264 encode 1920x1080, 600 frames"
  time $D/v4l2-h264-slenc -d "$(node vpu121-enc)" -i $D/yacht_1080p.nv12 -o $OUT/vepu2.h264 -W 1920 -H 1080 -r 120 -g 120 -b 20000000 -c -p 100 -8
  mux $OUT/vepu2.h264 120 $OUT/vepu2_h264.mkv
  play "VEPU2 H.264 -> Hantro G1" $OUT/vepu2_h264.mkv "matroskademux ! h264parse" "$(elem h264 vpu121-dec)" ;;
jpeg)      # VEPU121 JPEG encode -> VDPU720 JPEG decode -> display, live chain
  echo "=== VEPU121 JPEG encode -> rkjpegd decode, 1080p120 stream"
  sudo gst-launch-1.0 -q filesrc location=$D/yacht_1080p.nv12 ! \
    rawvideoparse format=nv12 width=1920 height=1080 framerate=120/1 ! v4l2jpegenc ! jpegparse ! v4l2jpegdec ! \
    fpsdisplaysink text-overlay=false sync=true video-sink="kmssink connector-id=$HDMI plane-id=$PLANE_HDMI" -v 2>&1 |
    grep -oE 'rendered: [0-9]+, dropped: [0-9]+, (current|average): [0-9.]+' | tail -1 ;;
dual)      # HEVC 4K120 on HDMI and VP9 4K on DP at the same time (both rkvdec cores)
  [ -n "$DP" ] || { echo "no DP display"; exit 1; }
  play "HDMI: rkvdec HEVC" $D/yacht_hevc_2160p120.mp4 "qtdemux ! h265parse" "$(elem h265 rkvdec)" &
  play "DP: rkvdec VP9" $D/yacht_vp9_2160p120.webm "matroskademux ! vp9parse" "$(elem vp9 rkvdec)" "$DP" "$PLANE_DP"
  wait ;;
*) sed -n '2,6p' "$0" ;;
esac
