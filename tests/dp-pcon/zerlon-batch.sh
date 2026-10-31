#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
# Zerlon on the dock, camera aimed at it. Copy crc.sh and zerlon-rb4k30.edid to /tmp on the board,
# then run: echo <pw> | sudo -S bash /tmp/zerlon-batch.sh   (about 75 s with gdm stopped)
cap() { timeout 10 gst-launch-1.0 -q v4l2src device=$(ls /dev/v4l/by-id/*-video-index0 | head -1) num-buffers=20 ! image/jpeg,width=1920,height=1080 ! multifilesink location=/tmp/zb-$1-%02d.jpg >/dev/null 2>&1; }
rd() { dd if=/dev/drm_dp_aux0 bs=1 skip=$(($1)) count=$2 status=none | xxd -p; }
wr() { printf "\\$(printf %03o $2)" | dd of=/dev/drm_dp_aux0 bs=1 seek=$(($1)) count=1 status=none; }
D=/sys/kernel/debug/dri/0/DP-1/edid_override
# ph <name> <mode> [force-0x3050-value]: the driver programs 0x3050 on enable; the optional value
# overrides it 2 s into the phase (test only)
ph() { n=$1; m=$2; echo "== $n $(date +%T) $m"
  (sleep 12) | modetest -M rockchip -s "86@84:$m" > /tmp/zb-mt-$n.log 2>&1 &
  sleep 2; [ -n "$3" ] && wr 0x3050 $3; sleep 4
  echo "$n crc $(sh /tmp/crc.sh 2 | tail -1) pcon=$(rd 0x3050 1)"; cap $n; wait; sleep 1; }
pkill -x modetest; rm -f /tmp/zb-*.jpg; systemctl stop gdm; sleep 2
ph ctl 2560x1440
ph hdmi 3840x2160-30
ph dvi 3840x2160-30 0
cat /tmp/zerlon-rb4k30.edid > $D; modetest -M rockchip -c >/dev/null 2>&1
ph rb '#0'
printf reset > $D; modetest -M rockchip -c >/dev/null 2>&1
systemctl start gdm; chmod 644 /tmp/zb-*.jpg; echo "done $(date +%T)"
