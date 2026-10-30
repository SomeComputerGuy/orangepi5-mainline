#!/bin/bash
# post-step checks for suspend testing
echo "== suspend_stats"; sudo cat /sys/kernel/debug/suspend_stats | head -12
echo "== pm_wakeup_irq: $(cat /sys/power/pm_wakeup_irq 2>&1)"
echo "== irq"; grep -E "hym8563|rk806|pwrkey" /proc/interrupts | awk '{s=0; for(i=2;i<=9;i++) s+=$i; print $1, s, $NF}'
echo "== cpufreq"; for p in /sys/devices/system/cpu/cpufreq/policy*; do echo "$p $(cat $p/scaling_cur_freq) $(cat $p/related_cpus)"; done
echo "== online: $(cat /sys/devices/system/cpu/online)"
echo "== SATA read"; sudo dd if=/dev/sda of=/dev/null bs=1M count=200 iflag=direct skip=$((RANDOM%2000)) 2>&1 | tail -1
echo "== SATA write"; sudo dd if=/dev/zero of=/var/tmp/susp-wtest bs=1M count=50 oflag=direct 2>&1 | tail -1; sudo rm -f /var/tmp/susp-wtest
echo "== net"; ip -br addr show end0; ping -c2 -W2 ${OPI5_HOST_IP:-172.31.55.1} | tail -2
echo "== usb"; lsusb | wc -l; lsusb -t | head -30
echo "== drm"; for c in /sys/class/drm/card*-*; do echo "$(basename $c) $(cat $c/status) $(cat $c/enabled 2>/dev/null)"; done
echo "== genpd on"; sudo cat /sys/kernel/debug/pm_genpd/pm_genpd_summary | grep -E "^[a-z0-9]+ +on"
echo "== dmesg err/warn since mark"; sudo dmesg --level=err,warn | tail -30
echo "== hdmi"; cat /sys/class/drm/card0-HDMI-A-1/status /sys/class/drm/card0-HDMI-A-1/enabled; modetest -M rockchip -c 2>/dev/null | awk '/HDMI-A/{p=1} p&&/#0|preferred/{print; n++} n>=2{exit}'
sudo dmesg | grep -iE "hdmi|scdc|frl" | tail -5
echo "== devfreq"; for d in /sys/class/devfreq/*; do echo "$(basename $d) $(cat $d/cur_freq) $(cat $d/governor)"; done
echo "== video devs"; for v in /sys/class/video4linux/video*; do printf "%s " "$(cat $v/name)"; done; echo
