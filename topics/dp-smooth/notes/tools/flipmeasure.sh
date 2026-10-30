#!/bin/sh
# flipmeasure.sh <tag> <connector-id> <plane-id> <clip> [seconds] [extra kmssink props]
# Plays <clip> with v4l2codecs + kmssink on one connector for N seconds while recording
# drm vblank trace events in a private tracefs instance; writes $OUT/<tag>.{trace,gst}.
set -e
TAG=$1 CONN=$2 PLANE=$3 CLIP=$4 SECS=${5:-8} EXTRA=$6
OUT=${OUT:-$HOME/dpsmooth/out}; mkdir -p "$OUT"
case "$CLIP" in *h265*) P=h265parse D=v4l2slh265dec;; *h264*) P=h264parse D=v4l2slh264dec;; *av1*) P=av1parse D=v4l2slav1dec;; esac
I=/sys/kernel/tracing/instances/dpsmooth
sudo mkdir -p $I
echo 0 | sudo tee $I/tracing_on >/dev/null
echo 16384 | sudo tee $I/buffer_size_kb >/dev/null
echo | sudo tee $I/trace >/dev/null
for e in drm_vblank_event drm_vblank_event_queued drm_vblank_event_delivered; do echo 1 | sudo tee $I/events/drm/$e/enable >/dev/null; done
echo 1 | sudo tee $I/tracing_on >/dev/null
timeout -s INT $SECS gst-launch-1.0 -e filesrc location="$CLIP" ! matroskademux ! $P ! $D ! \
  fpsdisplaysink text-overlay=false video-sink="kmssink connector-id=$CONN plane-id=$PLANE $EXTRA" -v > "$OUT/$TAG.gstout" 2> "$OUT/$TAG.gst" || true
echo 0 | sudo tee $I/tracing_on >/dev/null
sudo cat $I/trace > "$OUT/$TAG.trace"
for e in drm_vblank_event drm_vblank_event_queued drm_vblank_event_delivered; do echo 0 | sudo tee $I/events/drm/$e/enable >/dev/null; done
sudo rmdir $I
wc -l "$OUT/$TAG.trace" "$OUT/$TAG.gst"
