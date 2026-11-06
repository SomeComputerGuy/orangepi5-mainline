#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
#
# Board side: VEPU580 encodes with GStreamer v4l2codecs (v4l2sl*h26[45]enc on rockchip-venc),
# software decode with FFmpeg, PSNR against the source, dmesg check per case.
# usage: v8run.sh <csv> <label> <case> ...
#   case = name:codec:WxH:frames:rc     codec h264|h265, rc cqp | <kbps> (CBR)
# One CSV row per finished case; finished cases are skipped (resumable).
# Sources are scaled from ~/demo/bbb_sunflower_2160p_60fps_normal.mp4 (lanczos).
# Sources wider than 4096 are deleted after their case (disk space).
set -u
CSV=$1 LABEL=$2
shift 2
SRC=${SRC:-$HOME/hwenc-test/src8k}
WORK=${WORK:-$HOME/hwenc-test/venc8k}
DEMO=$HOME/demo/bbb_sunflower_2160p_60fps_normal.mp4
mkdir -p "$WORK" "$SRC"
[ -s "$CSV" ] || echo "label,name,codec,w,h,frames,rc,gst_rc,bytes,md5,dec_frames,dec_errs,psnr_y,psnr_left,psnr_right,enc_fps,dmesg_bad,kernel" > "$CSV"
dev_of() { for v in /dev/video*; do
	[ "$(cat /sys/class/video4linux/${v#/dev/}/name)" = "$1" ] && echo "$v"; done | head -1; }
elem_for() { gst-inspect-1.0 v4l2codecs 2>/dev/null | awk '{print $1}' | tr -d : |
	grep "^v4l2sl.*$2enc$" | while read -r e; do
		gst-inspect-1.0 "$e" | grep -q "Default: \"$1\"" && echo "$e"; done | head -1; }
RKV=$(dev_of rockchip-venc)
E_h265=$(elem_for "$RKV" h265) E_h264=$(elem_for "$RKV" h264)
echo "dev=$RKV h265=$E_h265 h264=$E_h264 kernel=$(uname -v)" >&2
KV=$(uname -r)-$(uname -v | awk '{print $1}')
psnr() { # dec src w h [crop] -> PSNR-Y
	local f=""
	[ -n "${5:-}" ] && f="$5,"
	ffmpeg -nostdin -v info -f rawvideo -pix_fmt nv12 -s "${3}x$4" -i "$1" \
		-f rawvideo -pix_fmt nv12 -s "${3}x$4" -i "$2" \
		-lavfi "[0:v]${f}null[a];[1:v]${f}null[b];[a][b]psnr" -f null - 2>&1 |
		awk '/PSNR y:/ { for (i = 1; i <= NF; i++) if ($i ~ /^y:/) y = substr($i, 3) } END { printf "%s", y }'
}
for c in "$@"; do
	IFS=: read -r name codec size n rc <<< "$c"
	key="$LABEL,$name,"
	grep -q "^$key" "$CSV" && continue
	w=${size%x*} h=${size#*x}
	eval "e=\${E_${codec}:-}"
	[ -n "$e" ] || { echo "no element for $c" >&2; continue; }
	avail=$(df --output=avail -k "$SRC" | tail -1)
	[ "$avail" -gt 4000000 ] || { echo "no disk space for $c ($avail kB free)" >&2; continue; }
	s=$SRC/$size-$n.nv12
	if [ ! -s "$s" ]; then
		echo "making source $size x $n" >&2
		timeout 1800 ffmpeg -nostdin -v error -ss 120 -i "$DEMO" -frames:v "$n" \
			-vf "scale=$w:$h:flags=lanczos,format=nv12" -f rawvideo "$s.tmp" && mv "$s.tmp" "$s"
	fi
	[ -s "$s" ] || { echo "no source $c" >&2; continue; }
	if [ "$codec" = h264 ]; then parse=h264parse; else parse=h265parse; fi
	if [ "$rc" = cqp ]; then props="rate-control=cqp qp-i=26 qp-p=28"; else props="rate-control=cbr bitrate=$rc"; fi
	o=$WORK/x.$codec
	rm -f "$o"
	cat "$s" > /dev/null
	echo "v8k-mark $LABEL $name" | sudo tee /dev/kmsg > /dev/null
	t0=$(date +%s.%N)
	timeout 900 gst-launch-1.0 -q filesrc location="$s" ! \
		rawvideoparse width="$w" height="$h" format=nv12 framerate=30/1 ! \
		$e $props key-int-max=60 ! $parse ! filesink location="$o" > "$WORK/gst-$name.log" 2>&1
	st=$?
	t1=$(date +%s.%N)
	sleep 1
	sudo dmesg | awk -v m="v8k-mark $LABEL $name" 'index($0, m) { p = 1; next } p' |
		grep -iE 'iommu|fault|time.?out|watchdog|rkvenc|venc|vepu|BUG|WARNING|Oops' > "$WORK/dmesg-$LABEL-$name.txt"
	bad=$(grep -c . "$WORK/dmesg-$LABEL-$name.txt")
	bytes=0 md5=- nf=0 errs=-1 py=0 pl=NA pr=NA efps=0
	if [ $st = 0 ] && [ -s "$o" ]; then
		bytes=$(stat -c %s "$o")
		md5=$(md5sum "$o" | cut -c1-32)
		efps=$(echo "$n / ($t1 - $t0)" | bc -l | xargs printf "%.2f")
		ffmpeg -nostdin -v error -i "$o" -f rawvideo -pix_fmt nv12 -y "$WORK/dec.nv12" 2> "$WORK/ffdec-$LABEL-$name.txt"
		errs=$(grep -c . "$WORK/ffdec-$LABEL-$name.txt")
		nf=$(( $(stat -c %s "$WORK/dec.nv12" 2>/dev/null || echo 0) / (w * h * 3 / 2) ))
		if [ "$nf" = "$n" ]; then
			py=$(psnr "$WORK/dec.nv12" "$s" "$w" "$h")
			if [ "$w" -gt 4096 ]; then
				pl=$(psnr "$WORK/dec.nv12" "$s" "$w" "$h" "crop=4096:$h:0:0")
				pr=$(psnr "$WORK/dec.nv12" "$s" "$w" "$h" "crop=$((w - 4096)):$h:4096:0")
			fi
		fi
		rm -f "$WORK/dec.nv12"
	else
		tail -5 "$WORK/gst-$name.log" >&2
		echo "gst failed $c (rc $st)" >&2
	fi
	[ "$w" -gt 4096 ] && rm -f "$s"
	echo "$key$codec,$w,$h,$n,$rc,$st,$bytes,$md5,$nf,$errs,$py,$pl,$pr,$efps,$bad,$KV" | tee -a "$CSV"
done
