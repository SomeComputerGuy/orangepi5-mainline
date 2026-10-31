# SPDX-License-Identifier: GPL-2.0
O=/var/tmp/hb; mkdir -p $O; t=$1
systemctl stop gdm; sleep 2; dmesg -C
(sleep 13) | modetest -M rockchip -a -s 88@83:3840x2160-60 -P 35@83:3840x2160@XR24 -w 88:'max bpc':10 > $O/$t.mt 2>&1 &
sleep 7; echo "$t $(modinfo -n rockchipdrm) $(grep -A12 HDMI-A-1 /sys/kernel/debug/dri/0/state | grep -E 'output_bpc|tmds' | tr -d '\t' | tr '\n' ' ') scdc=$(sed -n 4p /sys/kernel/debug/dri/0/HDMI-A-1/scdc_status | cut -c1-6)/$(sed -n 5p /sys/kernel/debug/dri/0/HDMI-A-1/scdc_status | cut -c1-3)"
timeout 10 gst-launch-1.0 -q v4l2src device=$(ls /dev/v4l/by-id/*-video-index0 | head -1) num-buffers=20 ! image/jpeg,width=1920,height=1080 ! multifilesink location=$O/$t-%02d.jpg >/dev/null 2>&1
wait; systemctl start gdm; chmod -R a+r $O
