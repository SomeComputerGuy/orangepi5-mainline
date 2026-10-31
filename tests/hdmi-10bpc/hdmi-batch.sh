# SPDX-License-Identifier: GPL-2.0
# HDMI 10 bpc FRL diagnosis batch: run as root on the board; camera aimed at the TV.
O=/var/tmp/hb; rm -rf $O; mkdir -p $O
cap() { timeout 10 gst-launch-1.0 -q v4l2src device=$(ls /dev/v4l/by-id/*-video-index0 | head -1) num-buffers=20 ! image/jpeg,width=1920,height=1080 ! multifilesink location=$O/$1-%02d.jpg >/dev/null 2>&1; }
pkill -f '^python3 /var/tmp/camview'; pkill -x modetest; systemctl stop gdm; sleep 2
echo 'file phy-rockchip-samsung-hdptx.c +p; file dw-hdmi-qp.c +p; file dw_hdmi_qp-rockchip.c +p; file drm_hdmi_state_helper.c +p; file drm_hdmi_helper.c +p' > /sys/kernel/debug/dynamic_debug/control
echo 0x106 > /sys/module/drm/parameters/debug
modetest -M rockchip -c > $O/conn.txt 2>&1
cf() { awk -v w="$1" '/^88/{f=1} /^86|^90/{f=0} f&&/color format/{g=1} g&&/enums:/{for(i=2;i<=NF;i++){split($i,a,"=");if(a[1]==w){print a[2];exit}}}' $O/conn.txt; }
Y420=$(cf YCbCr420); Y444=$(cf YCbCr444); echo "enums 420=$Y420 444=$Y444" | tee $O/summary.txt
run() { n=$1; shift; dmesg -C
  (sleep 13) | modetest -M rockchip -a -s 88@83:$1 -P 35@83:${1%%-*}@XR24 "${@:2}" > $O/$n.mt 2>&1 &
  sleep 6; cap $n
  grep -A12 'HDMI-A-1' /sys/kernel/debug/dri/0/state | grep -E 'output_bpc|output_format|tmds' | tr -d '\t' | tr '\n' ' ' > $O/$n.state
  cat /sys/kernel/debug/dri/0/HDMI-A-1/scdc_status > $O/$n.scdc 2>/dev/null
  wait; dmesg > $O/$n.dmesg
  echo "$n $1 [$*] :: $(cat $O/$n.state) scdc31=$(sed -n 4p $O/$n.scdc | cut -d' ' -f2) scdc40=$(sed -n 5p $O/$n.scdc | cut -d' ' -f1) | $(grep -m1 -oE 'bpc=[0-9]+' $O/$n.dmesg) $(grep -c -iE 'training succeeded' $O/$n.dmesg)lts" | tee -a $O/summary.txt; sleep 1; }
run ctl  3840x2160-60  -w 88:'max bpc':8
run A    3840x2160-60  -w 88:'max bpc':10
run C    3840x2160-30  -w 88:'max bpc':10
run D    3840x2160-120 -w 88:'max bpc':8
[ -n "$Y420" ] && run E 3840x2160-120 -w 88:'max bpc':10 -w 88:'color format':$Y420
[ -n "$Y444" ] && run F 3840x2160-60  -w 88:'max bpc':10 -w 88:'color format':$Y444
echo 0 > /sys/module/drm/parameters/debug; systemctl start gdm; chmod -R a+r $O; echo done
