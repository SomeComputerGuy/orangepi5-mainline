#!/bin/sh
# SPDX-License-Identifier: GPL-2.0
# Minimal reproducer for "HDMI0 No Signal after leaving YCbCr 4:2:0" (Orange Pi 5 / RK3588S, dw-hdmi-qp).
#
# Runs N rounds of [4096x2160@60/593407 YCbCr 4:2:0 8 bpc TMDS -> 4096x2160@60 10 bpc RGB FRL] as
# back-to-back modesets from ONE DRM master (no fbdev restore in between) and judges every step by
# the controller's own input-lock bit (dw-hdmi-qp VIDEO_INTERFACE_STATUS0 bit 18, read through
# /dev/mem by hdmiregs.py, only while HDMI0 is enabled) and, if a webcam is calibrated, the camera.
# Without the fix about half of the FRL steps show "No Signal" (lock bit clear); with it, none.
#
# Needs: this directory copied to /var/tmp/wedge, testmatrix in /var/tmp/testmatrix, root, gdm stopped:
#   sudo systemctl stop gdm; sudo sh /var/tmp/wedge/minimal-repro.sh /var/tmp/wo/repro 10; sudo systemctl start gdm
# Camera: CALIB=<calib.json from wedge.py ... calib>; without one use NOCAM=1.
set -e
out=${1:-/var/tmp/wo/repro}; n=${2:-10}
. /var/tmp/wedge/seq.sh
S=""; i=0
while [ $i -lt $n ]; do
	S="$S|y$i:$T4096,$B8,$Y420,$LIN|f$i:$T4096,$B10,$AUTO,$AFBC30"
	i=$((i+1))
done
IFS='|'; set -- $S; shift; unset IFS
python3 -I /var/tmp/wedge/seqrun.py "$out" "$@" | grep -v '^{' | tee "$out.summary"
bad=$(awk -F'\t' '$1 ~ /^f/ && $4 !~ /VIF=0x0004/' "$out.summary" | wc -l)
echo "FRL steps without input lock (No Signal): $bad of $n"
