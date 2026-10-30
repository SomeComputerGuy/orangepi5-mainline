#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# vqcmp.sh - timestamp-free PSNR / bit-exact comparison of video against a raw reference.
#
# Every input is first decoded to a raw file (no container timestamps, no frame-rate
# conversion), then compared frame by frame by index.  This avoids the two traps of
# "ffmpeg -i a.mkv -i b.nv12 -lavfi psnr": framesync pairing frames by (rounded) PTS,
# and raw elementary streams whose demuxer is not auto-detected from a ".es" suffix.
#
#   vqcmp.sh psnr  <test> <ref.nv12|ref-video> <WxH> [frames]   per-frame stats -> ./<basename test>.psnr
#   vqcmp.sh exact <test.yuv> <ref.yuv> <WxH> [frames] [fmt]    count identical frames (fmt default yuv420p)
#   vqcmp.sh align <test> <ref> <WxH> [frames] [maxshift]       best frame offset by PSNR (shift test vs ref)
#
# <test>/<ref> may be raw (.nv12/.yuv/.i420, taken as nv12 / yuv420p) or anything ffmpeg can
# decode; raw H.264/HEVC elementary streams (.es/.264/.h264/.265/.hevc) are probed by content.
set -e
mode=$1; T=$2; R=$3; S=$4; N=${5:-0}
TMP=$(mktemp -d); trap 'rm -rf $TMP' EXIT
fmt_of() { case "$1" in *.nv12) echo nv12;; *.yuv|*.i420) echo yuv420p;; *) echo;; esac; }
demux_of() {   # raw elementary streams: pick the demuxer by content, not by suffix
	case "$1" in *.264|*.h264) echo "-f h264"; return;; *.265|*.hevc) echo "-f hevc"; return;; esac
	case "$1" in *.es|*.bit|*.bin)
		if ffprobe -v error -f hevc -show_entries stream=codec_name -of csv=p=0 "$1" 2>/dev/null | grep -q hevc &&
		   [ "$(ffprobe -v error -f hevc -count_frames -show_entries stream=nb_read_frames -of csv=p=0 "$1" 2>/dev/null)" -gt 0 ] 2>/dev/null
		then echo "-f hevc"; else echo "-f h264"; fi;; esac; }
toraw() {      # toraw <in> <out> <pixfmt>: decode every frame, in decode output order, no fps filter
	local f; f=$(fmt_of "$1")
	if [ -n "$f" ]; then
		[ "$f" = "$3" ] && { ln -s "$(readlink -f "$1")" "$2"; return; }
		ffmpeg -nostdin -v error -y -f rawvideo -pix_fmt $f -s $S -i "$1" -f rawvideo -pix_fmt $3 "$2"
	else
		ffmpeg -nostdin -v error -y $(demux_of "$1") -i "$1" -fps_mode passthrough -f rawvideo -pix_fmt $3 "$2"
	fi; }
fsize() { local w=${S%x*} h=${S#*x}; echo $(( w*h + 2*((w+1)/2)*((h+1)/2) )); }
nfr() { echo $(( $(stat -L -c %s "$1") / $(fsize) )); }
case $mode in
psnr|align)
	toraw "$T" $TMP/t.yuv yuv420p; toraw "$R" $TMP/r.yuv yuv420p
	nt=$(nfr $TMP/t.yuv); nr=$(nfr $TMP/r.yuv)
	[ $N -gt 0 ] || N=$(( nt < nr ? nt : nr ))
	cmp1() {   # cmp1 <shift> <statsfile>: test frame i vs ref frame i+shift
		local sh=$1 st=$2 ts=0 rs=0; [ $sh -ge 0 ] && rs=$sh || ts=$(( -sh ))
		ffmpeg -nostdin -hide_banner -nostats \
			-f rawvideo -pix_fmt yuv420p -s $S -r 1 -i $TMP/t.yuv -f rawvideo -pix_fmt yuv420p -s $S -r 1 -i $TMP/r.yuv \
			-lavfi "[0:v]trim=start_frame=$ts,setpts=N[a];[1:v]trim=start_frame=$rs,setpts=N[b];[a][b]psnr=stats_file=$st:shortest=1" \
			-frames:v $N -f null - 2>&1 | grep -oE 'PSNR y:.*' ; }
	if [ $mode = psnr ]; then
		echo "frames: test=$nt ref=$nr compared=$N"
		st=$(basename "$T").psnr; cmp1 0 "$st"
		awk '{split($7,y,":"); if (min=="" || y[2]<min) {min=y[2]; mi=NR}} END {print "worst luma frame", mi, min " dB  (per-frame: " FILENAME ")"}' "$st"
	else
		for sh in $(seq -${6:-3} ${6:-3}); do echo "shift $sh: $(cmp1 $sh /dev/null | grep -oE 'average:[0-9.inf]+')"; done
	fi;;
exact)
	f=${6:-yuv420p}; fs=$(fsize); [ $f = yuv420p -o $f = nv12 ] || { echo "only 4:2:0 formats"; exit 1; }
	nt=$(( $(stat -L -c %s "$T") / fs )); nr=$(( $(stat -L -c %s "$R") / fs ))
	[ $N -gt 0 ] || N=$(( nt < nr ? nt : nr ))
	ok=0; bad=""
	for i in $(seq 0 $((N-1))); do
		if cmp -s <(dd if="$T" bs=$fs skip=$i count=1 2>/dev/null) <(dd if="$R" bs=$fs skip=$i count=1 2>/dev/null)
		then ok=$((ok+1)); else bad="$bad $i"; fi
	done
	echo "bitexact=$ok/$N (test frames $nt, ref frames $nr)${bad:+ mismatching:$bad}";;
*) sed -n '3,15p' "$0"; exit 1;;
esac
