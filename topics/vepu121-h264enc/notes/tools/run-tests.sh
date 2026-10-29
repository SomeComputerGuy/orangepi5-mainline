#!/bin/sh
# On-board tests for the VEPU121 H.264 stateless encoder.
# Usage: run-tests.sh <dir with v4l2-h264-slenc> <work dir>
# Only runs encodes/decodes, no module loading or fault injection.
# The RK3588 has a single H.264 encoder (VPU121 VEPU2): the parallel rows run
# several contexts on it, they are serialised by the mem2mem framework.
set -u
T=${1:-.}
D=${2:-/tmp/h264enc}
ENC=$T/v4l2-h264-slenc
N=${N:-60}
mkdir -p "$D"
cd "$D" || exit 1
log() { echo "== $*"; }

gen() { # w h name
	[ -f "$3.nv12" ] || ffmpeg -v error -f lavfi -i "testsrc2=size=$1x$2:rate=30" \
		-frames:v "$N" -pix_fmt nv12 -f rawvideo "$3.nv12"
}

check() { # file w h src -> prints decode errors, frames, PSNR
	errs=$(ffmpeg -v error -i "$1" -f null - 2>&1 | wc -l)
	frames=$(ffprobe -v error -count_frames -select_streams v:0 \
		-show_entries stream=nb_read_frames -of csv=p=0 "$1" 2>/dev/null)
	psnr=$(ffmpeg -v info -i "$1" -f rawvideo -pix_fmt nv12 -s "$2x$3" -i "$4" \
		-lavfi "[0:v]settb=1/30,setpts=N[a];[1:v]settb=1/30,setpts=N[b];[a][b]psnr" \
		-f null - 2>&1 | sed -n 's/.*PSNR y:\([0-9.inf]*\).*average:\([0-9.inf]*\).*/y=\1 avg=\2/p')
	echo "RESULT $1 decode_errors=$errs frames=$frames psnr_avg=$psnr"
}

gen 1920 1080 src1080
gen 1280 720 src720

log "single-frame smoke test"
$ENC -i src720.nv12 -o smoke.h264 -W 1280 -H 720 -n 1 -g 1 -v && check smoke.h264 1280 720 src720.nv12
dmesg | tail -5

for res in 720 1080; do
	if [ $res = 720 ]; then W=1280 H=720; else W=1920 H=1080; fi
	for qp in 20 28 36; do
		log "$res I-only qp $qp CAVLC"
		$ENC -i src$res.nv12 -o i_${res}_q$qp.h264 -W $W -H $H -n $N -g 1 -q $qp && \
			check i_${res}_q$qp.h264 $W $H src$res.nv12
		log "$res IPPP gop30 qp $qp CAVLC"
		$ENC -i src$res.nv12 -o p_${res}_q$qp.h264 -W $W -H $H -n $N -g 30 -q $qp && \
			check p_${res}_q$qp.h264 $W $H src$res.nv12
		log "$res IPPP gop30 qp $qp CABAC main"
		$ENC -i src$res.nv12 -o pc_${res}_q$qp.h264 -W $W -H $H -n $N -g 30 -q $qp -c && \
			check pc_${res}_q$qp.h264 $W $H src$res.nv12
	done
	log "$res High 8x8 CABAC qp 28"
	$ENC -i src$res.nv12 -o h_${res}.h264 -W $W -H $H -n $N -g 30 -q 28 -c -p 100 -8 && \
		check h_${res}.h264 $W $H src$res.nv12
	log "$res constrained baseline qp 28"
	$ENC -i src$res.nv12 -o cb_${res}.h264 -W $W -H $H -n $N -g 30 -q 28 -p 66 && \
		check cb_${res}.h264 $W $H src$res.nv12
	for br in 2000000 8000000; do
		log "$res CBR $br"
		$ENC -i src$res.nv12 -o cbr_${res}_$br.h264 -W $W -H $H -n $N -g 30 -b $br -c && \
			check cbr_${res}_$br.h264 $W $H src$res.nv12
	done
	log "$res CQ 80"
	$ENC -i src$res.nv12 -o cq_${res}.h264 -W $W -H $H -n $N -g 30 -Q 80 && \
		check cq_${res}.h264 $W $H src$res.nv12
done

for n in 2 4; do
	log "$n parallel 1080p streams"
	i=0; pids=
	while [ $i -lt $n ]; do
		$ENC -i src1080.nv12 -o par${n}_$i.h264 -W 1920 -H 1080 -n $N -g 30 -q 28 -c &
		pids="$pids $!"; i=$((i + 1))
	done
	wait $pids
	i=0; while [ $i -lt $n ]; do check par${n}_$i.h264 1920 1080 src1080.nv12; i=$((i + 1)); done
done
dmesg | grep -i -E "hantro|vepu|iommu|fdba" | tail -20

# Live webcam test: YUYV 4:2:2 straight into the encoder (needs the Aluratek camera).
CAM=${CAM:-/dev/v4l/by-id/usb-SHENZHEN_AONI_ELECTRONIC_CO._LTD_Aluratek_UHD_4K_Camera_N20201014001-video-index0}
if [ -e "$CAM" ]; then
	log "webcam YUYV 1280x720 -> H.264 (live pipe)"
	ffmpeg -v error -f v4l2 -input_format yuyv422 -video_size 1280x720 -i "$CAM" \
		-frames:v 90 -f rawvideo - | tee cam720.yuyv | \
		$ENC -Y -i - -W 1280 -H 720 -g 30 -q 28 -c -o cam720.h264
	errs=$(ffmpeg -v error -i cam720.h264 -f null - 2>&1 | wc -l)
	psnr=$(ffmpeg -v info -i cam720.h264 -f rawvideo -pix_fmt yuyv422 -s 1280x720 -i cam720.yuyv \
		-lavfi "[0:v]settb=1/30,setpts=N,format=yuv420p[a];[1:v]settb=1/30,setpts=N,format=yuv420p[b];[a][b]psnr" \
		-f null - 2>&1 | sed -n 's/.*PSNR y:\([0-9.inf]*\).*average:\([0-9.inf]*\).*/y=\1 avg=\2/p')
	echo "RESULT cam720.h264 decode_errors=$errs psnr_avg=$psnr"
fi
