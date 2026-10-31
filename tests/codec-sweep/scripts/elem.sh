#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# elem.sh <codec> <device-name-substring>: the GStreamer v4l2codecs decoder element for a codec on
# a given device (element names depend on /dev/video numbering, which changes between boots).
for e in $(gst-inspect-1.0 v4l2codecs 2>/dev/null | grep -oE "v4l2sl[a-z0-9]*${1}dec" | sort -u); do
	dev=$(gst-inspect-1.0 $e 2>/dev/null | grep -oE '/dev/video[0-9]+' | head -1)
	[ -n "$dev" ] && grep -q "$2" /sys/class/video4linux/$(basename $dev)/name && { echo $e; exit 0; }
done; exit 1
