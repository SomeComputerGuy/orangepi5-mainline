#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0
"""host: levels.py <calib-HDMI-A-1.json> <run dir>  quantization-range probe from the "levels" frames

kmsctl "levels": top 55 % = 8 grey bands at codes 0, 16, 32, 64, 160, 224, 235, 255. Lighting invariant: per
frame, n(v) = (L(v) - L(0)) / (L(255) - L(0)). Full-range data shown as limited by the sink crushes 0 and 16
(n16 ~ 0) and clips 235 and 255 (n235 ~ 1); with the matching range n16 > 0 and n235 < 1. The run compares RGB
on CTA modes against YCbCr (always limited, VOP2 R2Y limited matrix) and RGB on IT modes (full) on the same mode."""
import glob, json, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import camcheck as TMC

LEVELS = (0, 16, 32, 64, 160, 224, 235, 255)


def lum(p):
    return p[0] * .299 + p[1] * .587 + p[2] * .114


def measure(g, flip):
    L = [lum(TMC.region(g, i / 8, .08, (i + 1) / 8, .50, flip=flip, inner=.5)) for i in range(8)]
    on = [lum(TMC.region(g, i / 16, .56, (i + 1) / 16, .69, flip=flip, inner=.5)) for i in range(0, 16, 2)]
    off = [lum(TMC.region(g, i / 16, .56, (i + 1) / 16, .69, flip=flip, inner=.5)) for i in range(1, 16, 2)]
    st = sum(a > b for a, b in zip(on, off))
    return L, st


cal = TMC.with_top_ext(json.load(open(sys.argv[1])))
out = []
for d in sorted(glob.glob(f"{sys.argv[2]}/c/L*")):
    res = []
    for f in sorted(glob.glob(f"{d}/lev*.rgb")):
        g, _ = TMC.picture_grid(TMC.load(f), cal)
        L, st = max((measure(g, fl) for fl in (False, True)), key=lambda x: x[1])
        rng = max(L[7] - L[0], 1e-3)
        n = [round((x - L[0]) / rng, 3) for x in L]
        res.append(dict(stripes=st, range=round(rng, 1), n=n))
    if not res:
        continue
    ok = [r for r in res if r["stripes"] >= 7 and r["range"] > 20]
    avg = [round(sum(r["n"][k] for r in ok) / len(ok), 3) for k in range(8)] if ok else None
    out.append(dict(case=os.path.basename(d), frames=len(res), usable=len(ok), n=avg))
    print(os.path.basename(d), f"{len(ok)}/{len(res)} usable",
          dict(zip(LEVELS, avg)) if avg else "-")
json.dump(out, open(f"{sys.argv[2]}/levels.json", "w"), indent=1)
