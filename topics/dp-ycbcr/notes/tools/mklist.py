#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0
"""host: fmtck lists.  mklist.py <kms-list.json> <outdir>  -> quick.tsv (wire format + OSD + levels), t2.tsv (all accepted)"""
import json, sys
sys.path.insert(0, __file__.rsplit("/", 1)[0])
import hmodel
lst = json.load(open(sys.argv[1]))
O = sys.argv[2]
hc = next(c for c in lst["connectors"] if c["name"] == "HDMI-A-1")
CFS = [("AUTO", "AUTO"), ("RGB", "RGB"), ("444", "YUV 4:4:4"), ("422", "YUV 4:2:2"), ("420", "YUV 4:2:0")]


def spec(i, b, cf):
    p, f, m = (35, "XR30", "auto") if b > 8 else (59, "XR24", "linear")
    return f"conn=HDMI-A-1,mode={i},prop:max bpc={b},prop:color format={cf},plane={p},fmt={f},mod={m}"


code = 100
def row(cid, s, kind):
    global code
    code += 1
    return f"{cid}\t{s}\t{kind}\t{code}\n"


q = []
for i in (19, 11, 0, 6):            # 1080p60 TMDS, 4K30 TMDS, 4K60 (FRL at 10 bpc / 4:2:0 TMDS), 4K120 FRL
    for b in (8, 10):
        for k, cf in CFS:
            if hmodel.expect(hc["modes"][i], cf, b):
                q.append(row(f"H{i}_{b}_{k}", spec(i, b, cf), "osd"))
for i, b, k in [(19, 8, "RGB"), (19, 8, "444"), (19, 8, "422"), (19, 10, "RGB"), (19, 10, "444"), (0, 8, "RGB"),
                (0, 8, "444"), (0, 8, "420"), (16, 8, "RGB"), (16, 8, "444"), (36, 8, "RGB"), (19, 8, "RGB")]:
    cf = dict(CFS)[k]
    q.append(row(f"L{i}_{b}_{k}" + ("_b" if (i, b, k) == (19, 8, "RGB") and any(l.startswith("L19_8_RGB\t") for l in q) else ""),
                 spec(i, b, cf), "levels"))
open(f"{O}/quick.tsv", "w").write("".join(q))
t2 = []
for i, m in enumerate(hc["modes"]):
    for b in (8, 10):
        for k, cf in CFS:
            t2.append(row(f"H{i}_{b}_{k}", spec(i, b, cf), "cam" if hmodel.expect(m, cf, b) else "t"))
open(f"{O}/t2.tsv", "w").write("".join(t2))
print(len(q), len(t2), sum(1 for l in t2 if "\tcam\t" in l))
