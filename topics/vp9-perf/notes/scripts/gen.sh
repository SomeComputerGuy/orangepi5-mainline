#!/bin/sh
# Generate the VP9 benchmark clips (libvpx, realtime) in the current directory.
E="-deadline realtime -cpu-used 8 -row-mt 1 -threads 8 -tile-columns 2 -frame-parallel 0 -lag-in-frames 0 -error-resilient 0"
enc() { out=$1; shift; [ -s $out ] || nice -n 19 ffmpeg -hide_banner -loglevel error -y "$@" $out; }
enc 4k8.webm   -f lavfi -i testsrc2=size=3840x2160:rate=60 -frames:v 600 -pix_fmt yuv420p -c:v libvpx-vp9 $E -b:v 20M
enc 4k10.webm  -f lavfi -i testsrc2=size=3840x2160:rate=60 -frames:v 600 -pix_fmt yuv420p10le -c:v libvpx-vp9 -profile:v 2 $E -b:v 20M
enc 1080p.webm -f lavfi -i testsrc2=size=1920x1080:rate=60 -frames:v 1200 -pix_fmt yuv420p -c:v libvpx-vp9 $E -b:v 8M
enc 4k10hb.webm -f lavfi -i "mandelbrot=size=3840x2160:rate=60,noise=alls=12:allf=t" -frames:v 300 -pix_fmt yuv420p10le -c:v libvpx-vp9 -profile:v 2 $E -b:v 60M
ls -la *.webm
