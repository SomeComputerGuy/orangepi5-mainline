#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Orange Pi 5 board test for patches/ffmpeg 0012 (HEVC EXT_SPS_ST/LT_RPS).
# Decodes HEVC conformance vectors with FFmpeg's v4l2request hwaccel (rkvdec,
# VDPU381) and compares every frame with FFmpeg's software decode.
#
# usage: board-hevc-extsps.sh FFMPEG VECTOR_DIR OUT_DIR [NAME...]
#   FFMPEG      ffmpeg binary to test (bin/ffmpeg-before, bin/ffmpeg-after, or
#               /usr/bin/ffmpeg from the rebuilt debs)
#   VECTOR_DIR  directory with the JCT-VC-HEVC_V1 vectors (one subdirectory per
#               vector, as fluster or hevc-conf/x lay them out)
#   NAME...     vector names (default: all 8-bit vectors found)
# Output: OUT_DIR/results.txt ("PASS|FAIL|ERROR name frames-differing/total")
#         and OUT_DIR/<name>.{hw,sw}.framemd5, <name>.log
set -u
DMESG=${DMESG:-sudo -n dmesg}   # kernel log reader (the board has passwordless sudo)
FF=$1 VEC=$2 OUT=$3; shift 3
mkdir -p "$OUT"
RES=$OUT/results.txt; : > "$RES"

if [ $# -gt 0 ]; then
  NAMES=("$@")
else
  mapfile -t NAMES < <(find "$VEC" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' |
                       grep -viE 'main10|TSUNEQBD' | sort)
fi

warn0=$($DMESG 2>/dev/null | grep -c 'Long and short term RPS not set')
"$FF" -hide_banner -loglevel verbose -hwaccel v4l2request -hwaccel_output_format drm_prime \
  -i "$(find "$VEC/RPS_A_docomo_5" -name '*.bit' | head -1)" -frames:v 1 -f null - 2>&1 |
  grep -m1 -- '-based decoder with' | tee "$OUT/probe.txt"

for n in "${NAMES[@]}"; do
  f=$(find "$VEC/$n" -path '*__MACOSX*' -prune -o \( -name '*.bit' -o -name '*.bin' \) -print | head -1)
  [ -n "$f" ] || { echo "ERROR $n no-bitstream" | tee -a "$RES"; continue; }
  # Software reference, same binary, same output format
  "$FF" -hide_banner -nostdin -loglevel error -threads 1 -i "$f" -fps_mode passthrough \
    -vf format=yuv420p -f framemd5 "$OUT/$n.sw.framemd5" 2> "$OUT/$n.log"
  # hwdownload fails if the hwaccel did not run (no software fallback is possible here)
  timeout 300 "$FF" -hide_banner -nostdin -loglevel warning -threads 1 \
    -hwaccel v4l2request -hwaccel_output_format drm_prime -i "$f" -fps_mode passthrough \
    -vf hwdownload,format=nv12,format=yuv420p -f framemd5 "$OUT/$n.hw.framemd5" >> "$OUT/$n.log" 2>&1
  rc=$?
  sw=$(grep -vc '^#' "$OUT/$n.sw.framemd5" 2>/dev/null || echo 0)
  if [ $rc -ne 0 ] || [ ! -s "$OUT/$n.hw.framemd5" ]; then
    echo "ERROR $n rc=$rc" | tee -a "$RES"; continue
  fi
  bad=$(diff <(grep -v '^#' "$OUT/$n.sw.framemd5" | awk -F, '{print $NF}') \
             <(grep -v '^#' "$OUT/$n.hw.framemd5" | awk -F, '{print $NF}') | grep -c '^>')
  hw=$(grep -vc '^#' "$OUT/$n.hw.framemd5")
  if [ "$bad" -eq 0 ] && [ "$hw" -eq "$sw" ]; then r=PASS; else r=FAIL; fi
  echo "$r $n $bad/$sw (hw frames $hw)" | tee -a "$RES"
done

warn1=$($DMESG 2>/dev/null | grep -c 'Long and short term RPS not set')
{
  echo "pass: $(grep -c '^PASS' "$RES")  fail: $(grep -c '^FAIL' "$RES")  error: $(grep -c '^ERROR' "$RES")"
  echo "kernel 'Long and short term RPS not set' warnings during the run: $((warn1 - warn0)) (rate-limited)"
} | tee -a "$RES"
