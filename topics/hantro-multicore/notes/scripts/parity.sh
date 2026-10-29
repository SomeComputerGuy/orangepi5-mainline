#!/bin/sh
# Encode each input with v4l2jpegenc and print md5 of the MJPEG stream. $1 = tag
D=/var/tmp/hmc; O=$D/out-$1; mkdir -p $O
enc() { # name fmt w h
  bs=$(stat -c %s $D/$1); n=$5
  timeout 60 gst-launch-1.0 -q filesrc location=$D/$1 blocksize=$(( bs / n )) ! rawvideoparse format=$2 width=$3 height=$4 framerate=30/1 ! v4l2jpegenc ! filesink location=$O/$1.mjpeg || echo "FAIL $1"
  echo "$(md5sum < $O/$1.mjpeg | cut -d' ' -f1) $(stat -c %s $O/$1.mjpeg) $1"
}
enc in1080.nv12 nv12 1920 1080 60
enc in1080.i420 i420 1920 1080 30
enc in1080.yuy2 yuy2 1920 1080 30
enc in4k.nv12 nv12 3840 2160 10
