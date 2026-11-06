#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
# camcal.sh: per-connector camera calibration for a camera that sees several screens (run ON THE BOARD, root).
#   sudo env TM=/var/tmp/testmatrix sh camcal.sh [outdir]      default outdir /var/tmp/tm/cam2
# Commits white on one head and black on the other (then the reverse, then black/black), captures the 4K camera
# frame each time and writes calib-<CONN>.json = quad + levels of that screen only. Stops kmsctl at the end.
# Env: CAM_CAPS (default 4K MJPG), CAM_RGB (default 1280x720), CONNS (default "HDMI-A-1 DP-1"),
#      MODE_H / MODE_V (mode to use on both heads, default 1920x1080 60 Hz, picked by kmsctl list).
#      CAL_DIAG=<dir> (vop2-splice sp14): a kmsg marker "=== camcal <n> <patterns>" before each client and,
#      8 s into it, read-only captures into <dir>: clock lines of clk_summary, vop2 debugfs summary, DRM state.
TM=${TM:-/var/tmp/testmatrix}; O=${1:-/var/tmp/tm/cam2}; mkdir -p "$O"
export CAM_CAPS=${CAM_CAPS:-image/jpeg,width=3840,height=2160} CAM_RGB=${CAM_RGB:-1280x720}
CONNS=${CONNS:-"HDMI-A-1 DP-1"}
modeof() { python3 -I $TM/lib/kmsctl.py list | python3 -c '
import json,sys
d=json.load(sys.stdin)
for c in d["connectors"]:
    if c["name"]==sys.argv[1]:
        for i,m in enumerate(c["modes"]):
            if m["hdisplay"]==1920 and m["vdisplay"]==1080 and round(m.get("vrefresh",60))==60: print(i); sys.exit()
        print(0)' "$1"; }
KP=; NC=0
diag() {  # diag <n> <patterns>: read-only captures of the shown state
  local f=$CAL_DIAG/$1-$2 dri
  dri=$(ls -d /sys/kernel/debug/dri/*/vop2 2>/dev/null | head -1)
  grep -E '^ *(gpll|cpll|npll|spll|v0pll|aupll|ppll|aclk_vop[a-z0-9_]*|dclk_vop[0-9a-z_]*|clk_hdmiphy_pixel[0-9]) ' \
    /sys/kernel/debug/clk/clk_summary > "$f-clk.txt" 2>&1
  [ -n "$dri" ] && cat "$dri/summary" > "$f-vop2.txt" 2>&1 && cat "$(dirname "$dri")/state" > "$f-state.txt" 2>&1
}
stop() { [ -n "$KP" ] && kill $KP 2>/dev/null; KP=; sleep 1; sleep 1; }
show() { # uses PAT[]; heads get codes 1, 2
  local args=() i=0 c
  stop
  NC=$((NC + 1))
  [ -n "${CAL_DIAG:-}" ] && mkdir -p "$CAL_DIAG" && echo "=== camcal $NC ${PAT[0]}-${PAT[1]}" > /dev/kmsg
  for c in $CONNS; do args+=(--head "conn=$c,mode=$(modeof $c),pattern=${PAT[$i]},code=${CODES[$i]:-$((i+1))}"); i=$((i+1)); done
  python3 -I $TM/lib/kmsctl.py show "${args[@]}" --hold 600 < <(sleep 600) >$O/kms.json 2>&1 &
  KP=$!; sleep 8
  [ -n "${CAL_DIAG:-}" ] && diag $NC "${PAT[0]}-${PAT[1]}"
  return 0; }
cap() { python3 -I $TM/lib/camcheck.py capture $O/$1 >/dev/null; }
PAT=(black black); show; cap black
i=0
for c in $CONNS; do
  PAT=(black black); PAT[$i]=white; show; cap white-$c
  python3 -I $TM/lib/camcheck.py calib $O/white-$c.rgb $O/black.rgb $O/calib-$c.json || echo "CALIB FAILED $c"
  i=$((i+1))
done
# screens cut off at the top of the frame: tune top_ext on a bars frame (head i shows code CODES[i])
CODES=(1365 2730); PAT=(bars bars); show; sleep ${OSD_WAIT:-15}; cap bars
i=0
for c in $CONNS; do
  echo "$c top_ext/verdict: $(python3 -I $TM/lib/camcheck.py tune $O/calib-$c.json $O/bars.rgb ${CODES[$i]})"
  i=$((i+1))
done
stop
ls -l $O/calib-*.json
