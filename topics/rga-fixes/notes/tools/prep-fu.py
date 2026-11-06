#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""rga-fu: test inputs on the host (run with python3 -I).

prep-fu.py OUTDIR BASEDIR
  BASEDIR = the rga3-nv15 inputs (made by its prep.py). OUTDIR gets a symlink to each of them (run.sh
  pushes with tar -h) plus the 10-bit 4:2:2 picture for the NV20 cases:
    pic10.nv20   frame 0 of hevc10 (hevc10-f0.ref10) with every chroma row doubled, packed as V4L2 NV20
    pic10.ref422 the same samples as 16-bit little endian, Y plane then the interleaved CbCr plane (h rows)
  Doubled rows make 4:2:2 -> 4:2:0 conversions exact whether the hardware drops or averages rows.
"""
import os, sys
import numpy as np

OUT, BASE = sys.argv[1:3]
W, H = 1920, 1080
os.makedirs(OUT, exist_ok=True)
for f in os.listdir(BASE):
    d = os.path.join(OUT, f)
    if f != 'PREP-DONE' and not os.path.lexists(d):
        os.symlink(os.path.abspath(os.path.join(BASE, f)), d)


def pack_10b(a):
    """10-bit samples (rows, cols % 4 == 0) -> 4 samples in 40 bits, little endian (NV15/NV20)."""
    a = a.astype(np.uint64).reshape(a.shape[0], -1, 4)
    v = a[..., 0] | (a[..., 1] << 10) | (a[..., 2] << 20) | (a[..., 3] << 30)
    b = np.stack([(v >> (8 * i)) & 0xff for i in range(5)], axis=-1).astype(np.uint8)
    return b.reshape(a.shape[0], -1)


nv20 = os.path.join(OUT, 'pic10.nv20')
if not os.path.exists(nv20):
    raw = np.fromfile(os.path.join(BASE, 'hevc10-f0.ref10'), '<u2', W * H * 3 // 2)
    y = raw[:W * H].reshape(H, W)
    c = np.repeat(raw[W * H:].reshape(H // 2, W), 2, axis=0)
    with open(os.path.join(OUT, 'pic10.ref422.tmp'), 'wb') as f:
        f.write(y.astype('<u2').tobytes() + c.astype('<u2').tobytes())
    with open(nv20 + '.tmp', 'wb') as f:
        f.write(pack_10b(y).tobytes() + pack_10b(c).tobytes())
    os.rename(os.path.join(OUT, 'pic10.ref422.tmp'), os.path.join(OUT, 'pic10.ref422'))
    os.rename(nv20 + '.tmp', nv20)
open(os.path.join(OUT, 'PREP-DONE'), 'w').write('ok\n')
print('prep-fu done', OUT)
