#!/bin/sh
# Labelled tones: HDMI (TV) 440 Hz 3 s, 3 s pause, DP (Dell) 880 Hz 3 s.
t() { timeout 6 gst-launch-1.0 -q audiotestsrc freq=$2 volume=0.3 num-buffers=141 ! audioconvert ! audioresample ! alsasink device=plughw:$1 || echo "$1 failed (busy?)"; }
date +"%T HDMI/TV 440 Hz"; t hdmi0 440; sleep 3
date +"%T DP/Dell 880 Hz"; t dp0 880; date +"%T done"
