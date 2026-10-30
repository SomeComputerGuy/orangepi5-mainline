# SPDX-License-Identifier: GPL-2.0-only
# ccu-lib.sh: helpers shared by ccu-verify.sh and baseline.sh (sourced)
E5=$(~/cq/elem.sh h265 rkvdec); E4=$(~/cq/elem.sh h264 rkvdec); E9=$(~/cq/elem.sh vp9 rkvdec)
C5=~/demo/yacht_hevc_2160p120.mp4 C4=~/demo/yacht_h264_2160p120.mp4 C9=~/demo/yacht_vp9_2160p120.webm
src() { case $1 in 5) echo "filesrc location=$C5 ! qtdemux ! h265parse ! $E5";;
		   4) echo "filesrc location=$C4 ! qtdemux ! h264parse ! $E4";;
		   9) echo "filesrc location=$C9 ! matroskademux ! vp9parse ! $E9";; esac; }
clip() { case $1 in 5) echo $C5;; 4) echo $C4;; 9) echo $C9;; esac; }
fps() {	# fps <codec>: decode the whole 600-frame clip into fakevideosink, best of 2
	local best=0 t
	for r in 1 2; do
		t0=$(date +%s.%N)
		gst-launch-1.0 -q $(src $1) ! fakevideosink sync=false >/dev/null 2>&1 || { echo FAIL; return; }
		t=$(echo "600 / ($(date +%s.%N) - $t0)" | bc -l)
		best=$(echo "if ($t > $best) $t else $best" | bc -l)
	done; printf "%.1f" $best; }
exact() { # exact <codec> <tag>: per-frame md5 of the whole clip vs FFmpeg software decoding
	[ -f $HOME/ccu/ref$1.md5 ] || ffmpeg -nostdin -v error -i $(clip $1) -pix_fmt yuv420p -f framemd5 $HOME/ccu/ref$1.md5
	local n m try note=""
	for try in 1 2; do	# a truncated run (seen once, with another agent switching HDMI modes) is retried once
		gst-launch-1.0 -q $(src $1) ! videoconvert ! video/x-raw,format=I420 ! fdsink fd=1 2>gst$1-$2.err |
			ffmpeg -nostdin -v error -f rawvideo -pix_fmt yuv420p -s 3840x2160 -i - -f framemd5 t$1-$2.md5
		[ $(grep -vc '^#' t$1-$2.md5) -ge 600 ] && break
		note=" (run 1 truncated at $(grep -vc '^#' t$1-$2.md5) frames, retried)"; cp t$1-$2.md5 t$1-$2.try1.md5
	done
	n=$(grep -vc '^#' $HOME/ccu/ref$1.md5); m=$(paste -d' ' <(grep -v '^#' $HOME/ccu/ref$1.md5 | awk -F, '{print $NF}') \
		<(grep -v '^#' t$1-$2.md5 | awk -F, '{print $NF}') | awk '$1==$2' | wc -l)
	echo "$m/$n frames bit-exact (gst frames: $(grep -vc '^#' t$1-$2.md5))$note"; }

