#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
# Unattended replay of the three VOP2 POST_BUF_EMPTY cases (vop2-underflow v2). Run on the board as root
# (or via sudo); stops gdm for the run and starts it again afterwards. Needs: python3, the webcam pointed
# at the HDMI TV (optional, picture verdicts are skipped without it), gst-launch-1.0 for the camera.
#   sudo ./vop2uf-test.sh [OUTDIR]        default /var/tmp/vop2uf/<date-time>
# Result: OUTDIR/summary.txt (one line per case, PASS/FAIL against the patched kernel's expectations).
set -uo pipefail
[ "$(id -u)" -eq 0 ] || exec sudo -E "$0" "$@"
D=$(cd "$(dirname "$0")" && pwd)
OUT=${1:-/var/tmp/vop2uf/$(date +%Y%m%d-%H%M%S)}
mkdir -p "$OUT"
mountpoint -q /sys/kernel/debug || mount -t debugfs none /sys/kernel/debug
if systemctl is-active -q gdm 2>/dev/null; then
  trap 'systemctl start gdm' EXIT
  systemctl stop gdm; sleep 3
fi
pkill -INT -x modetest 2>/dev/null; pkill -INT -x gst-launch-1.0 2>/dev/null
masters=$(pgrep -a -x 'gnome-shell|Xorg|weston|kwin_wayland|sway|mutter|gamescope' || true)
[ -n "$masters" ] && { echo "a compositor still holds the display: $masters" | tee "$OUT/summary.txt"; exit 1; }
{
  echo "# kernel $(uname -r) $(cat /proc/version)"
  echo "# rockchipdrm: $(modinfo -n rockchipdrm 2>/dev/null) srcversion $(cat /sys/module/rockchipdrm/srcversion 2>/dev/null)"
} >> "$OUT/summary.txt"
timeout 1800 python3 -I "$D/vop2uf.py" "$OUT"
rc=$?
echo "# exit $rc" >> "$OUT/summary.txt"
chown -R "${SUDO_UID:-0}:${SUDO_GID:-0}" "$OUT" 2>/dev/null
echo "summary: $OUT/summary.txt"
exit $rc
