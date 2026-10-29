#!/bin/bash
# usage: cmpvp9.sh <vector name>  -> prints first mismatching frames
V=$1; D=~/.local/share/fluster/resources/VP9-TEST-VECTORS/$V/$V; O=~/vp9conf/dbg/$V; mkdir -p $O
timeout 120 gst-launch-1.0 -q filesrc location=$D ! parsebin ! v4l2slvp9dec ! videoconvert dither=none ! video/x-raw,format=I420 ! filesink location=$O/hw.yuv >$O/gst.log 2>&1
timeout 120 ffmpeg -v error -y -c:v libvpx-vp9 -i $D -f rawvideo -pix_fmt yuv420p $O/ref.yuv
WH=$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=p=0 $D)
python3 -I ~/vp9conf/bin/cmp.py $O/hw.yuv $O/ref.yuv ${WH/,/ }
