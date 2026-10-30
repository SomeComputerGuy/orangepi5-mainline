#!/bin/sh
# idlecommits.sh <tag> <secs>: count kernel-internal (fbdev) commit-done events per CRTC with no client
I=/sys/kernel/tracing/instances/dpsmooth2; sudo mkdir -p $I
echo 1 | sudo tee $I/events/drm/drm_vblank_event_delivered/enable >/dev/null
echo | sudo tee $I/trace >/dev/null; echo 1 | sudo tee $I/tracing_on > /dev/null
sleep $2; echo 0 | sudo tee $I/tracing_on > /dev/null
printf "%s: " $1; sudo grep -o "file=0000000000000000, crtc=[0-9]" $I/trace | sort | uniq -c | tr '\n' ' '; echo
echo 0 | sudo tee $I/events/drm/drm_vblank_event_delivered/enable >/dev/null; sudo rmdir $I
