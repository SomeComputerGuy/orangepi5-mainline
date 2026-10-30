R=~/.local/share/fluster/resources; E4=$(~/cq/elem.sh h264 rkvdec)
d() { gst-launch-1.0 -q filesrc location=$(ls $R/JVT-AVC_V1/$1/* | head -1) ! h264parse ! $E4 ! fakesink >/dev/null 2>&1; }
n0=$(sudo -n dmesg | wc -l)
for i in $(seq 1 ${1:-10}); do d FM1_BT_B & d FM1_FT_E & wait; done
m=$(sudo -n dmesg | tail -n +$((n0+1)))
echo "FM1_BT_B+FM1_FT_E x${1:-10}: timeouts $(echo "$m" | grep -c 'timed out') page faults $(echo "$m" | grep -c 'Page fault') stall timeouts $(echo "$m" | grep -c 'stall request') bus-not-idle $(echo "$m" | grep -c 'bus not idle')"
