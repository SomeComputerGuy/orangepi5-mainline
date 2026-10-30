#!/bin/bash
# Runs ON the board, unattended: the DP-only, slow variant of modesweep.sh. Every mode on the
# DP connector (pattern only, then with a full-screen NV12 overlay plane), 12 s per mode instead
# of 4 s. Counts POST_BUF_EMPTY (VOP underflow) and failures per test.
# Report: ~/modesweep/report-dp-slow.txt
#   nohup sudo bash ~/modesweep/dpslow.sh > ~/modesweep/run-dp-slow.log 2>&1 &
D=$HOME/modesweep; R=$D/report-dp-slow.txt; mkdir -p $D; : > $R
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
for name in DP-1; do
  cid=$(awk -v n=$name '$4==n && $3=="connected"{print $1}' $D/connectors.txt); [ -n "$cid" ] || { echo "$name not connected" | tee -a $R; continue; }
  crtc=${CRTC[$name]}
  # modes: "WxH-refresh" from the connector's mode list (dedup)
  mapfile -t modes < <(awk -v id=$cid '$1==id && $3 ~ /connected/{f=1;next} f && /^[0-9]+\t/{f=0} f && /^  #[0-9]+ /{print $2"-"$3}' $D/connectors.txt | awk '!s[$0]++')
  echo "== $name (conn $cid, crtc $crtc): ${#modes[@]} modes" | tee -a $R
  for m in "${modes[@]}"; do run "$name $m pattern" 12 -s "$cid@$crtc:$m"; done
  # same modes with a full-screen NV12 overlay on an Esmart plane (59 for vp0, 65 for vp2)
  ov=$([ $crtc = 83 ] && echo 59 || echo 65)
  for m in "${modes[@]}"; do wh=${m%%-*}; run "$name $m +overlay$ov NV12" 12 -s "$cid@$crtc:$m" -P "$ov@$crtc:$wh@NV12"; done
done
echo "== summary" | tee -a $R
echo "tests: $(grep -c 'rc=' $R)  with underflow: $(grep -E 'underflow=[1-9]' $R | wc -l)  rc!=0: $(grep -E 'rc=[1-9]' $R | wc -l)" | tee -a $R
echo "DONE $(date '+%F %T')" | tee -a $R
