#!/bin/bash
# Runs ON the board, unattended: every mode on every connected connector (pattern only, then with a
# full-screen NV12 overlay plane), then every format on every plane at each connector's preferred
# mode. Counts POST_BUF_EMPTY (VOP underflow) and failures per test. Report: ~/modesweep/report.txt
#   nohup sudo bash ~/modesweep/modesweep.sh > ~/modesweep/run.log 2>&1 &
D=$HOME/modesweep; R=$D/report.txt; mkdir -p $D; : > $R
pkill -INT -x gst-launch-1.0 2>/dev/null; sleep 1
MT="modetest -M rockchip"
pb() { dmesg | grep -c POST_BUF_EMPTY; }
run() {   # run <label> <secs> <modetest args...>
  local label=$1 secs=$2; shift 2
  local b; b=$(pb)
  local out; out=$( (sleep "$secs") | timeout $((secs+10)) $MT "$@" 2>&1 )
  local rc=$? a; a=$(pb)
  local err; err=$(echo "$out" | grep -iE "fail|error|invalid|cannot|unable" | head -1 | cut -c1-80)
  local scdc=""; [ -r /sys/kernel/debug/dri/0/HDMI-A-1/scdc_status ] && [[ $label == HDMI* ]] && \
    scdc=$(sed -n '5p' /sys/kernel/debug/dri/0/HDMI-A-1/scdc_status | cut -c1-2)
  printf '%-58s rc=%-3s underflow=%-5s %s %s\n' "$label" "$rc" "$((a-b))" "${scdc:+scdc40=$scdc}" "$err" | tee -a $R
}
echo "# mode sweep $(date '+%F %T')  kernel $(uname -v)" | tee -a $R
$MT -c > $D/connectors.txt 2>&1; $MT -p > $D/planes.txt 2>&1
# connectors: id, name, crtc (HDMI-A-1 -> video_port0, DP-1 -> video_port2)
declare -A CRTC=([HDMI-A-1]=83 [DP-1]=84)
for name in HDMI-A-1 DP-1; do
  cid=$(awk -v n=$name '$4==n && $3=="connected"{print $1}' $D/connectors.txt); [ -n "$cid" ] || { echo "$name not connected" | tee -a $R; continue; }
  crtc=${CRTC[$name]}
  # modes: "WxH-refresh" from the connector's mode list (dedup)
  mapfile -t modes < <(awk -v id=$cid '$1==id && $3 ~ /connected/{f=1;next} f && /^[0-9]+\t/{f=0} f && /^  #[0-9]+ /{print $2"-"$3}' $D/connectors.txt | awk '!s[$0]++')
  echo "== $name (conn $cid, crtc $crtc): ${#modes[@]} modes" | tee -a $R
  for m in "${modes[@]}"; do run "$name $m pattern" 4 -s "$cid@$crtc:$m"; done
  # same modes with a full-screen NV12 overlay on an Esmart plane (59 for vp0, 65 for vp2)
  ov=$([ $crtc = 83 ] && echo 59 || echo 65)
  for m in "${modes[@]}"; do wh=${m%%-*}; run "$name $m +overlay$ov NV12" 4 -s "$cid@$crtc:$m" -P "$ov@$crtc:$wh@NV12"; done
  # every format on every plane that can use this CRTC, at the preferred (first) mode
  pm=${modes[0]}; wh=${pm%%-*}
  echo "== $name formats per plane at $pm" | tee -a $R
  awk '/^Planes:/{p=1} p && /^[0-9]+\t/{id=$1; crtcs=$NF} p && /formats:/{for(i=2;i<=NF;i++) print id, crtcs, $i}' $D/planes.txt |
  while read -r pid mask fmt; do
    bit=$([ $crtc = 83 ] && echo 1 || echo 2)
    (( mask & bit )) || continue
    case $fmt in Y210|YU10|YU08|XR30|XB30|NV30|NV15) ;; esac   # tested too; modetest may lack patterns for some
    # stdin redirected so nothing in run() can consume the awk pipe that feeds this loop
    run "$name plane$pid $fmt $wh" 3 -s "$cid@$crtc:$pm" -P "$pid@$crtc:$wh@$fmt" < /dev/null
  done
done
# both displays at once, each at its preferred mode, with an overlay each
h=$(awk '$4=="HDMI-A-1" && $3=="connected"{print $1}' $D/connectors.txt); d=$(awk '$4=="DP-1" && $3=="connected"{print $1}' $D/connectors.txt)
if [ -n "$h" ] && [ -n "$d" ]; then
  echo "== dual display" | tee -a $R
  for hm in 3840x2160-120 3840x2160-60; do
    run "DUAL HDMI $hm + DP 3840x2160-30, overlays" 6 -s "$h@83:$hm" -s "$d@84:3840x2160-30" -P "59@83:3840x2160@NV12" -P "65@84:3840x2160@NV12"
  done
fi
echo "== summary" | tee -a $R
echo "tests: $(grep -c 'rc=' $R)  with underflow: $(grep -E 'underflow=[1-9]' $R | wc -l)  rc!=0: $(grep -E 'rc=[1-9]' $R | wc -l)" | tee -a $R
echo "DONE $(date '+%F %T')" | tee -a $R
