#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
# Display matrix with objective verification. Runs ON the board as root, unattended and resumable
# (rerun the same command after a hang/reboot; finished cases are kept, the case that was running is
# recorded as FAIL). Needs the KMS device to itself: pass --stop-gdm to stop gdm for the run (it is
# started again on exit), or stop it yourself.
#
#   sudo ./display-matrix.sh [--stop-gdm] [--out DIR] [--cam CONN] [--groups LIST] [--conn LIST] [--max N]
#   sudo ./display-matrix.sh --list            # print the cases, run nothing
#   sudo ./display-matrix.sh --summary         # rebuild summary.txt / results-final.tsv
#   sudo ./display-matrix.sh --fresh ...       # forget a previous run in DIR
#
# Groups: calib (webcam: white/black + known-good/known-bad modes), modes (every EDID mode, kmsctl),
#   modetest (every mode again through modetest -a with an explicit -P plane), props (every mode x max bpc
#   x color format), hdr, vrr, planes (every plane x format x modifier at the preferred mode), dual.
# Env: CAM_CONN (monitor under the webcam, e.g. DP-1), CAM_DEV, CAM_NAME (default Aluratek),
#   CAM_CALIB_MODE (1920x1080@60), CAM_KNOWN ("1920x1080@60=GOOD 2560x1440@60=GOOD 3840x2160@30/297000=BAD"),
#   SETTLE (4 s after commit), CAM_SETTLE (+3 s for the camera monitor), PROPS_MODES=all|unique,
#   CRC_GOLDEN (crc-golden.json of a known-good run), SRC_TMDS_MAX_MHZ (600), SRC_FRL_MAX (10x4).
set -uo pipefail
[ "$(id -u)" -eq 0 ] || exec sudo -E "$0" "$@"
D=$(cd "$(dirname "$0")" && pwd)
OUT=/var/tmp/testmatrix/display; STOP_GDM=0; ARGS=(); MODE=run; FRESH=0
while [ $# -gt 0 ]; do
  case $1 in
    --out) OUT=$2; shift ;;
    --cam) export CAM_CONN=$2; shift ;;
    --stop-gdm) STOP_GDM=1 ;;
    --groups|--conn|--max) ARGS+=("$1" "$2"); shift ;;
    --list) MODE=list ;;
    --summary) MODE=summary ;;
    --fresh) FRESH=1 ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "unknown option $1" >&2; exit 2 ;;
  esac; shift
done
mkdir -p "$OUT"
[ $FRESH = 1 ] && rm -rf "${OUT:?}/cases.json" "$OUT/results.tsv" "$OUT/inprogress" "$OUT/calib.json" "$OUT/case"
for t in python3 modetest; do command -v $t >/dev/null || { echo "missing $t" >&2; exit 1; }; done
[ -n "${CAM_CONN:-}" ] && ! command -v gst-launch-1.0 >/dev/null && { echo "webcam needs gst-launch-1.0" >&2; exit 1; }
mountpoint -q /sys/kernel/debug || mount -t debugfs none /sys/kernel/debug
[ -r /sys/kernel/debug/dri/0/state ] || { echo "no /sys/kernel/debug/dri/0/state" >&2; exit 1; }

if [ $MODE = summary ]; then
  exec python3 -I -c "import sys,json; sys.path.insert(0,'$D/lib'); import dmatrix
info, cases = json.load(open('$OUT/cases.json')); dmatrix.summarize('$OUT', cases)"
fi
if [ $MODE = list ]; then exec python3 -I "$D/lib/dmatrix.py" --out "$OUT" "${ARGS[@]}" --list-only; fi

masters=$(pgrep -a -x 'gnome-shell|Xorg|weston|kwin_wayland|sway|mutter|gamescope' || true)
if [ -n "$masters" ]; then
  if [ $STOP_GDM = 1 ] && systemctl is-active -q gdm; then
    echo "stopping gdm for the run (restarted on exit)"
    trap 'systemctl start gdm' EXIT
    systemctl stop gdm; sleep 3
    masters=$(pgrep -a -x 'gnome-shell|Xorg|weston|kwin_wayland|sway|mutter|gamescope' || true)
  fi
  [ -n "$masters" ] && { echo "a compositor holds the display (pass --stop-gdm or stop it):"; echo "$masters"; exit 1; }
fi
pkill -INT -x modetest 2>/dev/null; pkill -INT -x gst-launch-1.0 2>/dev/null
{ echo "# $(date '+%F %T') $(uname -r) $(uname -v) cam=${CAM_CONN:-none} args=${ARGS[*]:-}"; } >> "$OUT/runs.log"
python3 -I "$D/lib/dmatrix.py" --out "$OUT" "${ARGS[@]}"
rc=$?
chown -R "${SUDO_UID:-0}:${SUDO_GID:-0}" "$OUT" 2>/dev/null
exit $rc
