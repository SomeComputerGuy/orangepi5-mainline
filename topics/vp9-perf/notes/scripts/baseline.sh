#!/bin/sh
# Full benchmark matrix; run from ~/vp9perf. $1 = label
i=0; while pgrep -f "fluster|slenc|gst-launch" >/dev/null && [ $i -lt 60 ]; do sleep 5; i=$((i+1)); done
echo "== $1 $(uname -r) $(date) load: $(cut -d' ' -f1-3 /proc/loadavg)"
pgrep -af "gst-launch|fluster|slenc|ffmpeg" | grep -v pgrep | grep -v baseline
for c in 4k8.webm 4k10.webm 4k10hb.webm 1080p.webm 4k8.hevc.mkv 4k8.h264.mkv; do
  for n in 1 2; do ./bench.sh $c $n fakevideosink; done
done
./bench.sh 4k8.webm 1 fakesink
./bench.sh 4k10.webm 1 fakesink
./bench.sh 4k8.webm 2 fakesink
