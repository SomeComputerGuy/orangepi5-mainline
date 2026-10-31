#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
# GNOME session check (image test sheet, step 1): does the gdm greeter (or the logged-in session) light
# every connected output? Checks mutter DisplayConfig GetCurrentState (monitor has a current mode and a
# logical monitor), PowerSaveMode == 0, the kernel atomic state (active CRTC with a framebuffer plane,
# dpms On) and, with CAM_CONN set, the webcam (screen lit, not black). Read-only unless --wake (sets
# PowerSaveMode 0 if the greeter blanked) or --modes (applies every mutter mode, temporary config, and
# restores the original mode). Does not stop gdm.
#   sudo [CAM_CONN=DP-1] ./gnome-check.sh [--wake] [--modes] [--out DIR] [--calib DIR/calib.json]
# --calib: calib.json from a display-matrix.sh run with the camera in the same position (without it the
# webcam frame is only saved, verdict MANUAL). Exit status 0 = every output PASS.
set -uo pipefail
[ "$(id -u)" -eq 0 ] || exec sudo -E "$0" "$@"
D=$(cd "$(dirname "$0")" && pwd)
mountpoint -q /sys/kernel/debug || mount -t debugfs none /sys/kernel/debug
python3 -I "$D/lib/gnomecheck.py" check "$@"
