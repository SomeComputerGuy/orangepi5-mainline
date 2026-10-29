#!/bin/sh
# Generate raw test inputs in /var/tmp/hmc (tmpfs-ish RAM copies go to /dev/shm)
set -e
D=/var/tmp/hmc; mkdir -p $D; cd $D
[ -f in1080.nv12 ] || ffmpeg -loglevel error -f lavfi -i testsrc2=size=1920x1080:rate=30 -frames:v 60 -pix_fmt nv12 -f rawvideo in1080.nv12
[ -f in1080.i420 ] || ffmpeg -loglevel error -f lavfi -i testsrc2=size=1920x1080:rate=30 -frames:v 30 -pix_fmt yuv420p -f rawvideo in1080.i420
[ -f in1080.yuy2 ] || ffmpeg -loglevel error -f lavfi -i testsrc2=size=1920x1080:rate=30 -frames:v 30 -pix_fmt yuyv422 -f rawvideo in1080.yuy2
[ -f in4k.nv12 ] || ffmpeg -loglevel error -f lavfi -i testsrc2=size=3840x2160:rate=30 -frames:v 10 -pix_fmt nv12 -f rawvideo in4k.nv12
# throughput input in RAM: 300 frames 1080p nv12 (~930MB is too big) -> 100 frames (311MB)
mkdir -p /dev/shm/hmc
[ -f /dev/shm/hmc/raw.nv12 ] || ffmpeg -loglevel error -f lavfi -i testsrc2=size=1920x1080:rate=30 -frames:v 100 -pix_fmt nv12 -f rawvideo /dev/shm/hmc/raw.nv12
ls -la $D /dev/shm/hmc
