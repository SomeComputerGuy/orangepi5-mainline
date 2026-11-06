#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0
"""host: compare TEST_ONLY accept/refuse of HDMI-only configs with hmodel.  t1cmp.py <kms-list.json> <results1.tsv|p1.jsonl>"""
import json, sys
sys.path.insert(0, __file__.rsplit("/", 1)[0])
import hmodel
lst = json.load(open(sys.argv[1]))
hc = next(c for c in lst["connectors"] if c["name"] == "HDMI-A-1")
CF = {"AUTO": "AUTO", "RGB": "RGB", "444": "YUV 4:4:4", "422": "YUV 4:2:2", "420": "YUV 4:2:0"}
res = {}
p = sys.argv[2]
if p.endswith(".tsv"):
    L = open(p).read().splitlines()
    hd = L[0].split("\t")
    for l in L[1:]:
        r = dict(zip(hd, l.split("\t")))
        if r.get("kind") == "hdmi-only":
            res[r["hdmi"]] = r["ok"] == "1"
else:
    for l in open(p):
        r = json.loads(l)
        res[r["id"].split("+")[0]] = r["ok"]
n = bad = 0
for cid, ok in sorted(res.items()):
    if not cid.startswith("H"):
        continue
    i, b, cf = cid[1:].split("_")
    m = hc["modes"][int(i)]
    e = hmodel.expect(m, CF[cf], int(b))
    n += 1
    if bool(e) != ok:
        bad += 1
        print(f"MISMATCH {cid} {m['name']}@{m['vrefresh']} clk={m['clock']} vic={hmodel.vic_of(m)} kernel={'ACCEPT' if ok else 'REFUSE'} model={e}")
print(f"{n} configs, {bad} mismatches")
