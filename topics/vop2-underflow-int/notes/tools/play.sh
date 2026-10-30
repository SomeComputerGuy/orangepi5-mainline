#!/bin/bash
# play.sh <mode> <secs> <file> [decoder chain]: hold mode with modetest -d (console pattern on Cluster0),
# play the file with kmssink on plane 59 (Esmart0), count POST_BUF_EMPTY frames + VOP irq/s
mode=$1; secs=$2; f=$3; dec=${4:-"qtdemux ! h265parse ! v4l2slh265dec"}
s=$(awk "{print \$1}" /proc/uptime)
(sleep $((secs+4)) | sudo modetest -M rockchip -d -s 88@83:$mode > /tmp/mt.log 2>&1 &)
sleep 2
sudo timeout $((secs+1)) gst-launch-1.0 filesrc location=$f ! $dec ! fpsdisplaysink text-overlay=false signal-fps-measurements=true video-sink="kmssink connector-id=88 plane-id=59 skip-vsync=true" -v 2>&1 | grep -o "rendered: [0-9]*, dropped: [0-9]*, fps: [0-9.]*" | tail -1 > /tmp/fps.txt &
sleep 3; act=$(sudo grep "win0: ACTIVE" /sys/kernel/debug/dri/0/vop2/summary | tr -d " \t" | cut -d- -f1 | tr "\n" ","); r=$(~/vop2uf/irqrate.sh 3); wait; sleep 2.5
e=$(awk "{print \$1}" /proc/uptime)
n=$(sudo dmesg | awk -v s=$s -v e=$e "{t=substr(\$0,2,index(\$0,\"]\")-2)+0} t>=s && t<=e" | awk "/POST_BUF_EMPTY/{n++} /callbacks suppressed/{for(i=1;i<=NF;i++) if(\$i==\"callbacks\") m+=\$(i-1)} END{print n+m}")
echo "[play $mode ${secs}s $(basename $f)] underflow frames: $n  active wins: $act  irq/s: $r  fps: $(cat /tmp/fps.txt)"
