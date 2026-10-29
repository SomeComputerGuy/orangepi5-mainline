#!/bin/sh
# On-board test sequence for rockchip-venc (safe tests only: no fault
# provocation, no module unload). Run as a normal user with access to
# /dev/video* and /dev/media*; needs ffmpeg and v4l2-compliance.
#
# usage: run-tests.sh <dir with rkvenc-enc> <work dir>
set -u
BIN=${1:-.}/rkvenc-enc
WD=${2:-/tmp/rkvenc}
mkdir -p "$WD"
cd "$WD" || exit 1
LOG=$WD/results.txt
: > "$LOG"

say() { echo "$*" | tee -a "$LOG"; }

gen() { # w h frames name
	[ -f "$4" ] || ffmpeg -loglevel error -f lavfi -i testsrc2=size=$1x$2:rate=30 \
		-frames:v $3 -pix_fmt nv12 -f rawvideo "$4"
}

psnr() { # w h raw h264 (decodes, then compares frame by frame)
	$(dirname "$BIN")/psnr.sh "$1" "$2" "$3" "$4" | sed 's/ min:.*//'
}

decode_check() { # h264 -> number of decode errors
	ffmpeg -v error -i "$1" -f null - 2>&1 | wc -l
}

irqs() { grep -E 'fdbd0000|fdbe0000' /proc/interrupts | awk '{s=0; for(i=2;i<=9;i++) s+=$i; printf "%s=%d ", $NF, s}'; }

gen 1920 1080 300 in1080.nv12
gen 3840 2160 60 in2160.nv12

say "== v4l2-compliance"
DEV=$(for v in /dev/video*; do v4l2-ctl -d $v -D 2>/dev/null | grep -q "Driver name.*rockchip-venc" && echo $v; done | head -1)
v4l2-compliance -d "$DEV" 2>&1 | tail -3 | tee -a "$LOG"

for res in 1080 2160; do
	[ $res = 1080 ] && W=1920 H=1080 N=300 || W=3840 H=2160 N=60
	for gop in 1 30; do
		for qp in 22 27 32 37; do
			out=q${qp}_g${gop}_${res}.h264
			r=$($BIN -i in$res.nv12 -o $out -w $W -h $H -n $N -g $gop -q $qp 2>&1 | tail -1)
			say "fixqp res=$res gop=$gop qp=$qp: $r | decode-errors=$(decode_check $out) psnr=$(psnr $W $H in$res.nv12 $out)"
		done
	done
	for br in 2000000 8000000 20000000; do
		out=cbr${br}_${res}.h264
		r=$($BIN -i in$res.nv12 -o $out -w $W -h $H -n $N -g 30 -b $br 2>&1 | tail -1)
		say "cbr res=$res target=$br: $r | decode-errors=$(decode_check $out) psnr=$(psnr $W $H in$res.nv12 $out)"
	done
done

say "== profiles (1080p, GOP 30, QP 27)"
for p in 66 77 100; do
	out=prof$p.h264
	r=$($BIN -i in1080.nv12 -o $out -w 1920 -h 1080 -n 120 -g 30 -q 27 -p $p 2>&1 | tail -1)
	say "profile $p: $r | decode-errors=$(decode_check $out) $(ffprobe -v error -show_entries stream=profile -of csv=p=0 $out)"
done
out=cavlc.h264
r=$($BIN -i in1080.nv12 -o $out -w 1920 -h 1080 -n 120 -g 30 -q 27 -c 2>&1 | tail -1)
say "high cavlc: $r | decode-errors=$(decode_check $out)"

say "== two parallel 4K streams"
say "irqs before: $(irqs)"
$BIN -i in2160.nv12 -o par0.h264 -w 3840 -h 2160 -g 30 -q 27 > par0.log 2>&1 &
$BIN -i in2160.nv12 -o par1.h264 -w 3840 -h 2160 -g 30 -q 27 > par1.log 2>&1 &
wait
say "stream0: $(tail -1 par0.log)"
say "stream1: $(tail -1 par1.log)"
say "irqs after: $(irqs)"
say "decode-errors: $(decode_check par0.h264) $(decode_check par1.h264)"

say "== runtime PM"
sleep 2
for d in /sys/bus/platform/devices/fdbd0000.video-codec /sys/bus/platform/devices/fdbe0000.video-codec; do
	say "$d: $(cat $d/power/runtime_status)"
done
say "== dmesg"
dmesg | grep -iE 'venc|vepu|fdbd|fdbe|iommu' | tail -20 | tee -a "$LOG"
