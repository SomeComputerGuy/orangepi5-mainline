#!/bin/bash
# IEP2 quality/throughput tests; run on the board as a normal user.
# usage: board-test.sh /dev/videoN
set -u
DEV=$1
T=/tmp/iep
mkdir -p $T
cd $T || exit 1
IEPT=$T/iep-test
N=50	# progressive frames -> N/2 interlaced frames

psnr() { # size fmt out ref
	ffmpeg -hide_banner -nostats -f rawvideo -s $1 -pix_fmt $2 -i $3 \
		-f rawvideo -s $1 -pix_fmt $2 -i $4 -lavfi psnr -f null - 2>&1 |
		sed -n 's/.*PSNR y:\([0-9.inf]*\).*average:\([0-9.inf]*\).*/Y=\1 avg=\2/p'
}

gen() { # size fmt
	local s=$1 f=$2
	[ -f prog_${s}_$f.yuv ] && return
	ffmpeg -hide_banner -loglevel error -f lavfi -i testsrc2=size=$s:rate=50 \
		-frames:v $N -pix_fmt $f -f rawvideo prog_${s}_$f.yuv
	# even frames = first-field times (frame-rate reference)
	ffmpeg -hide_banner -loglevel error -f rawvideo -s $s -pix_fmt $f -i prog_${s}_$f.yuv \
		-vf "select=not(mod(n\,2))" -fps_mode passthrough -f rawvideo -pix_fmt $f even_${s}_$f.yuv
	for o in tff bff; do
		ffmpeg -hide_banner -loglevel error -f rawvideo -s $s -pix_fmt $f -r 50 \
			-i prog_${s}_$f.yuv -vf "interlace=scan=$o:lowpass=off" \
			-pix_fmt $f -f rawvideo int_${s}_${f}_$o.yuv
	done
}

for s in 720x576 1920x1080; do
for f in nv12 nv16; do
	rm -f /tmp/iep/*.yuv
	gen $s $f
	w=${s%x*}; h=${s#*x}
	for o in tff bff; do
		F=tb; [ $o = bff ] && F=bt
		in=int_${s}_${f}_$o.yuv
		for m in bob ma; do
			for r in 0 1; do
				ref=even_${s}_$f.yuv; ro=""; [ $r = 1 ] && { ref=prog_${s}_$f.yuv; ro=-r; }
				out=out_${s}_${f}_${o}_${m}_$r.yuv
				res=$($T/guard.sh 60 $IEPT -d $DEV -i $in -o $out -w $w -h $h -f $f -F $F -m $m $ro 2>&1 | tail -2 | tr "\n" " ")
				case "$res" in *iommu_faults=+0*) ;; *) echo "FAULT/ERR: $res"; exit 99;; esac
				echo "IEP $s $f $o $m rate=$r: $(psnr $s $f $out $ref) | $res"
				rm -f $out
			done
		done
		# software references
		for sw in bwdif yadif; do
			for r in 0 1; do
				ref=even_${s}_$f.yuv; mo=send_frame
				[ $r = 1 ] && { ref=prog_${s}_$f.yuv; mo=send_field; }
				out=sw_${s}_${f}_${o}_${sw}_$r.yuv
				ffmpeg -hide_banner -loglevel error -f rawvideo -s $s -pix_fmt $f -r 25 -i $in \
					-vf "setfield=$o,$sw=mode=$mo:parity=$o" -pix_fmt $f -f rawvideo -y $out
				echo "SW  $s $f $o $sw rate=$r: $(psnr $s $f $out $ref)"
				rm -f $out
			done
		done
		# weave (no deinterlacing) baseline
		echo "RAW $s $f $o weave: $(psnr $s $f $in even_${s}_$f.yuv)"
		rm -f $in
	done
done
done
