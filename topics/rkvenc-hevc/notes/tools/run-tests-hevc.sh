#!/bin/sh
# On-board test sequence for rockchip-venc HEVC (safe tests only: no fault
# provocation, no module unload). Needs ffmpeg/ffprobe and v4l2-compliance.
#
# usage: run-tests-hevc.sh <dir with rkvenc-enc and psnr.sh> <work dir>
set -u
BIN=${1:-.}/rkvenc-enc
PSNR=$(dirname "$BIN")/psnr.sh
WD=${2:-/tmp/rkvenc-hevc}
mkdir -p "$WD" /tmp/rkvenc
cd "$WD" || exit 1
LOG=$WD/results.txt
: > "$LOG"

say() { echo "$*" | tee -a "$LOG"; }

gen() { # w h frames name
	[ -f "$4" ] || ffmpeg -loglevel error -f lavfi -i testsrc2=size=$1x$2:rate=30 \
		-frames:v $3 -pix_fmt nv12 -f rawvideo "$4"
}

psnr() { "$PSNR" "$1" "$2" "$3" "$4" | sed 's/ min:.*//'; }

# Decoder messages (errors and warnings): 0 expected
decode_check() { ffmpeg -v warning -i "$1" -f null - 2>&1 | wc -l; }

frames_of() { ffprobe -v error -count_frames -select_streams v:0 \
	-show_entries stream=nb_read_frames,profile,width,height -of csv=p=0 "$1"; }

enc() { # name args...: encodes, then checks decode, frame count and PSNR
	name=$1; shift
	r=$($BIN -e hevc -o "$name" "$@" 2>&1)
	st=$?
	fb=$(echo "$r" | grep -o 'feedback errors: [0-9]*')
	say "$name: rc=$st $(echo "$r" | grep encoded) | $fb | decode-msgs=$(decode_check "$name") probe=$(frames_of "$name") psnr=$(psnr $W $H $IN "$name")"
	echo "$r" | grep -E 'error|unexpected|timeout' | head -3 | tee -a "$LOG"
}

irqs() { grep -E 'fdbd0000|fdbe0000' /proc/interrupts | awk '{s=0; for(i=2;i<=9;i++) s+=$i; printf "%s=%d ", $NF, s}'; }

gen 1920 1080 300 in1080.nv12
gen 3840 2160 60 in2160.nv12
gen 1918 1078 60 in1918.nv12
gen 352 288 60 incif.nv12

DEV=$(for v in /dev/video*; do v4l2-ctl -d $v -D 2>/dev/null | grep -q "Driver name.*rockchip-venc" && echo $v; done | head -1)
say "== device $DEV"
v4l2-ctl -d "$DEV" --list-formats 2>&1 | grep -E "S265|S264" | tee -a "$LOG"
say "== v4l2-compliance"
v4l2-compliance -d "$DEV" 2>&1 | tail -3 | tee -a "$LOG"

say "== H.264 regression (shared code changed)"
W=1920 H=1080 IN=in1080.nv12
r=$($BIN -i $IN -o h264_q27.h264 -w $W -h $H -n 60 -g 30 -q 27 2>&1 | tail -1)
say "h264 1080p gop30 qp27: $r | decode-msgs=$(decode_check h264_q27.h264) psnr=$(psnr $W $H $IN h264_q27.h264)"

say "== HEVC: first frames, verbose (I, then the first P frame)"
W=1920 H=1080 IN=in1080.nv12
$BIN -e hevc -i $IN -o first.h265 -w $W -h $H -n 3 -g 30 -q 27 -v 2>&1 | tee -a "$LOG"
say "decode-msgs=$(decode_check first.h265) probe=$(frames_of first.h265)"

say "== HEVC fixed QP"
for res in 1080 2160; do
	[ $res = 1080 ] && W=1920 H=1080 N=300 || W=3840 H=2160 N=60
	IN=in$res.nv12
	for gop in 1 30; do
		for qp in 22 27 32 37; do
			enc q${qp}_g${gop}_${res}.h265 -i $IN -w $W -h $H -n $N -g $gop -q $qp
		done
	done
done

say "== HEVC tools (1080p GOP 30 QP 27)"
W=1920 H=1080 IN=in1080.nv12
enc tmvp.h265 -i $IN -w $W -h $H -n 120 -g 30 -q 27 -t
enc nosao.h265 -i $IN -w $W -h $H -n 120 -g 30 -q 27 -S
enc ltr.h265 -i $IN -w $W -h $H -n 120 -g 30 -q 27 -L
enc gop10.h265 -i $IN -w $W -h $H -n 60 -g 10 -q 27
enc cq50.h265 -i $IN -w $W -h $H -n 120 -g 30 -Q 50

say "== HEVC sizes (conformance window, small picture)"
W=1918 H=1078 IN=in1918.nv12
enc odd.h265 -i $IN -w $W -h $H -n 60 -g 30 -q 27
W=352 H=288 IN=incif.nv12
enc cif.h265 -i $IN -w $W -h $H -n 60 -g 30 -q 27

say "== HEVC CBR (300 frames 1080p, GOP 30)"
W=1920 H=1080 IN=in1080.nv12
for br in 2000000 4000000 8000000 20000000; do
	enc cbr$br.h265 -i $IN -w $W -h $H -n 300 -g 30 -b $br
done

say "== two parallel 4K HEVC streams"
W=3840 H=2160 IN=in2160.nv12
say "irqs before: $(irqs)"
$BIN -e hevc -i $IN -o par0.h265 -w $W -h $H -g 30 -q 27 > par0.log 2>&1 &
$BIN -e hevc -i $IN -o par1.h265 -w $W -h $H -g 30 -q 27 > par1.log 2>&1 &
wait
say "stream0: $(grep encoded par0.log)"
say "stream1: $(grep encoded par1.log)"
say "irqs after: $(irqs)"
say "decode-msgs: $(decode_check par0.h265) $(decode_check par1.h265); cmp: $(cmp par0.h265 par1.h265 >/dev/null && echo identical || echo differ)"

say "== runtime PM"
sleep 2
for d in /sys/bus/platform/devices/fdbd0000.video-codec /sys/bus/platform/devices/fdbe0000.video-codec; do
	say "$d: $(cat $d/power/runtime_status)"
done
say "== dmesg"
dmesg | grep -iE 'rkvenc|venc|iommu|fdbd|fdbe' | tail -20 | tee -a "$LOG"
