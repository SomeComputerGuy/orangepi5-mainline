#!/bin/sh
# SPDX-License-Identifier: GPL-2.0
# Wedge hunt: N rounds of [4096x2160@60/593407 YUV420 8 bpc TMDS -> 4096x2160@60 10 bpc FRL AFBC XR30 -> 1080p RGB TMDS]
# usage (root, gdm stopped): hunt.sh <outdir> <rounds> [FRL timing var name, default T4096]
. /var/tmp/wedge/seq.sh
out=$1; n=$2; frl=${3:-T4096}; eval FT=\$$frl
steps=""
i=0
while [ $i -lt $n ]; do
	set -- "$@"
	steps="$steps|y$i:$T4096,$B8,$Y420,$LIN|f$i:$FT,$B10,$AUTO,$AFBC30|t$i:$T1080,$B8,$AUTO,$LIN"
	i=$((i+1))
done
IFS='|'; set -- $steps; shift; unset IFS
POSTCAP=0 /var/tmp/wedge/run.sh "$out" log.txt "$@"
