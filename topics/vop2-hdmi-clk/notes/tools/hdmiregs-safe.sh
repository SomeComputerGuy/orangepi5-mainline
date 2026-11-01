#!/bin/sh
# SPDX-License-Identifier: GPL-2.0
# Read the known-safe dw-hdmi-qp status registers only if HDMI0 is really running:
# dclk_vop0 enabled (clk_summary enable count > 0) and an active CRTC driving HDMI-A-1.
en=$(awk '$1=="dclk_vop0"{print $2}' /sys/kernel/debug/clk/clk_summary)
st=$(awk '/^connector\[[0-9]+\]: HDMI-A-1/{f=1;next} /^connector/{f=0} f&&/crtc=/{print $1}' /sys/kernel/debug/dri/0/state)
if [ "${en:-0}" -gt 0 ] && [ -n "$st" ] && [ "$st" != "crtc=(null)" ]; then
	exec python3 -I /var/tmp/wedge/hdmiregs.py
fi
echo "HDMI0 not enabled (dclk_vop0 enable=$en, $st): not reading dw-hdmi-qp registers"
