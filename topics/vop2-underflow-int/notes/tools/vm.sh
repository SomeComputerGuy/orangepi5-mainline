#!/bin/bash
# vm.sh <label> <hdmi mode> <dp mode|-> <load 0|1> <secs>
# modetest -d holds the mode(s) with a pattern on each primary plane (console stand-in, no cursor);
# kmssink skip-vsync=true plays the 4K60 clip on HDMI plane 59 and the 4K30 clip on DP plane 65.
label=$1 hm=$2 dm=$3 load=$4 secs=$5
P="matroskademux ! h265parse ! v4l2slh265dec"
play() { sudo timeout $secs gst-launch-1.0 filesrc location=$2 ! $P ! fpsdisplaysink text-overlay=false video-sink="kmssink connector-id=$1 plane-id=$3 skip-vsync=true" -v 2>&1 | grep -o "rendered: [0-9]*, dropped: [0-9]*" | tail -1 > /tmp/fps.$1; }
s=$(awk "{print \$1}" /proc/uptime)
dpa=""; [ "$dm" != - ] && dpa="-s 86@84:$dm"
(sleep $((secs+6)) | sudo modetest -M rockchip -d -s 88@83:$hm $dpa > /tmp/mt.log 2>&1 &)
sleep 2.5
[ "$load" = 1 ] && (sudo timeout $((secs+2)) sh -c "while :; do gst-launch-1.0 -q filesrc location=~/demo/yacht_hevc_2160p120.mp4 ! qtdemux ! h265parse ! v4l2slh265dec ! fakesink sync=false; done" >/dev/null 2>&1 &)
play 88 ~/codecsweep/work/ref_h265_3840x2160_60.mkv 59 &
[ "$dm" != - ] && play 86 ~/codecsweep/work/ref_h265_3840x2160_30.mkv 65 &
sleep 6; pl=$(sudo python3 -I ~/vop2uf/portload.py); wait; sleep 3
e=$(awk "{print \$1}" /proc/uptime)
n=$(sudo dmesg | awk -v s=$s -v e=$e "{t=substr(\$0,2,index(\$0,\"]\")-2)+0} t>=s && t<=e" | awk "/POST_BUF_EMPTY/{n++} /callbacks suppressed/{for(i=1;i<=NF;i++) if(\$i==\"callbacks\") m+=\$(i-1)} END{print n+m}")
echo "[$label] HDMI $hm DP $dm load=$load ${secs}s :: underflow frames: $n :: HDMI($(cat /tmp/fps.88)) ${dpa:+DP($(cat /tmp/fps.86))}"
echo "     $pl"
rm -f /tmp/fps.88 /tmp/fps.86
