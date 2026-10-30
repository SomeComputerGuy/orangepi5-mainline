#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Display hot-unplug / replug during playback. Runs ON the board; a human pulls the cables.
#   hotplug.sh [step ...]     steps: dp hdmi dp-modeset hdmi-modeset (default: dp hdmi dp-modeset)
# For each step the script prints "ACTION: ..." (also in ~/hotplug/PROMPT) and waits up to 10 min for the
# connector status to change, so the timing of the human doesn't matter.
# dp/hdmi: weston + one looping 4K player per display (stream.py, local clips). Unplug one display, wait 20 s,
#   replug, wait 20 s. Pass = no kernel errors/oops/hangs; the player on the pulled output keeps running or exits
#   cleanly; weston survives and re-enables the output; the other display's player never stutters (per-second fps
#   stays >= 90% of nominal); USB devices behind the dongle come back (lsusb count).
# *-modeset: weston stopped; modetest alternates 2 modes on the connector every 0.5 s while the cable is pulled.
STEPS=${*:-dp hdmi dp-modeset}
H=$HOME/hotplug; mkdir -p $H; R=$H/report.txt; : > $R; P=$H/PROMPT
say() { echo "$*" | tee -a $R; }
ask() { echo "$(date +%T) ACTION: $*" | tee $P | tee -a $R; }
W="XDG_RUNTIME_DIR=/run/user/0 WAYLAND_DISPLAY=wayland-9"
PY="env PYTHONPATH=$HOME/npu-venv/lib/python3.14/site-packages python3"
st() { cat /sys/class/drm/card*-$1/status 2>/dev/null | head -1; }
waitst() { for ((s=0; s<600; s++)); do [ "$(st $1)" = "$2" ] && return 0; sleep 1; done; return 1; }
now() { cut -d' ' -f1 /proc/uptime; }
kerr() { sudo dmesg | awk -v t="$1" '{x=$1; gsub(/[][]/,"",x); if (x+0>t) print}' | \
  grep -iE 'timeout|timed out|fault|oops|serror|BUG|WARNING|hung task|Unable to handle|flip_done|error' | sed -E 's/^\[ *[0-9.]+\] //' | sort | uniq -c | head -15; }
source <(sed -n "/^dev_of/,/^demux_for/p" $HOME/maxout/maxout.sh)
H265=$(dec_for h265); VP9=$(dec_for vp9)

start_weston() {
  pgrep -x weston >/dev/null && return
  sudo mkdir -p /run/user/0; sudo chmod 700 /run/user/0
  sudo env XDG_RUNTIME_DIR=/run/user/0 LIBSEAT_BACKEND=noop nohup weston --backend=drm --shell=desktop \
    --continue-without-input --idle-time=0 --socket=wayland-9 --log=$H/weston.log >/dev/null 2>&1 </dev/null &
  sleep 8
}
players() {  # HDMI: HEVC 4K120 clip (shown at 60), DP: VP9 4K120 clip (shown at 30)
  sudo env $W $PY $HOME/maxout/stream.py $HOME/demo/yacht_hevc_2160p120.mp4 HDMI-A-1 $H/$1.hdmi.log --codec h265 --dec $H265 --secs 900 &
  sudo env $W $PY $HOME/maxout/stream.py $HOME/demo/yacht_vp9_2160p120.webm DP-1 $H/$1.dp.log --codec vp9 --dec $VP9 --secs 900 &
  sleep 6
}
stop_players() { sudo pkill -INT -f maxout/stream.py; sleep 3; sudo pkill -KILL -f maxout/stream.py; }
# fps per second of a stream.py log between two epoch times: min and count of seconds below threshold
fpsrange() { awk -v a=$2 -v b=$3 -v th=$4 '$2=="SEC" && $1>=a && $1<=b {split($5,f,"="); n++; if(min==""||f[2]<min)min=f[2]; if(f[2]<th)low++}
  END{printf "%d s sampled, min %s fps, %d s below %d", n, min, low, th}' $1; }

hp_step() {  # hp_step <dp|hdmi>
  local c=DP-1 other=hdmi oth=54; [ $1 = hdmi ] && { c=HDMI-A-1; other=dp; oth=27; }
  [ "$(st $c)" = connected ] || { say "$1: $c not connected at start, skipping"; return; }
  start_weston; local t0=$(now) u0=$(lsusb | wc -l); players $1
  local e0=$(date +%s.%N)
  ask "unplug $c (the $( [ $1 = dp ] && echo 'USB-C dongle' || echo 'HDMI cable')) now"
  waitst $c disconnected || { say "$1: timed out waiting for unplug"; stop_players; return; }
  local e1=$(date +%s.%N); say "$1: $c disconnected at $(date +%T)"; sleep 20
  ask "replug $c now"
  waitst $c connected || { say "$1: timed out waiting for replug"; }
  local e2=$(date +%s.%N); say "$1: $c connected at $(date +%T)"; sleep 20
  local e3=$(date +%s.%N)
  say "$1: weston alive: $(pgrep -x weston >/dev/null && echo yes || echo NO)"
  say "$1: weston log since start: $(grep -iE 'output|hotplug|connector|error|fail' $H/weston.log | tail -6 | tr '\n' '|')"
  say "$1: pulled-output player: $(tail -1 $H/$1.$( [ $1 = dp ] && echo dp || echo hdmi).log | cut -c1-160)"
  say "$1: pulled-output player alive: $(pgrep -f "stream.py.*$c" >/dev/null && echo yes || echo exited) $(grep -m2 -E 'ERROR|WARNING' $H/$1.*.log | cut -c1-160 | tr '\n' '|')"
  say "$1: other display ($other) fps during unplug: $(fpsrange $H/$1.$other.log $e1 $e2 $oth); during replug: $(fpsrange $H/$1.$other.log $e2 $e3 $oth)"
  say "$1: USB devices before $u0, after $(lsusb | wc -l)"
  say "$1: kernel messages:"; kerr $t0 >> $R
  stop_players
}
modeset_step() {  # modeset_step <dp|hdmi>
  local c=DP-1; [ $1 = hdmi ] && c=HDMI-A-1
  sudo pkill -x weston; sleep 2
  local id=$(sudo modetest -M rockchip -c 2>/dev/null | awk -v n=$c '$4==n{print $1; exit}')
  local modes=($(sudo modetest -M rockchip -c 2>/dev/null | awk -v id=$id '$1==id{f=1} f&&/#[0-9]+ [0-9]+x[0-9]+/{print $2"-"$3; if(++k==2) exit}'))
  say "$1-modeset: connector $id modes ${modes[*]}"
  local t0=$(now)
  ( while [ ! -e $H/stop ]; do for m in "${modes[@]}"; do timeout 1 sudo modetest -M rockchip -s $id:${m%%-*}@0 >/dev/null 2>&1; done; done ) &
  local L=$!
  ask "unplug $c now (mode sets are running every ~0.5 s), then replug it after ~10 s"
  waitst $c disconnected; say "$1-modeset: disconnected $(date +%T)"; waitst $c connected; say "$1-modeset: connected $(date +%T)"
  sleep 10; touch $H/stop; wait $L 2>/dev/null; rm -f $H/stop
  timeout 10 sudo modetest -M rockchip -s $id:${modes[0]%%-*} >/dev/null 2>&1 & sleep 3
  say "$1-modeset: modetest after replug: $(sudo pkill -INT -x modetest && echo ran || echo 'did not run')"
  say "$1-modeset: kernel messages:"; kerr $t0 >> $R
}
say "# hotplug $(date '+%F %T') $(uname -v) steps: $STEPS"
for s in $STEPS; do case $s in dp|hdmi) hp_step $s ;; *-modeset) modeset_step ${s%-modeset} ;; esac; done
start_weston
echo "$(date +%T) DONE" > $P; say "DONE $(date '+%F %T')"
