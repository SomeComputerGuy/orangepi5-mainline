#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Verification after booting with updates/opi5-codec-quality (run on the board from ~/cq, idle board).
cd ~/cq; W=~/codecsweep/work; O=after-reboot.txt; : > $O
s() { echo "== $*" | tee -a $O; }
s modules; for m in rockchip_jpegd hantro_vpu rockchip_vdec; do modinfo -n $m; done | tee -a $O
s "rkjpegd: v4l2-compliance -s -f (used to hang in DQBUF)"
timeout 300 v4l2-compliance -d /dev/video1 -s -f 2>&1 | grep -E '^Total|fail' | tee -a $O
s "rkjpegd: 640x360 VEPU121 JPEGs vs ffmpeg decode (expect ~63 dB, unchanged)"
gst-launch-1.0 -q filesrc location=$W/jpeg_640x360.mjpeg ! jpegparse ! v4l2jpegdec ! videoconvert ! video/x-raw,format=I420 ! identity eos-after=61 ! filesink location=j.yuv
ffmpeg -nostdin -v error -y -f mjpeg -i $W/jpeg_640x360.mjpeg -frames:v 60 -f rawvideo -pix_fmt yuv420p jf.yuv
./vqcmp.sh psnr j.yuv jf.yuv 640x360 60 | grep PSNR | tee -a $O
s "hantro: MPEG-2 conformance (field pictures used to fail)"; ./mpeg2-conf.sh 2>&1 | tee -a $O
s "hantro: H.264/VP8/MPEG-2 sweep clips"
for f in ref_h264_1280x720_30.mkv:h264parse:v4l2slh264dec ref_vp8_1280x720_30.webm::v4l2slvp8dec ref_mpeg2_1280x720_30.mkv:mpegvideoparse:v4l2slmpeg2dec; do
	IFS=: read c p e <<<"$f"
	gst-launch-1.0 -q filesrc location=$W/$c ! matroskademux ! ${p:-identity} ! $e ! videoconvert ! video/x-raw,format=I420 ! identity eos-after=31 ! filesink location=h.yuv
	ffmpeg -nostdin -v error -y -i $W/$c -frames:v 30 -f rawvideo -pix_fmt yuv420p f.yuv
	echo "$c $(./vqcmp.sh exact h.yuv f.yuv 1280x720 30 | cut -c1-16) $(./vqcmp.sh psnr h.yuv f.yuv 1280x720 30 | grep -oE 'average:[0-9.inf]+')" | tee -a $O
done
sudo dmesg | grep -cE 'stall request|Oops|BUG:' | sed 's/^/iommu stall\/oops lines: /' | tee -a $O
