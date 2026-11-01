# SPDX-License-Identifier: GPL-2.0
A=/dev/drm_dp_aux0
wr() { printf "\\x$2" | dd of=$A bs=1 seek=$(($1)) count=1 conv=notrunc status=none; }
rd() { dd if=$A bs=1 skip=$(($1)) count=$2 status=none | xxd -p; }
cap() { timeout 10 gst-launch-1.0 -q v4l2src device=$(ls /dev/v4l/by-id/*-video-index0 | head -1) num-buffers=20 ! image/jpeg,width=1920,height=1080 ! multifilesink location=/tmp/zs-$1-%02d.jpg >/dev/null 2>&1; }
pkill -x modetest; rm -f /tmp/zs-*.jpg; systemctl stop gdm; sleep 2
for c in force:08 noauto:04; do n=${c%%:*}; v=${c#*:}
  (sleep 14) | modetest -M rockchip -s 86@84:3840x2160-30 > /tmp/zs-$n.log 2>&1 &
  sleep 3; wr 0x3051 $v; sleep 3; echo "$n 3050-3052=$(rd 0x3050 3)"; cap $n; wait; wr 0x3051 00; sleep 1; done
systemctl start gdm; chmod 644 /tmp/zs-*.jpg; echo done
