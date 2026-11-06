#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""cmp.py: native-DP colour matrix before (stock 15, k14/hdmi-formats/run-dp_0[0-3]-2*) vs after (15ycc1 chunks).
Prints per requested colour format: cases, accepted, bus format family as requested, camera GOOD; plus mismatches."""
import glob, os, re, sys
W = os.path.expanduser("~/orangepi5/work/_out")
FAM = {"100a": "RGB", "1018": "RGB", "2025": "444", "2016": "444", "2011": "422", "200d": "422", "2026": "420", "2027": "420"}
REQ = {"AUTO": "AUTO", "RGB": "RGB", "444": "444", "422": "422", "420": "420"}

def load(paths):
    rows = {}
    for p in paths:
        for i, line in enumerate(open(p)):
            c = line.rstrip("\n").split("\t")
            if i == 0 or len(c) < 17:
                continue
            rows[c[1]] = c
    return rows

before = load(sorted(glob.glob(f"{W}/k14/hdmi-formats/run-dp_0[0-3]-2*/fmt.tsv")))
after = load(sorted(glob.glob(f"{W}/k15/dp-ycc/run-15ycc1-dp_0[0-3].c*/fmt.tsv")))

def summary(rows, name):
    print(f"\n### {name} ({len(rows)} cases)\n")
    print("| requested | cases | commit accepted | rejected (errno) | bus format = request | camera GOOD (of accepted) |")
    print("|---|---|---|---|---|---|")
    bad = []
    for req in REQ:
        rs = [c for k, c in rows.items() if k.split("_")[2] == req]
        acc = [c for c in rs if c[5] == "1"]
        rej = [c for c in rs if c[5] != "1"]
        errs = sorted({c[6] for c in rej})
        match = [c for c in acc if req == "AUTO" or FAM.get(c[13].split("/")[0]) == req]
        good = [c for c in acc if c[16].startswith("GOOD")]
        print(f"| {req} | {len(rs)} | {len(acc)} | {len(rej)} {'/'.join(errs)} | {len(match)}/{len(acc)} | {len(good)}/{len(acc)} |")
        bad += [c for c in acc if c not in match or not c[16].startswith("GOOD")]
    return bad

b = summary(before, "before: stock 7.3.0-15")
a = summary(after, "after: 15ycc1 (k15-dpycc)")
print("\n### after: accepted cases that are not GOOD or not the requested format\n")
for c in a:
    print(f"- {c[1]}: busfmt {c[13]} cam {c[16]}")
missing = sorted(set(before) - set(after))
print(f"\ncases in before but not after: {len(missing)} {' '.join(missing[:20])}")
