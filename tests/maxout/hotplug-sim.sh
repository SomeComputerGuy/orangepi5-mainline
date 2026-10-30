#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Software-simulated display/dongle yanking during playback (weston + one looping 4K player per display).
#   hotplug-sim.sh [cycles=20] [kinds]     kinds: drm-dp drm-hdmi altmode pin usb all   (default: all of them)
# Each cycle picks a kind (or "all" = several at once with random delays), applies it, restores, then checks:
#   no Oops/SError/hung task/IOMMU fault/decoder timeout/flip_done timeout in dmesg; weston alive;
#   the affected connector is connected again and its CRTC active (weston re-enabled the output);
#   the other display's player didn't drop (per-second fps >= 90% nominal); USB re-enumerates (lsusb count);
#   end0 (our SSH) loses no pings to ${OPI5_HOST_IP:-172.31.55.1}.
# Kinds: drm-dp / drm-hdmi: /sys/class/drm/card0-<conn>/status off -> on -> detect
#        altmode: typec partner altmode active 0 -> 1      pin: pin_assignment C <-> D (and back)
#        usb: unbind/bind the dongle hubs (8-1 SuperSpeed, 7-1 high-speed) -> AX88179/cdc_ncm netdev vanishes
#        busy variants run while a third CCU decode (fakevideosink) is active; "modeset" variant restarts the
#        DP player at the same moment (weston modeset of the output) — included in "all".
N=${1:-20}; shift; KINDS=${*:-drm-dp drm-hdmi altmode pin usb all}
H=$HOME/hotplug-sim; mkdir -p $H; R=$H/report.txt; : > $R
say() { echo "$*" | tee -a $R; }
W="XDG_RUNTIME_DIR=/run/user/0 WAYLAND_DISPLAY=wayland-9"
PY="env PYTHONPATH=$HOME/npu-venv/lib/python3.14/site-packages python3"
TC=/sys/bus/typec/devices/port0-partner.0
now() { cut -d' ' -f1 /proc/uptime; }
st() { cat /sys/class/drm/card0-$1/status; }
kerr() { sudo dmesg | awk -v t="$1" '{x=$1; gsub(/[][]/,"",x); if (x+0>t) print}' | \
  grep -iE 'timeout|timed out|fault|oops|serror|BUG|WARNING|hung task|Unable to handle|flip_done|call trace' | sed -E 's/^\[ *[0-9.]+\] //' | sort | uniq -c | head -8; }
crtc_active() {  # is the CRTC driving connector $1 active? (DRM atomic state, not regmap)
  sudo awk -v c="$1" '/^connector\[/{f=index($0,c)>0} f&&/crtc=/{print $1; exit}' /sys/kernel/debug/dri/0/state 2>/dev/null; }
source <(sed -n "/^dev_of/,/^demux_for/p" $HOME/maxout/maxout.sh)
H265=$(dec_for h265); VP9=$(dec_for vp9); H264=$(dec_for h264)

if ! pgrep -x weston >/dev/null; then
  sudo mkdir -p /run/user/0; sudo chmod 700 /run/user/0
  sudo env XDG_RUNTIME_DIR=/run/user/0 LIBSEAT_BACKEND=noop nohup weston --backend=drm --shell=desktop \
    --continue-without-input --idle-time=0 --socket=wayland-9 --log=$H/weston.log >/dev/null 2>&1 </dev/null &
  sleep 8
fi
player() {  # player <HDMI-A-1|DP-1>
  if [ $1 = HDMI-A-1 ]; then sudo env $W $PY $HOME/maxout/stream.py $HOME/demo/yacht_hevc_2160p120.mp4 HDMI-A-1 $H/hdmi.log --codec h265 --dec $H265 --secs 3600 &
  else sudo env $W $PY $HOME/maxout/stream.py $HOME/demo/yacht_vp9_2160p120.webm DP-1 $H/dp.log --codec vp9 --dec $VP9 --secs 3600 & fi; }
player HDMI-A-1; player DP-1; sleep 8
( ping -i 0.2 ${OPI5_HOST_IP:-172.31.55.1} > $H/ping.log 2>&1 ) & PING=$!
fpsmin() {  # fpsmin <log> <from epoch> <to epoch> -> "min below"
  awk -v a=$2 -v b=$3 '$2=="SEC" && $1>=a && $1<=b {split($5,f,"="); if(min==""||f[2]<min)min=f[2]} END{print (min==""?"none":min)}' $1; }
busy_dec() { timeout $1 gst-launch-1.0 -q filesrc location=$HOME/demo/yacht_h264_2160p120.mp4 ! qtdemux ! h264parse ! $H264 ! fakevideosink >/dev/null 2>&1 & }

do_kind() {  # applies one kind; echoes the connector it disturbs ("" = none)
  case $1 in
  drm-dp)   echo off | sudo tee /sys/class/drm/card0-DP-1/status >/dev/null; sleep 0.$((RANDOM%9+1)); sleep $((RANDOM%3))
            echo on | sudo tee /sys/class/drm/card0-DP-1/status >/dev/null; sleep 1; echo detect | sudo tee /sys/class/drm/card0-DP-1/status >/dev/null ;;
  drm-hdmi) echo off | sudo tee /sys/class/drm/card0-HDMI-A-1/status >/dev/null; sleep 0.$((RANDOM%9+1)); sleep $((RANDOM%3))
            echo on | sudo tee /sys/class/drm/card0-HDMI-A-1/status >/dev/null; sleep 1; echo detect | sudo tee /sys/class/drm/card0-HDMI-A-1/status >/dev/null ;;
  altmode)  echo 0 | sudo tee $TC/active >/dev/null; sleep 0.$((RANDOM%9+1)); sleep $((RANDOM%3)); echo 1 | sudo tee $TC/active >/dev/null ;;
  pin)      local p0; p0=$(grep -oE '\[[A-F]\]' $TC/displayport/pin_assignment | tr -d '[]')
            for p in C D; do [ $p != "$p0" ] && echo $p | sudo tee $TC/displayport/pin_assignment >/dev/null; done; sleep $((RANDOM%3+1))
            echo $p0 | sudo tee $TC/displayport/pin_assignment >/dev/null ;;
  usb)      for h in 8-1 7-1; do echo $h | sudo tee /sys/bus/usb/drivers/usb/unbind >/dev/null 2>&1; done; sleep 0.$((RANDOM%9+1)); sleep $((RANDOM%3))
            for h in 7-1 8-1; do echo $h | sudo tee /sys/bus/usb/drivers/usb/bind >/dev/null 2>&1; done ;;
  modeset)  sudo pkill -INT -f "stream.py.*DP-1"; sleep 0.3; player DP-1 ;;
  esac
}
U0=$(lsusb | wc -l); NET0=$(ip -br link | grep -c '^enx')
say "# hotplug-sim $(date '+%F %T') $(uname -v) N=$N kinds: $KINDS; usb devices $U0, dongle netdevs $NET0"
declare -A PASS FAIL
ks=($KINDS)
for ((i=1; i<=N; i++)); do
  k=${ks[$((RANDOM % ${#ks[@]}))]}; t0=$(now); e0=$(date +%s.%N)
  [ $((RANDOM % 2)) = 0 ] && { busy_dec 6; busy=" +ccu-busy"; } || busy=""
  if [ $k = all ]; then
    for kk in drm-dp altmode usb pin modeset drm-hdmi; do [ $((RANDOM % 2)) = 0 ] && { do_kind $kk & sleep 0.$((RANDOM%5)); }; done; wait
  else do_kind $k; fi
  # recovery window
  for ((s=0; s<20; s++)); do [ "$(st DP-1)" = connected ] && [ "$(st HDMI-A-1)" = connected ] && [ $(lsusb | wc -l) -ge $U0 ] && break; sleep 1; done
  sleep 4; e1=$(date +%s.%N)
  bad=""
  [ "$(st DP-1)" = connected ] || bad="$bad; DP-1 $(st DP-1)"
  [ "$(st HDMI-A-1)" = connected ] || bad="$bad; HDMI-A-1 $(st HDMI-A-1)"
  pgrep -x weston >/dev/null || bad="$bad; WESTON DIED"
  [ $(lsusb | wc -l) -ge $U0 ] || bad="$bad; usb $(lsusb | wc -l)/$U0"
  [ $(ip -br link | grep -c '^enx') -ge $NET0 ] || bad="$bad; dongle netdev missing"
  for c in DP-1 HDMI-A-1; do a=$(crtc_active $c); [ -z "$a" ] || [ "$a" = "crtc=(null)" ] && bad="$bad; $c has no CRTC (weston did not re-enable)"; done
  case $k in drm-dp|altmode|pin|usb) fm=$(fpsmin $H/hdmi.log $e0 $e1); [ "$fm" != none ] && [ "$fm" -lt 54 ] && bad="$bad; HDMI (undisturbed) fps dipped to $fm" ;;
             drm-hdmi) fm=$(fpsmin $H/dp.log $e0 $e1); [ "$fm" != none ] && [ "$fm" -lt 27 ] && bad="$bad; DP (undisturbed) fps dipped to $fm" ;; esac
  for c in hdmi dp; do grep -q "stream.py.*$( [ $c = dp ] && echo DP-1 || echo HDMI-A-1)" <(pgrep -af stream.py) || { bad="$bad; $c player exited ($(grep -E 'ERROR' $H/$c.log | tail -1 | cut -c1-100))"; player $( [ $c = dp ] && echo DP-1 || echo HDMI-A-1); sleep 5; }; done
  ke=$(kerr $t0); [ -n "$ke" ] && bad="$bad; kernel: $(echo "$ke" | head -3 | tr '\n' '|')"
  if [ -z "$bad" ]; then PASS[$k]=$((PASS[$k]+1)); echo "cycle $i $k$busy: ok" >> $H/cycles.log
  else FAIL[$k]=$((FAIL[$k]+1)); echo "cycle $i $k$busy: FAIL$bad" | tee -a $H/cycles.log >> $R
    [ -d $H/fail-$i ] || { mkdir -p $H/fail-$i; sudo dmesg | tail -80 > $H/fail-$i/dmesg.txt; tail -20 $H/weston.log > $H/fail-$i/weston.txt
      sudo cat /sys/kernel/debug/dri/0/state > $H/fail-$i/drm-state.txt 2>/dev/null; lsusb -t > $H/fail-$i/usb.txt; }
  fi
  sleep $((RANDOM % 3 + 1))
done
kill $PING; sudo pkill -INT -f maxout/stream.py; sleep 3
say "per kind (pass/fail): $(for k in $KINDS; do printf '%s %d/%d; ' $k ${PASS[$k]:-0} ${FAIL[$k]:-0}; done)"
say "end0 pings: $(tail -2 $H/ping.log | head -1)"
say "HDMI player: $(grep TOTAL $H/hdmi.log | cut -c1-120)   DP player: $(grep TOTAL $H/dp.log | cut -c1-120)"
say "DONE $(date '+%F %T')"
