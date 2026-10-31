#!/bin/sh
# SPDX-License-Identifier: GPL-2.0
# Read DP sink CRCs (DPCD 0x240-0x245) N times while TEST_SINK_START is set.
AUX=${AUX:-/dev/drm_dp_aux0}; N=${1:-5}
rd() { dd if=$AUX bs=1 skip=$(($1)) count=$2 status=none | xxd -p; }
wr() { printf "$(printf '\\%03o' $2)" | dd of=$AUX bs=1 seek=$(($1)) count=1 status=none; }
wr 0x270 1
i=0; while [ $i -lt $N ]; do sleep 0.1; echo "crc=$(rd 0x240 6) misc=$(rd 0x246 1) symerr=$(rd 0x210 4)"; i=$((i+1)); done
wr 0x270 0
