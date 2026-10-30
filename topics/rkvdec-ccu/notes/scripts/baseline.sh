#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# baseline.sh: fps and bit-exactness of the currently loaded rkvdec (before the CCU driver).
set -u
. $(dirname $(readlink -f $0))/ccu-lib.sh
D=~/ccu/baseline-$(date +%m%d-%H%M); mkdir -p $D; cd $D
log() { echo "$*" | tee -a summary.txt; }
log "== $(date) rockchip-vdec: $(modinfo -n rockchip-vdec)"
for c in 5 4 9; do log "codec $c: $(fps $c) fps; $(exact $c base)"; done
t0=$(date +%s.%N)
for i in 1 2; do gst-launch-1.0 -q $(src 5) ! fakevideosink sync=false >/dev/null 2>&1 & done; wait
log "2 x HEVC decode-only: $(echo "1200/($(date +%s.%N)-$t0)" | bc -l | cut -c1-5) fps total"
