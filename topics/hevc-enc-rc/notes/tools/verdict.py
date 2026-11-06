#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""hevc-rc verdict: mechanical checks on results/hevcrc.csv (+ sizes/, trace/).

usage: verdict.py <results dir>
Variant "new" (15hrc1) decides the overall PASS/FAIL; "d2" (15hrc1b) is reported only.
Checks per H.265 case of a variant, against the same case of "old" (15h1rc2):
  RATE   |err_pct| <= 3.0, or err_pct < -3.0 with the QP state at the QP minimum (10)
         in >= 50% of the traced pictures (FLOOR: the content needs less than the
         bitrate even at the lowest QP)
  PSNR   psnr_y >= old psnr_y - 0.05 dB
  SPIKE  first P picture after each later IDR <= 2.0x the median of the 10 P before it
  FPS    enc_fps >= 0.95 * old enc_fps
  KERNEL the row was made on the expected kernel
H.264 regression ("new" vs "old", rkvenc and H1): kbps within 0.3%, PSNR within 0.05 dB.
A missing row is a FAIL.
"""
import csv, os, re, sys

R = sys.argv[1]
REV = {"old": "#15h1rc2", "new": "#15hrc1", "d2": "#15hrc1b"}
HEVC = [(s, v) for s in ("bbb1080", "yacht1080") for v in (2000, 4000, 8000)] + \
       [(s, v) for s in ("bbb2160", "jelly2160") for v in (20000, 40000)]
H264 = [("bbb1080", "rkv", 4000), ("yacht1080", "rkv", 2000), ("bbb1080", "h1", 4000)]

rows = {}
with open(os.path.join(R, "hevcrc.csv")) as f:
    for r in csv.DictReader(f):
        rows[(r["label"], r["src"], r["codec"], r["enc"], int(r["value"]))] = r


def floor_frac(label, src, val):
    p = os.path.join(R, "trace", f"trace-{label}-trace-{src}-h265-rkv-{val}.txt")
    if not os.path.exists(p):
        return None
    q = [int(m.group(1)) for m in re.finditer(r"qp: (-?\d+)/256", open(p, errors="replace").read())]
    return sum(1 for x in q if x <= 10 * 256) / len(q) if q else None


def variant(label):
    fails = 0
    print(f"== {label} ({REV[label]}) vs old ({REV['old']}): H.265 CBR")
    print(f"{'case':22s} {'err%':>6s} {'gop%':>6s} {'old%':>6s} {'psnr':>7s} {'oldpsnr':>7s} "
          f"{'spike':>5s} {'idrR':>5s} {'fps':>6s} {'oldfps':>6s}  checks")
    for s, v in HEVC:
        n, o = rows.get((label, s, "h265", "rkv", v)), rows.get(("old", s, "h265", "rkv", v))
        name = f"{s}:{v}"
        if not n or not o:
            print(f"{name:22s} MISSING ({'new' if not n else 'old'} row) FAIL")
            fails += 1
            continue
        err = float(n["err_pct"])
        ff = floor_frac(label, s, v)
        c = []
        if abs(err) <= 3.0:
            c.append("RATE ok")
        elif err < -3.0 and ff is not None and ff >= 0.5:
            c.append(f"RATE ok(FLOOR {ff:.0%})")
        else:
            c.append("RATE FAIL" + (f"(floor {ff:.0%})" if ff is not None else ""))
        c.append("PSNR ok" if float(n["psnr_y"]) >= float(o["psnr_y"]) - 0.05 else "PSNR FAIL")
        c.append("SPIKE ok" if float(n["spike"]) <= 2.0 else "SPIKE FAIL")
        c.append("FPS ok" if float(n["enc_fps"]) >= 0.95 * float(o["enc_fps"]) else "FPS FAIL")
        okk = n["kernel"].endswith(REV[label]) and o["kernel"].endswith(REV["old"])
        c.append("KERNEL ok" if okk else "KERNEL FAIL")
        fails += sum("FAIL" in x for x in c)
        print(f"{name:22s} {err:6.1f} {float(n['gop_err_pct']):6.1f} {float(o['err_pct']):6.1f} "
              f"{float(n['psnr_y']):7.3f} {float(o['psnr_y']):7.3f} {float(n['spike']):5.2f} "
              f"{float(n['idr_ratio_max']):5.2f} {float(n['enc_fps']):6.1f} {float(o['enc_fps']):6.1f}  "
              + " ".join(c))
    return fails


def h264():
    fails = 0
    print("== H.264 regression of the shared helper: new vs old")
    for s, e, v in H264:
        n, o = rows.get(("new", s, "h264", e, v)), rows.get(("old", s, "h264", e, v))
        name = f"{s}:{e}:{v}"
        if not n or not o:
            print(f"{name:22s} MISSING FAIL")
            fails += 1
            continue
        same = None
        pn = os.path.join(R, "sizes", f"sizes-new-{s}-h264-{e}-{v}.txt")
        po = os.path.join(R, "sizes", f"sizes-old-{s}-h264-{e}-{v}.txt")
        if os.path.exists(pn) and os.path.exists(po):
            same = open(pn).read() == open(po).read()
        kn, ko = float(n["kbps"]), float(o["kbps"])
        ok = abs(kn - ko) <= 0.003 * ko and abs(float(n["psnr_y"]) - float(o["psnr_y"])) <= 0.05
        fails += not ok
        print(f"{name:22s} kbps {kn:.0f} vs {ko:.0f}  psnr {n['psnr_y']} vs {o['psnr_y']}  "
              f"sizes identical: {same}  {'ok' if ok else 'FAIL'}")
    return fails


fn = variant("new")
fh = h264()
print()
fd = variant("d2")
print()
print(f"new (15hrc1): {fn + fh} failed checks -> {'PASS' if fn + fh == 0 else 'FAIL'}")
print(f"d2 (15hrc1b, comparison only): {fd} failed checks")
print(f"OVERALL {'PASS' if fn + fh == 0 else 'FAIL'}")
