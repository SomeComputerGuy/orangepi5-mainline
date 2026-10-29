#!/bin/sh
# Generate JPEG/MJPEG test vectors and ffmpeg reference decodes in /tmp/jt
set -e
cd /tmp/jt
F="timeout 120 ffmpeg -hide_banner -loglevel error -y"
src() { echo "testsrc2=size=$1:rate=30"; }

for s in 1920x1080 1921x1081 33x17 3840x2160 640x480; do
  for p in yuvj420p yuvj422p yuvj444p gray; do
    $F -f lavfi -i "$(src $s)" -frames:v 1 -pix_fmt $p -q:v 2 img_${p}_${s}.jpg
  done
done
# default (Annex K style) huffman tables, and quality variety
for q in 1 5 15 31; do
  $F -f lavfi -i "$(src 1920x1080)" -frames:v 1 -pix_fmt yuvj420p -huffman default -q:v $q img_hdef_q${q}.jpg
done
# restart intervals: ffmpeg's mjpeg encoder emits DRI with slice threading
$F -f lavfi -i "$(src 1920x1080)" -frames:v 1 -pix_fmt yuvj420p -threads 4 -slices 4 -q:v 3 img_dri_420.jpg
$F -f lavfi -i "$(src 1921x1081)" -frames:v 1 -pix_fmt yuvj422p -threads 4 -slices 4 -q:v 3 img_dri_422.jpg
# MJPEG streams
$F -f lavfi -i "$(src 1920x1080)" -frames:v 300 -pix_fmt yuvj420p -q:v 3 -f mjpeg s1080.mjpeg
$F -f lavfi -i "$(src 3840x2160)" -frames:v 120 -pix_fmt yuvj420p -q:v 3 -f mjpeg s2160.mjpeg
$F -f lavfi -i "$(src 1280x720)" -frames:v 60 -pix_fmt yuvj422p -q:v 3 -c:v mjpeg s720.avi
# resolution change mid-stream
$F -f lavfi -i "$(src 640x480)" -frames:v 10 -pix_fmt yuvj420p -f mjpeg a.mjpeg
$F -f lavfi -i "$(src 1280x720)" -frames:v 10 -pix_fmt yuvj422p -f mjpeg b.mjpeg
cat a.mjpeg b.mjpeg a.mjpeg > reschange.mjpeg
# corrupt inputs
head -c 30000 img_yuvj420p_1920x1080.jpg > trunc.jpg
python3 - <<'EOF'
import random
d = bytearray(open('img_yuvj420p_1920x1080.jpg','rb').read())
random.seed(1)
for i in range(400):
    j = random.randrange(2000, len(d) - 10)
    d[j] = random.randrange(256)
open('corrupt.jpg','wb').write(d)
open('garbage.jpg','wb').write(bytes(random.randrange(256) for _ in range(50000)))
EOF
# references: ffmpeg software decode in native planar layout
for f in img_*.jpg; do
  $F -i $f -f rawvideo ${f%.jpg}.ref
done
echo gen done
