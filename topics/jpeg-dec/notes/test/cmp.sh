#!/bin/sh
# Decode every img_*.jpg with the hardware and compare with ffmpeg's decode
cd /tmp/jt
DEV=$1
for f in img_*.jpg; do
  b=${f%.jpg}
  case $b in
    *Y42B*) pf=yuv422p ;;
    *Y444*) pf=yuv444p ;;
    *GRAY8*) pf=gray ;;
    *) pf=yuv420p ;;
  esac
  size=$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=s=x:p=0 $f)
  res=$(timeout 20 ./jdec -q -d $DEV -o $b.hw $f 2>&1 | tail -1)
  if cmp -s $b.hw $b.ref; then md5=identical; else md5=differs; fi
  psnr=$(timeout 60 ffmpeg -hide_banner -f rawvideo -pix_fmt $pf -s $size -i $b.hw \
         -f rawvideo -pix_fmt $pf -s $size -i $b.ref -lavfi "[0][1]psnr" -f null - 2>&1 |
         sed -n 's/.*PSNR \(.*\)$/\1/p')
  echo "$f | $size | $pf | $md5 | $psnr | $res"
done
