#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
#
# Board side: CBR encodes with GStreamer v4l2codecs (VEPU580 H.265/H.264, Hantro H1 H.264).
# usage: hrun.sh <csv> <label> <case> ...    case = src:codec:enc:kbps
#   src bbb1080|yacht1080|bbb2160|jelly2160, codec h265|h264, enc rkv|h1
# One CSV row per finished case; finished cases are skipped (resumable).
# TRACE=1 also enables the pr_debug trace of v4l2-enc-cbr.c and keeps dmesg per case.
# Missing sources are made from ~/demo like hwenc-gst/tests/run-board-tests.sh does.
set -u
CSV=$1 LABEL=$2
shift 2
SRC=${SRC:-$HOME/hwenc-test/src}
WORK=${WORK:-$HOME/hwenc-test/hevcrc}
mkdir -p "$WORK" "$SRC"
[ -s "$CSV" ] || echo "label,src,codec,enc,value,kbps,err_pct,gop_err_pct,psnr_y,ssim,frames,enc_fps,gop,i0_bytes,spike,idr_ratio_max,max1s_kbps,kernel" > "$CSV"
info() { case $1 in bbb1080|yacht1080) echo "1920 1080 60 300";; *) echo "3840 2160 30 120";; esac; }
mk_src() { # name input start-seconds
	read -r w h fps n <<< "$(info "$1")"
	[ -s "$SRC/$1.nv12" ] && return 0
	echo "making source $1" >&2
	timeout 1200 ffmpeg -nostdin -v error -ss "$3" -i "$2" -frames:v "$n" \
		-vf "scale=$w:$h:flags=lanczos,format=nv12" -f rawvideo "$SRC/$1.nv12.tmp" &&
		mv "$SRC/$1.nv12.tmp" "$SRC/$1.nv12"
}
mk_src bbb1080 ~/demo/bbb_sunflower_2160p_60fps_normal.mp4 120
mk_src yacht1080 ~/demo/yacht_h264_1080p120.mp4 0
mk_src bbb2160 ~/demo/bbb_sunflower_2160p_60fps_normal.mp4 120
mk_src jelly2160 ~/demo/jellyfish-120-mbps-4k-uhd-h264.mkv 10
dev_of() { for v in /dev/video*; do
	[ "$(cat /sys/class/video4linux/${v#/dev/}/name)" = "$1" ] && echo "$v"; done | head -1; }
elem_for() { gst-inspect-1.0 v4l2codecs 2>/dev/null | awk '{print $1}' | tr -d : |
	grep "^v4l2sl.*$2enc$" | while read -r e; do
		gst-inspect-1.0 "$e" | grep -q "Default: \"$1\"" && echo "$e"; done | head -1; }
RKV=$(dev_of rockchip-venc) H1=$(dev_of rockchip,rk3588-vpu121-enc)
E_rkv_h265=$(elem_for "$RKV" h265) E_rkv_h264=$(elem_for "$RKV" h264) E_h1_h264=$(elem_for "$H1" h264)
echo "rkv265=$E_rkv_h265 rkv264=$E_rkv_h264 h1=$E_h1_h264 kernel=$(uname -v)" >&2
KV=$(uname -r)-$(uname -v | awk '{print $1}')
DD=/sys/kernel/debug/dynamic_debug/control
for c in "$@"; do
	IFS=: read -r s codec enc val <<< "$c"
	key="$LABEL,$s,$codec,$enc,$val,"
	grep -q "^$key" "$CSV" && continue
	read -r w h fps n <<< "$(info "$s")"
	eval "e=\${E_${enc}_${codec}:-}"
	[ -n "$e" ] || { echo "no element for $c" >&2; continue; }
	[ -s "$SRC/$s.nv12" ] || { echo "no source $s" >&2; continue; }
	if [ "$codec" = h264 ]; then parse=h264parse; else parse=h265parse; fi
	o=$WORK/x.$codec
	tag=$LABEL-$s-$codec-$enc-$val
	cat "$SRC/$s.nv12" > /dev/null
	if [ "${TRACE:-0}" = 1 ]; then
		sudo dmesg -C
		echo "file v4l2-enc-cbr.c +p" | sudo tee $DD > /dev/null
	fi
	t0=$(date +%s.%N)
	timeout 600 gst-launch-1.0 -q filesrc location="$SRC/$s.nv12" ! \
		rawvideoparse width="$w" height="$h" format=nv12 framerate="$fps/1" ! \
		$e bitrate=$val ! $parse ! filesink location="$o" > "$WORK/gst.log" 2>&1
	st=$?
	t1=$(date +%s.%N)
	if [ "${TRACE:-0}" = 1 ]; then
		echo "file v4l2-enc-cbr.c -p" | sudo tee $DD > /dev/null
		sudo dmesg > "$WORK/trace-$tag.txt"
	fi
	[ $st = 0 ] || { echo "gst failed $c" >&2; tail -3 "$WORK/gst.log" >&2; continue; }
	efps=$(echo "$n / ($t1 - $t0)" | bc -l | xargs printf "%.1f")
	kb=$(echo "$(stat -c %s "$o") * 8 * $fps / $n / 1000" | bc -l | xargs printf "%.0f")
	err=$(echo "($kb - $val) * 100 / $val" | bc -l | xargs printf "%.1f")
	ffprobe -v error -show_entries packet=size,flags -of csv=p=0 "$o" > "$WORK/sizes-$tag.txt"
	# whole-GOP error, GOP, first-P-after-IDR spike, IDR size ratio, max 1 s rate
	st=$(awk -F, -v f="$fps" -v val="$val" '{ s[NR] = $1; k[NR] = ($2 ~ /K/) } END {
		ni = 0; for (i = 1; i <= NR; i++) if (k[i]) idr[++ni] = i
		g = ni > 1 ? idr[2] - idr[1] : NR; m = int(NR / g) * g; if (m < 1) m = NR
		t = 0; for (i = 1; i <= m; i++) t += s[i]
		gerr = (t * 8 * f / m / 1000 - val) * 100 / val
		sp = 0; ir = 0
		for (j = 2; j <= ni; j++) { x = idr[j]; c = 0
			for (i = x - 10; i < x; i++) if (i >= 1 && !k[i]) b[++c] = s[i]
			for (i = 2; i <= c; i++) { v = b[i]; for (j2 = i - 1; j2 >= 1 && b[j2] > v; j2--) b[j2 + 1] = b[j2]; b[j2 + 1] = v }
			if (c && x + 1 <= NR) { med = (c % 2) ? b[(c + 1) / 2] : (b[c / 2] + b[c / 2 + 1]) / 2
				r = s[x + 1] / med; if (r > sp) sp = r }
			delete b
			r = s[x] / s[idr[j - 1]]; if (r > ir) ir = r }
		mx = 0; for (i = 1; i + f - 1 <= NR; i++) { t = 0; for (j = i; j < i + f; j++) t += s[j]; if (t > mx) mx = t }
		printf "%.1f,%d,%d,%.2f,%.2f,%.0f", gerr, g, s[1], sp, ir, mx * 8 / 1000 }' "$WORK/sizes-$tag.txt")
	IFS=, read -r gerr gop i0 spike iratio mx <<< "$st"
	ffmpeg -nostdin -v error -i "$o" -f rawvideo -pix_fmt nv12 -y "$WORK/dec.nv12"
	q=$(ffmpeg -nostdin -v info -f rawvideo -pix_fmt nv12 -s "${w}x$h" -r "$fps" -i "$WORK/dec.nv12" \
		-f rawvideo -pix_fmt nv12 -s "${w}x$h" -r "$fps" -i "$SRC/$s.nv12" \
		-lavfi "[0:v]split[a0][a1];[1:v]split[b0][b1];[a0][b0]psnr;[a1][b1]ssim" -f null - 2>&1 |
		awk '/PSNR y:/ { for (i = 1; i <= NF; i++) if ($i ~ /^y:/) y = substr($i, 3) }
		     /SSIM Y:/ { for (i = 1; i <= NF; i++) if ($i ~ /^All:/) s = substr($i, 5) }
		     END { printf "%.3f,%.5f", y, s }')
	nf=$(( $(stat -c %s "$WORK/dec.nv12") / (w * h * 3 / 2) ))
	rm -f "$WORK/dec.nv12"
	echo "$key$kb,$err,$gerr,$q,$nf,$efps,$gop,$i0,$spike,$iratio,$mx,$KV" | tee -a "$CSV"
done
