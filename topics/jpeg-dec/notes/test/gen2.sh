#!/bin/sh
# canonical (libjpeg via gst jpegenc) vectors: chroma sampling factors 1x1
cd /tmp/jt
rm -f img_*.jpg img_*.ref img_*.hw
g() { timeout 120 gst-launch-1.0 -q videotestsrc pattern=$4 num-buffers=${5:-1} ! video/x-raw,format=$1,width=${2%x*},height=${2#*x} ! jpegenc quality=$3 ! filesink location=$6; }
for s in 1920x1080 1921x1081 33x17 3840x2160 641x479; do
  for f in I420 Y42B Y444 GRAY8; do
    g $f $s 90 smpte 1 img_${f}_${s}.jpg
  done
done
for q in 20 50 75 100; do g Y42B 1920x1080 $q ball 1 img_Y42B_q${q}.jpg; done
# ffmpeg encoded 4:2:0 with DRI (canonical 2x2/1x1/1x1)
cp /tmp/jt/img_dri_420.jpg img_I420_dri_ffmpeg.jpg 2>/dev/null
timeout 120 ffmpeg -hide_banner -loglevel error -y -f lavfi -i testsrc2=size=1920x1080 -frames:v 1 -pix_fmt yuvj420p -threads 4 -slices 4 -q:v 3 img_I420_dri_ffmpeg.jpg
timeout 120 ffmpeg -hide_banner -loglevel error -y -f lavfi -i testsrc2=size=1920x1080 -frames:v 1 -pix_fmt yuvj420p -huffman default -q:v 5 img_I420_hdef_ffmpeg.jpg
# streams
g Y42B 1280x720 85 ball 60 s720_422.mjpeg
timeout 120 gst-launch-1.0 -q videotestsrc num-buffers=60 pattern=ball ! video/x-raw,format=Y42B,width=1280,height=720 ! jpegenc ! avimux ! filesink location=s720_422.avi
g Y42B 1280x720 85 smpte 10 b2.mjpeg
cat a.mjpeg b2.mjpeg a.mjpeg > reschange.mjpeg
for f in img_*.jpg; do timeout 60 ffmpeg -hide_banner -loglevel error -y -i $f -f rawvideo ${f%.jpg}.ref; done
echo gen2 done
