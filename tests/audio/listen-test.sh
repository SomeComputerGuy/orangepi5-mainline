#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
# Orange Pi 5 audible output check, run as the normal (non-root) user.
# Usage: listen-test.sh [hdmi|hp|dp|all]   (default: all)
# Each output plays: spoken "Front Left"/"Front Right" (speaker-test -t wav),
# a 2 s 440 Hz sine via GStreamer alsasink, then 2 s 880 Hz via autoaudiosink
# (autoaudiosink only for the default device, so it is played once at the end).
set -u
card() { aplay -l | sed -n "s/^card \([0-9]*\): $1 .*/\1/p" | head -1; }
play() { # name card-id
	c=$(card "$2")
	if [ -z "$c" ]; then echo "== $1: no card $2"; return; fi
	echo "== $1 (card $c): voice Front Left / Front Right"
	timeout 15 speaker-test -D plughw:$c,0 -c 2 -t wav -l 1 >/dev/null 2>&1 || echo "   speaker-test failed: $?"
	echo "== $1 (card $c): 440 Hz sine, 2 s (GStreamer alsasink)"
	timeout 10 gst-launch-1.0 -q audiotestsrc freq=440 volume=0.3 num-buffers=94 ! \
		audioconvert ! audioresample ! alsasink device=plughw:$c,0 || echo "   alsasink failed: $?"
	sleep 1
}
what=${1:-all}
id
case $what in hdmi|all) play HDMI hdmi0 ;; esac
case $what in hp|all) play "Headphone jack" rockchipes8388 ;; esac
case $what in dp|all) play "USB-C DP" dp0 ;; esac
if [ "$what" = all ]; then
	echo "== default device: 880 Hz sine, 2 s (GStreamer autoaudiosink)"
	timeout 10 gst-launch-1.0 -q audiotestsrc freq=880 volume=0.3 num-buffers=94 ! \
		audioconvert ! audioresample ! autoaudiosink || echo "   autoaudiosink failed: $?"
fi
