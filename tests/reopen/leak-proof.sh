#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# 500 mid-stream NULLs per decoder (rkvdec H.264 4K, rkvdec HEVC 4K, Hantro H.264 1080p) in one
# process each; PASS = 0 start failures and 0 dma-buf fds left open after every cycle.
#   leak-proof.sh [N=500]     (on the board, from ~/reopen)
D=$(cd "$(dirname "$0")" && pwd); N=${1:-500}; O=$D/results/leak-$(date +%H%M%S); mkdir -p $O
dpkg -l gstreamer1.0-plugins-bad libgstreamer-plugins-bad1.0-0 | awk '/^ii/{print $2, $3}' | tee $O/versions.txt
for b in rkvdec-h264 rkvdec-hevc hantro-h264; do
  bash $D/matrix.sh desc $b | python3 $D/tools/gst-null-leak.py $N > $O/$b.json 2> $O/$b.log
  python3 - "$b" "$O/$b.json" <<'EOF' | tee -a $O/summary.txt
import json, sys
d = json.load(open(sys.argv[2]))
ok = d['fail_start'] == 0 and d['dmabufs_max'] == 0 and d.get('fds_growth', 0) <= 0
print('%-12s %s: %d cycles, %d start failures, dma-buf fds open max %d / at end %d, other fds grew by %d, stops after k frames %s %s' % (
    sys.argv[1], 'PASS' if ok else 'FAIL', d['cycles'], d['fail_start'], d['dmabufs_max'], d['dmabufs_end'], d.get('fds_growth', 0),
    d['k_hist'], d['errors'][:2]))
EOF
done
