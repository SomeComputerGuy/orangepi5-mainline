#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
# Build and run spsdump (host). Usage: spsdump.sh VECTOR.bit...
set -e
T=$(cd "$(dirname "$0")" && pwd)
B=${EXTSPS_BUILD:-$HOME/orangepi5/build/ffmpeg-hevc-extsps}
SRC=$HOME/orangepi5/work/_downloads/ffmpeg-hevc-extsps/ffmpeg
O=${SPSDUMP_OUT:-$HOME/orangepi5/build/rkvdec-hevc-rps-host}
mkdir -p "$O"
gcc -std=gnu17 -g -O1 -Wall -fsanitize=address,undefined -I"$B/host" -I"$SRC" \
    -o "$O/spsdump" "$T/spsdump.c" \
    "$B/host/libavcodec/libavcodec.a" "$B/host/libavutil/libavutil.a" -lm -pthread
ASAN_OPTIONS=detect_leaks=0 "$O/spsdump" "$@"
