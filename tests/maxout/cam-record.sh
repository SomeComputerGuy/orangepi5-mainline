#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Live 4K webcam -> rkjpegd -> (RGA to NV12) -> VEPU580 HEVC at fixed QP -> 150-s .mkv segments on the SD card,
# with each closed segment decode-checked (rkvdec), copied SD -> Ultra Fit and back, and SD -> Extreme (sha256-verified).
#   cam-record.sh <secs> [qp=19]          logs: ~/camrec/
# Camera: the UVC device whose formats include MJPG 3840x2160 (Aluratek UHD), mode MJPEG 3840x2160@30.
SECS=${1:?secs}; QP=${2:-19}
D=$HOME/camrec; mkdir -p $D; SEG=/mnt/scratch-sd/cam; BACK=/mnt/scratch-sd/cam-back; USBD=/mnt/scratch-usb/cam; EXTD=/mnt/scratch-ext/cam
mkdir -p $SEG $BACK $USBD; mountpoint -q /mnt/scratch-ext && mkdir -p $EXTD || EXTD=""
source <(sed -n "/^dev_of/,/^demux_for/p" $HOME/maxout/maxout.sh)
CAM=""; for v in /dev/video*; do v4l2-ctl -d $v --list-formats-ext 2>/dev/null | grep -A40 MJPG | grep -q '3840x2160' && { CAM=$v; break; }; done
[ -n "$CAM" ] || { echo "no 4K MJPEG camera"; exit 1; }
RGA3=$(conv_for rk3588-rga3); RGA2=$(conv_for rk3288-rga); H265=$(dec_for h265); VENC=$(for d in /sys/class/video4linux/video*; do grep -q rockchip-venc $d/name && echo /dev/$(basename $d); done)
v4l2-ctl -d $CAM -c exposure_dynamic_framerate=0 2>/dev/null   # keep the full 30 fps (auto exposure may otherwise lower it)
PY="env PYTHONPATH=$HOME/npu-venv/lib/python3.14/site-packages python3"
ENC=$HOME/maxout/tools/rkvenc-enc   # with -s: dma-buf input over a unix socket (zero-copy)
SOCK=$D/enc.sock
END=$(( $(date +%s) + SECS ))
echo "# cam-record $(date '+%F %T') cam=$CAM ($(cat /sys/class/video4linux/$(basename $CAM)/name)) qp=$QP venc=$VENC" | tee $D/report.txt
# 1+2) one process (stream.py): camera MJPEG -> rkjpegd -> RGA3 (NV12, CAPTURE exported as dma-buf)
#   -> tee: fps counter | 15 fps -> RGA -> NPU (MobileNet, CPU cross-check) | dma-buf fd -> VEPU580 (zero CPU copy)
#   The encoder writes the HEVC elementary stream to ffmpeg, which timestamps it from the frame rate and cuts 150-s
#   Matroska segments (h265parse leaves PTS unset on a raw byte-stream, so matroskamux would drop it: FOLLOWUPS 10).
$PY $HOME/maxout/stream.py - none $D/cam.log --secs $SECS --npu $HOME/npu/models/mobilenet_v1_1.0_224_quant.tflite \
  $HOME/npu/models/imagenet_labels.txt --rga $RGA3 $RGA2 --enc-sock $SOCK \
  --source "v4l2src device=$CAM ! image/jpeg,width=3840,height=2160,framerate=30/1 ! jpegparse ! v4l2jpegdec ! $RGA3 capture-io-mode=dmabuf ! video/x-raw,format=NV12,width=3840,height=2160" \
  --enc "$ENC -e hevc -d $VENC -s $SOCK -o /dev/stdout -w 3840 -h 2160 -f 30 -g 60 -q $QP 2>>$D/enc.log | ffmpeg -v warning -fflags +genpts -f hevc -framerate 30 -i - -c copy -f segment -segment_time 150 -reset_timestamps 1 $SEG/seg%05d.mkv 2>>$D/mux.log" \
  > $D/cam.out 2>&1 &
CP=$!
# 3) segment checker/copier
verify() {  # frames decoded by rkvdec, end to end
  gst-launch-1.0 -v filesrc location=$1 ! matroskademux ! h265parse ! $H265 ! fpsdisplaysink text-overlay=false sync=false \
    video-sink=fakevideosink 2>&1 | grep -oE 'rendered: [0-9]+' | tail -1 | grep -oE '[0-9]+'; }
cpv() {  # cpv <src> <dst>: copy with fsync, verify sha256 read back with O_DIRECT
  dd if=$1 of=$2 bs=4M conv=fsync status=none 2>>$D/copy.err || { echo IOERR; return; }
  local a=$(sha256sum < $1 | cut -c1-64) b=$(dd if=$2 iflag=direct bs=4M status=none | sha256sum | cut -c1-64)
  [ "$a" = "$b" ] && echo ok || echo "CORRUPT $a $b"; }
done_list=$D/done.txt; : > $done_list
while [ $(date +%s) -lt $((END + 10)) ] || pgrep -f "segment_time 150" >/dev/null; do
  sleep 5
  segs=($(ls $SEG/seg*.mkv 2>/dev/null | sort)); n=${#segs[@]}
  last=$n; [ $(date +%s) -lt $((END + 10)) ] && last=$((n - 1))   # the newest one is still open while recording
  for ((k=0; k<last; k++)); do s=${segs[$k]}; grep -qx "$s" $done_list && continue; echo "$s" >> $done_list
    fr=$(verify $s); sz=$(stat -c %s $s)
    t0=$(date +%s.%N); r1=$(cpv $s $USBD/$(basename $s)); t1=$(date +%s.%N)
    r2=$(cpv $USBD/$(basename $s) $BACK/$(basename $s)); t2=$(date +%s.%N)
    r3=skipped; [ -n "$EXTD" ] && r3=$(cpv $s $EXTD/$(basename $s)); t3=$(date +%s.%N)
    echo "$(basename $s): $sz bytes, $fr frames decoded ($(awk -v f=${fr:-0} 'BEGIN{printf "%.1f s @30", f/30}')), $(awk -v b=$sz 'BEGIN{printf "%.1f Mbit/s", b*8/150/1e6}'), sd->usb $r1 $(awk -v a=$t0 -v b=$t1 -v n=$sz 'BEGIN{printf "%.0f MB/s", n/1048576/(b-a)}'), usb->sd $r2 $(awk -v a=$t1 -v b=$t2 -v n=$sz 'BEGIN{printf "%.0f MB/s", n/1048576/(b-a)}'), sd->ext $r3 $(awk -v a=$t2 -v b=$t3 -v n=$sz 'BEGIN{printf "%.0f MB/s", n/1048576/(b-a)}')" | tee -a $D/report.txt
    rm -f $BACK/$(basename $s)
  done
  [ $(date +%s) -ge $((END + 60)) ] && break
done
wait $CP; sleep 3
echo "camera: $(grep TOTAL $D/cam.log | cut -d' ' -f3-)" | tee -a $D/report.txt
echo "camera per-s fps: $(awk '$2=="SEC"{split($5,f,"="); n++; s+=f[2]} END{if(n)printf "mean %.1f over %d s", s/n, n}' $D/cam.log), encoder per-s fps: $(awk '$2=="SEC"{for(i=3;i<=NF;i++){split($i,kv,"="); if(kv[1]=="enc_fps"){s+=kv[2];n++}}} END{if(n)printf "mean %.1f", s/n}' $D/cam.log)" | tee -a $D/report.txt
echo "camera NPU: $(awk '$2=="SEC"{for(i=3;i<=NF;i++){split($i,kv,"="); if(kv[1]=="npu_inf/s"){s+=kv[2];n++}}} END{if(n)printf "%.1f inf/s", s/n}' $D/cam.log); $(grep -c ' CMP ' $D/cam.log) CPU cross-checks, see CMP lines in $D/cam.log" | tee -a $D/report.txt
echo "encoder: $(tail -2 $D/enc.log | tr '\n' ' ')" | tee -a $D/report.txt
# 4) quality sample: 30 camera frames, decoded MJPEG (reference) vs the same frames through the encoder at this QP
gst-launch-1.0 -q v4l2src device=$CAM num-buffers=30 ! image/jpeg,width=3840,height=2160,framerate=30/1 ! jpegparse ! v4l2jpegdec ! \
  $RGA3 ! video/x-raw,format=NV12,width=3840,height=2160 ! filesink location=$D/ref.nv12 2>/dev/null
$ENC -e hevc -d $VENC -i $D/ref.nv12 -o $D/q.hevc -w 3840 -h 2160 -n 30 -f 30 -g 60 -q $QP > /dev/null 2>&1
ffmpeg -v error -f rawvideo -pix_fmt nv12 -s 3840x2160 -i $D/ref.nv12 -i $D/q.hevc -lavfi psnr -f null - 2>&1 | tail -1 > $D/psnr.txt
ffmpeg -v info -f rawvideo -pix_fmt nv12 -s 3840x2160 -i $D/ref.nv12 -i $D/q.hevc -lavfi psnr -f null - 2>&1 | grep -oE 'PSNR .*' | tail -1 >> $D/psnr.txt
echo "quality QP$QP: $(tail -1 $D/psnr.txt), $(( $(stat -c %s $D/q.hevc) * 8 / 1000000 )) Mbit/s at 30 frames/1 s" | tee -a $D/report.txt
