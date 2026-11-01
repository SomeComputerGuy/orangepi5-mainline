#!/bin/sh
# SPDX-License-Identifier: GPL-2.0
# Minimal trigger: N rounds of [4096x2160@60/593407 YUV420 8 bpc TMDS -> (fbdev restore) -> 1080p60 RGB 8 bpc TMDS]
# usage (root, gdm stopped): hunt2.sh <outdir> <rounds>
. /var/tmp/wedge/seq.sh
out=$1; n=$2; steps=""; i=0
while [ $i -lt $n ]; do
	steps="$steps|y$i:$T4096,$B8,$Y420,$LIN|t$i:$T1080,$B8,$AUTO,$LIN"
	i=$((i+1))
done
IFS='|'; set -- $steps; shift; unset IFS
POSTCAP=0 /var/tmp/wedge/run.sh "$out" log.txt "$@"
