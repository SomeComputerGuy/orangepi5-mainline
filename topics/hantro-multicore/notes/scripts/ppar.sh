#!/bin/sh
# 4 (or $1) parallel encodes of the 60-frame 1080p NV12 input; each output must match the single-core reference
D=/var/tmp/hmc; O=/dev/shm/hmc/pp; mkdir -p $O; N=${1:-4}
for i in $(seq $N); do
  timeout 60 gst-launch-1.0 -q filesrc location=$D/in1080.nv12 blocksize=3110400 ! rawvideoparse format=nv12 width=1920 height=1080 framerate=30/1 ! v4l2jpegenc ! filesink location=$O/s$i.mjpeg &
done; wait
md5sum $O/*.mjpeg | awk '{print $1}' | sort | uniq -c
rm -rf $O
