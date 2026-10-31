#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# MPEG-2 conformance (ISO/IEC 13818-4 vectors from fluster MPEG2_VIDEO-MAIN, which ships no
# reference checksums): hardware (v4l2slmpeg2dec) vs FFmpeg per vector - frame counts, bit-exact
# frames, PSNR. MPEG-2 only requires IEEE 1180 IDCT accuracy, so decoders are not bit-exact.
# FFmpeg runs with -fps_mode passthrough: its default CFR output duplicates frames for 3:2 pulldown
# (repeat_first_field), which GStreamer signals with buffer flags instead.
R=${R:-$HOME/.local/share/fluster/resources/MPEG2_VIDEO-MAIN}; V=$(readlink -f $(dirname $0))/vqcmp.sh; T=$(mktemp -d)
trap 'rm -rf $T' EXIT
for d in $R/*/; do f=$(ls $d | head -1); n=$(basename $d)
	wh=$(ffprobe -v error -show_entries stream=width,height -of csv=s=x:p=0 $d/$f | head -1 | sed 's/x$//')
	timeout 120 gst-launch-1.0 -q filesrc location=$d/$f ! mpegvideoparse ! v4l2slmpeg2dec ! videoconvert ! video/x-raw,format=I420 ! filesink location=$T/hw.yuv >/dev/null 2>&1; rc=$?
	ffmpeg -nostdin -v fatal -y -i $d/$f -fps_mode passthrough -f rawvideo -pix_fmt yuv420p $T/sw.yuv
	ex=$($V exact $T/hw.yuv $T/sw.yuv $wh 2>&1 | grep -oE 'bitexact=[0-9]+/[0-9]+ \(test frames [0-9]+, ref frames [0-9]+\)')
	ps=$(cd $T && $V psnr $T/hw.yuv $T/sw.yuv $wh 2>&1 | grep -oE 'average:[0-9.inf]+ min:[0-9.inf]+')
	printf '%-22s %-9s rc=%-3s %-44s %s\n' $n $wh $rc "$ex" "$ps"
done
