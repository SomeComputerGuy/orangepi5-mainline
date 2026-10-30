R=~/.local/share/fluster/resources; P=/sys/module/rockchip_vdec/parameters; E4=$(~/cq/elem.sh h264 rkvdec)
V=$R/JVT-AVC_V1/HCBP1_HHI_A/HCBP1_HHI_A.264; B=$R/JVT-AVC_V1/FM1_FT_E/$(ls $R/JVT-AVC_V1/FM1_FT_E | head -1)
fm() { gst-launch-1.0 -q filesrc location=$V ! h264parse ! $E4 ! videoconvert ! video/x-raw,format=I420 ! fdsink fd=1 2>/dev/null | ffmpeg -nostdin -v error -f rawvideo -pix_fmt yuv420p -s $(ffprobe -v error -f h264 -show_entries stream=width,height -of csv=s=x:p=0 $V) -i - -f framemd5 - | grep -v "^#" | awk -F, '{print $NF}'; }
echo 0 | sudo -n tee $P/pipeline $P/ccu_hw >/dev/null; fm > /tmp/ref.md5
echo 1 | sudo -n tee $P/pipeline $P/ccu_hw >/dev/null
for i in 1 2; do { fm > /tmp/t$i.md5 & gst-launch-1.0 -q filesrc location=$B ! h264parse ! $E4 ! fakesink 2>/dev/null; wait; }
 echo "run $i: frames $(wc -l < /tmp/t$i.md5)/$(wc -l < /tmp/ref.md5), differing: $(paste -d' ' /tmp/ref.md5 /tmp/t$i.md5 | awk '$1!=$2{printf "%d ", NR-1}' | cut -c1-200)"; done
sudo -n dmesg | grep -iE "resetting|failing|timed" | tail -4
