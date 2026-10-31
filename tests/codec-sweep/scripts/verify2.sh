#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Verification of the final opi5-codec-quality modules (run on the board from ~/cq, detached).
cd ~/cq; W=~/codecsweep/work; O=verify2.txt; : > $O
s() { echo "== $*" | tee -a $O; }
node() { for d in /sys/class/video4linux/video*; do grep -q "$1" $d/name && echo /dev/$(basename $d); done | head -1; }
s modules; for m in rockchip_jpegd hantro_vpu rockchip_vdec; do modinfo -n $m; done | tee -a $O
s "v4l2-compliance -s -f"
for n in rockchip-jpegd rkvdec vpu121-dec vpu121-enc vepu121-enc rockchip-venc; do d=$(node $n)
	echo "$n $d: $(timeout 900 v4l2-compliance -d $d -s -f 2>&1 | tee comp2_$n.txt | grep -E '^Total')" | tee -a $O; done
s "rkvdec 4K fps (fakevideosink) and bit-exact first 30 frames vs ffmpeg"
for x in h264:h264parse:ref_h264_3840x2160_60.mkv h265:h265parse:ref_h265_3840x2160_60.mkv; do IFS=: read c p f <<<"$x"; E=$(./elem.sh $c rkvdec)
	t0=$(date +%s.%N); gst-launch-1.0 -q filesrc location=$W/$f ! matroskademux ! $p ! $E ! fakevideosink sync=false; t1=$(date +%s.%N)
	gst-launch-1.0 -q filesrc location=$W/$f ! matroskademux ! $p ! $E ! videoconvert ! video/x-raw,format=I420 ! identity eos-after=31 ! filesink location=v2h.yuv
	ffmpeg -nostdin -v error -y -i $W/$f -frames:v 30 -f rawvideo -pix_fmt yuv420p v2s.yuv
	echo "$f fps=$(echo "240/($t1-$t0)" | bc -l | cut -c1-6) $(./vqcmp.sh exact v2h.yuv v2s.yuv 3840x2160 30 | cut -c1-16)" | tee -a $O; done
rm -f v2h.yuv v2s.yuv
s "MPEG-2 conformance"; ./mpeg2-conf.sh 2>&1 | tee mpeg2conf-final.txt >> $O
s fluster; ./run-fluster.sh; cat fluster-results.txt >> $O
s "kernel"; sudo dmesg | grep -cE 'stall request|paging request|Oops|BUG:|timed out' | sed 's/^/iommu stall\/oops\/timeout lines: /' | tee -a $O
echo DONE >> $O
