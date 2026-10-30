#!/bin/bash
# Runs ON the board: two 4K streams pulled over HTTP at once (the host's web server stands in for
# Jellyfin), each decoded on rkvdec and shown full-screen through weston (HDMI + DP), while
# measuring per-stream rendered/dropped frames, VOP underflows, NIC throughput/errors, CPU and
# softirq load. Then a decode-only pass of the 400 Mbit/s 10-bit HEVC clip over HTTP.
#   netstress.sh <http base url> [seconds]      report: ~/netstress/report.txt
BASE=${1:?usage: netstress.sh http://host:port [seconds]}; SECS=${2:-30}
D=$HOME/netstress; mkdir -p $D; R=$D/report.txt; : > $R
say() { echo "$*" | tee -a $R; }
W="XDG_RUNTIME_DIR=/run/user/0 WAYLAND_DISPLAY=wayland-9"
elem() { for e in $(gst-inspect-1.0 v4l2codecs 2>/dev/null | grep -oE "v4l2sl[a-z0-9]*${1}dec" | sort -u); do
  dev=$(gst-inspect-1.0 $e 2>/dev/null | grep -oE '/dev/video[0-9]+' | head -1)
  [ -n "$dev" ] && grep -q "$2" /sys/class/video4linux/$(basename $dev)/name && { echo $e; return; }; done; }
H264=$(elem h264 rkvdec); H265=$(elem h265 rkvdec)
nic() { awk '/end0:/{print $2, $3, $4, $5}' /proc/net/dev; }            # rx_bytes rx_packets rx_errs rx_drop
cpu() { awk '/^cpu /{print $2+$3+$4+$5+$6+$7+$8, $5+$6, $7+$8}' /proc/stat; }  # total idle+iowait irq+softirq
pb() { sudo dmesg | grep -c POST_BUF_EMPTY; }

sudo pkill -INT -x gst-launch-1.0 2>/dev/null; sleep 1
if ! pgrep -x weston >/dev/null; then
  sudo mkdir -p /run/user/0; sudo chmod 700 /run/user/0
  sudo env XDG_RUNTIME_DIR=/run/user/0 LIBSEAT_BACKEND=noop nohup weston --backend=drm --shell=desktop \
    --continue-without-input --idle-time=0 --socket=wayland-9 --log=$D/weston.log >/dev/null 2>&1 </dev/null &
  sleep 8
fi
say "# netstress $(date '+%F %T') kernel $(uname -v); h264=$H264 h265=$H265; ${SECS}s per case"

play() {   # play <name> <url> <parse> <decoder> <output or ""=fakesink>
  local sink
  if [ -n "$5" ]; then sink="waylandsink fullscreen=true fullscreen-output=$5"; else sink="fakevideosink"; fi
  sudo env $W timeout $((SECS+5)) gst-launch-1.0 -v souphttpsrc location="$2" ! queue2 use-buffering=true max-size-bytes=100000000 ! \
    $3 ! queue ! $4 ! queue ! fpsdisplaysink text-overlay=false sync=true signal-fps-measurements=true video-sink="$sink" \
    > $D/$1.log 2>&1 </dev/null
}
summ() { grep -oE 'rendered: [0-9]+, dropped: [0-9]+' $D/$1.log | tail -1; }

case_run() {   # case_run <label> <name:url:parse:decoder:output> ...
  local label=$1; shift
  local n0 c0 p0 n1 c1 p1
  n0=($(nic)); c0=($(cpu)); p0=$(pb)
  local pids=()
  for spec in "$@"; do IFS='|' read -r name url parse dec out <<<"$spec"; play "$name" "$url" "$parse" "$dec" "$out" & pids+=($!); done
  wait "${pids[@]}"   # only the players: weston may be a child of this script too
  n1=($(nic)); c1=($(cpu)); p1=$(pb)
  local dt=$((c1[0]-c0[0])); [ $dt -gt 0 ] || dt=1
  say "== $label"
  for spec in "$@"; do IFS='|' read -r name _ <<<"$spec"; say "   $name: $(summ $name) $(grep -m1 -oE 'ERROR.*' $D/$name.log | cut -c1-90)"; done
  say "   network: $(( (n1[0]-n0[0]) * 8 / SECS / 1000000 )) Mbit/s avg, rx_errs +$((n1[2]-n0[2])), rx_drop +$((n1[3]-n0[3]))"
  say "   CPU busy $(( 100 - 100*(c1[1]-c0[1])/dt ))%, irq+softirq $(( 100*(c1[2]-c0[2])/dt ))% (of all 8 cores); VOP underflows +$((p1-p0))"
}

MKV="matroskademux ! h264parse"; MKV5="matroskademux ! h265parse"
case_run "1 stream: 120 Mbit/s 4K H.264 -> HDMI" "j120|$BASE/jellyfish-120-mbps-4k-uhd-h264.mkv|$MKV|$H264|HDMI-A-1"
case_run "1 stream: 250 Mbit/s 4K H.264 -> HDMI" "j250|$BASE/jellyfish-250-mbps-4k-uhd-h264.mkv|$MKV|$H264|HDMI-A-1"
case_run "2 different streams at once: Jellyfish 250 Mbit/s -> HDMI + Big Buck Bunny 4K60 -> DP (both rkvdec cores)" \
  "j250h|$BASE/jellyfish-250-mbps-4k-uhd-h264.mkv|$MKV|$H264|HDMI-A-1" \
  "bbbd|$BASE/bbb_sunflower_2160p_60fps_normal.mp4|qtdemux ! h264parse|$H264|DP-1"
if curl -sfI $BASE/tears_of_steel_2160p_hevc.mp4 >/dev/null && [ -z "$TOS_PARTIAL" ]; then
  case_run "2 different streams at once: Tears of Steel 4K HEVC -> HDMI + Big Buck Bunny 4K60 H.264 -> DP" \
    "tosh|$BASE/tears_of_steel_2160p_hevc.mp4|qtdemux ! h265parse|$H265|HDMI-A-1" \
    "bbbd2|$BASE/bbb_sunflower_2160p_60fps_normal.mp4|qtdemux ! h264parse|$H264|DP-1"
fi
[ -n "$(curl -sI $BASE/jellyfish-400-mbps-4k-uhd-hevc-10bit.mkv | grep -i '200 OK')" ] && \
  case_run "decode only: 400 Mbit/s 4K HEVC Main10 (fakesink)" "j400|$BASE/jellyfish-400-mbps-4k-uhd-hevc-10bit.mkv|$MKV5|$H265|"
say "NIC totals: $(ip -s link show end0 | sed -n '4p;6p' | tr -s ' ' | tr '\n' ';')"
say "DONE $(date '+%F %T')"
