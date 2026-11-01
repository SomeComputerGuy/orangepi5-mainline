#!/bin/sh
# SPDX-License-Identifier: GPL-2.0
# usage: run.sh <outdir> <logname> STEP...   (root, gdm stopped). Kernel log (drm.debug=0x6 + dyndbg of the HDMI
# path, panthor filtered) is streamed to <outdir>/<logname>.
out=$1; log=$2; shift 2
mkdir -p "$out"; [ -f "$out/calib.json" ] || cp /var/tmp/wo/r1/calib.json "$out/"
for f in phy-rockchip-samsung-hdptx.c dw-hdmi-qp.c dw_hdmi_qp-rockchip.c rockchip_drm_vop2.c; do
	echo "file $f +p" > /sys/kernel/debug/dynamic_debug/control
done
echo 0x6 > /sys/module/drm/parameters/debug
dmesg -C
dmesg -w | grep -v -E 'panthor|drm_dp_dpcd|fde50000.dp|Probed mode|printmodeline|mode_prune|CONNECTOR:86' > "$out/$log" &
dp=$!
KMSCTL_PROBE=1 POSTCAP=${POSTCAP:-1} python3 -I /var/tmp/wedge/wedge.py "$out" run "$@"
sleep 1; kill $dp
echo 0 > /sys/module/drm/parameters/debug
