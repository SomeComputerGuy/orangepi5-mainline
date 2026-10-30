#!/bin/sh
# Run as root with nothing holding DRM master. A 440 Hz tone plays on the TV
# (HDMI, as aruni) for ~30 s while the mode changes:
#   0 s 4K60 (FRL) -> 6 s 4K120 (FRL) -> 14 s 4K60 -> 20 s 1080p60 (TMDS) -> 26 s 4K60
# Ask: does the tone continue cleanly after each screen blink (4 blinks)?
st() { echo "$(date +%T) $1: $(grep -E "^state" /proc/asound/hdmi0/pcm0p/sub0/status)"; }
su aruni -c "timeout 32 gst-launch-1.0 -q audiotestsrc freq=440 volume=0.2 is-live=true ! audio/x-raw,rate=48000,channels=2 ! alsasink device=plughw:hdmi0" &
sleep 6; st "-> 4K120";  sleep 8 | timeout 12 modetest -M rockchip -s 88@83:3840x2160-120 >/dev/null 2>&1
st "-> 4K60"; sleep 6; st "-> 1080p60"; sleep 6 | timeout 10 modetest -M rockchip -s 88@83:1920x1080-60 >/dev/null 2>&1
st "-> 4K60"; wait; echo "$(date +%T) tone stopped"
