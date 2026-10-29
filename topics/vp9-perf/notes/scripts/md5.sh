#!/bin/sh
# usage: md5.sh clip  -> md5 over the per-frame md5s of the visible picture
f=$1; t=$(mktemp)
gst-launch-1.0 -q filesrc location=$f ! matroskademux ! vp9parse ! v4l2slvp9dec ! \
	checksumsink hash=md5 sync=false 2>/dev/null | awk '{print $NF}' > $t
echo "$(md5sum < $t | cut -c1-32)  $f ($(wc -l < $t) frames)"
rm -f $t
