#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Reproducer for the souphttpsrc HEAD-probe race: start the stream-B pipeline N times and count instant
# "Internal data stream error" (flow -5) failures.   soup-race.sh <stock|patched> [N=30]
V=${1:-stock}; N=${2:-30}; fail=0
source <(sed -n "/^dev_of/,/^demux_for/p" $HOME/maxout/maxout.sh); D=$(dec_for h265)
PP=""; [ $V = patched ] && PP=$HOME/gstbuild/plug
for ((i=1; i<=N; i++)); do
  sudo env XDG_RUNTIME_DIR=/run/user/0 WAYLAND_DISPLAY=wayland-9 GST_PLUGIN_PATH=$PP timeout 4 gst-launch-1.0 souphttpsrc \
    location=http://${OPI5_HOST_IP:-172.31.55.1}:8099/tears_of_steel_2160p_hevc.mp4 ! queue2 use-buffering=true max-size-bytes=100000000 ! qtdemux ! \
    h265parse ! queue ! $D ! queue ! fpsdisplaysink text-overlay=false sync=true video-sink="waylandsink fullscreen=true fullscreen-output=HDMI-A-1" \
    > /tmp/soup-race.log 2>&1
  grep -q "Internal data stream error" /tmp/soup-race.log && fail=$((fail+1))
done
echo "$V: $fail/$N instant start failures"
