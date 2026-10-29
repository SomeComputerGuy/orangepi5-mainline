#!/bin/sh
# psnr.sh W H src.nv12 enc.h264 -> average PSNR (Y/U/V/avg) of decoded frames vs source
W=$1 H=$2 SRC=$3 ENC=$4
D=$(mktemp /tmp/rkvenc/dec.XXXXXX)
ffmpeg -v error -y -i "$ENC" -f rawvideo -pix_fmt nv12 "$D" || { echo decode-failed; exit 1; }
N=$(( $(stat -c %s "$D") / (W*H*3/2) ))
ffmpeg -hide_banner -f rawvideo -pix_fmt nv12 -s ${W}x$H -r 30 -i "$D" \
  -f rawvideo -pix_fmt nv12 -s ${W}x$H -r 30 -i "$SRC" \
  -lavfi "[1:v]trim=end_frame=$N[r];[0:v][r]psnr" -f null - 2>&1 | grep -o 'PSNR y:.*' | sed "s/^/frames=$N /"
rm -f "$D"
