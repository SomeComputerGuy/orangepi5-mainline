#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""hevc-rc-2 verdict: mechanical checks on results2/ (hevcrc.csv, wide.csv, sizes/, psnr/, trace/).

usage: verdict.py <results2 dir>
"new" = 16hrc2 (k16-hevcrc), "old" = 16rc2 (k16-rc2: driver HEVC RC, H.264 before the helper).
The reasons for each threshold are in ../STATE.md ("Criteria").

H.265 CBR, per case, new vs old:
  RATE   error over whole GOPs within -3.0 .. +1.0 %, and full-clip error within -3.0 .. +3.0 %
         (+5.0 % when the clip ends inside a GOP: the planned I excess of the unfinished GOP, up to
         3.9 % for 2.5 GOPs); below -3 % only as FLOOR (traced QP state at the minimum 10 in >= 50 %)
  PEAK   largest 1 s window <= the plan's 1 s peak with the I picture at 1.5x its largest share
         (I/P ratio 30, the MPP re-encode threshold): 1.395x at 1080p60/GOP 120, 1.66x at 2160p30/GOP 60
  PSNR   over WHOLE GOPs only (the unfinished last GOP is left out on both sides) and at EQUAL
         ACHIEVED BITRATE (old PSNR interpolated over log(kbps) from the old curve of the same clip):
         steady state (whole GOPs after the first) >= old - 0.05 dB; all whole GOPs >= old - 0.15 dB
         (start-up allowance for the first GOP); mean of the all-GOP differences of all cases >= 0
  SPIKE  first P after each later IDR <= 2.0x the median of the 10 P before it
  FPS    per case >= 0.85x old; median per resolution >= 0.95x old median
  KERNEL rows made on the expected kernels
H.264 regression (new vs old, rkvenc and H1): RATE as above; PSNR at equal bitrate (slope of the
  old H.265 curve of the same clip) >= old - 0.05 dB.
Wide H.265 (new): encode ok, all pictures decoded by FFmpeg without messages, no dmesg lines,
  PSNR-Y whole/left 4096/right >= 36 dB (CQP) or 32 dB (CBR).
A missing row is a FAIL. Last line: OVERALL PASS|FAIL.
"""
import csv
import math
import os
import re
import statistics
import sys

R = sys.argv[1]
REF1 = os.path.join(os.path.dirname(os.path.abspath(R)), "results")  # hevcrc-1 (15hrc1), report only
REV = {"old": "#16rc2", "new": "#16hrc2"}
HEVC = [(s, v) for s in ("bbb1080", "yacht1080") for v in (2000, 4000, 8000)] + \
       [(s, v) for s in ("bbb2160", "jelly2160") for v in (20000, 40000)]
H264 = [("bbb1080", "rkv", 4000), ("yacht1080", "rkv", 2000), ("bbb1080", "h1", 4000)]
WIDE = ["w4104-h265-cqp", "w5120-h265-cbr", "w8192-h265-cqp"]
RMAX = 30


def fps_of(s):
    return 60 if "1080" in s else 30


def load(path):
    rows = {}
    if os.path.exists(path):
        with open(path) as f:
            for r in csv.DictReader(f):
                rows[tuple(r[k] for k in ("label", "src", "codec", "enc", "value"))] = r
    return rows


def sizes(d, label, s, codec, enc, v):
    p = os.path.join(d, "sizes", f"sizes-{label}-{s}-{codec}-{enc}-{v}.txt")
    if not os.path.exists(p):
        return None
    out = []
    for line in open(p):
        f = line.strip().split(",")
        if f and f[0].isdigit():
            out.append((int(f[0]), "K" in (f[1] if len(f) > 1 else "")))
    return out


def stats(sz, s, v):
    """kbps full/steady, IDRs, gop, 1 s peak ratio"""
    fps = fps_of(s)
    b = [x[0] for x in sz]
    idr = [i for i, x in enumerate(sz) if x[1]]
    g = idr[1] - idr[0] if len(idr) > 1 else len(b)
    m = max(len(b) // g * g, 1)
    ss0 = g if m > g else 0
    kb = sum(b[:m]) * 8 * fps / m / 1000
    kss = sum(b[ss0:m]) * 8 * fps / (m - ss0) / 1000
    nom = v * 1000 / 8 / fps
    pk = max(sum(b[i:i + fps]) for i in range(0, len(b) - fps + 1)) / fps / nom
    return {"kbps": kb, "kss": kss, "ss0": ss0, "m": m, "gop": g, "n": len(b), "peak": pk,
            "partial": len(b) % g != 0}


def peak_limit(s, g):
    w = fps_of(s)
    p = g / (RMAX + g - 1)
    return (1.5 * RMAX * p + (w - 1) * p) / w


def psnr_of(d, label, s, codec, enc, v, ss0, m):
    p = os.path.join(d, "psnr", f"psnr-{label}-{s}-{codec}-{enc}-{v}.txt")
    if not os.path.exists(p):
        return None, None
    mse = [float(m.group(1)) for m in re.finditer(r"mse_y:([0-9.]+)", open(p).read())]
    if not mse:
        return None, None
    f = lambda a: 10 * math.log10(255 ** 2 / max(statistics.fmean(a), 1e-9))
    if len(mse) < m:
        return None, None
    return f(mse[:m]), f(mse[ss0:m])


def interp(pts, x):
    """pts [(log kbps, psnr)] sorted; linear in log(kbps), extrapolated with the end segment"""
    pts = sorted(p for p in pts if p[1] is not None)
    if len(pts) < 2:
        return None
    for i in range(len(pts) - 1):
        if x <= pts[i + 1][0] or i == len(pts) - 2:
            (x0, y0), (x1, y1) = pts[i], pts[i + 1]
            return y0 + (y1 - y0) * (x - x0) / (x1 - x0)


def floor_frac(s, v):
    p = os.path.join(R, "trace", f"trace-new-trace-{s}-h265-rkv-{v}.txt")
    if not os.path.exists(p):
        return None
    q = [int(m.group(1)) for m in re.finditer(r"qp: (-?\d+)/256", open(p, errors="replace").read())]
    return sum(1 for x in q if x <= 10 * 256) / len(q) if q else None


rows = load(os.path.join(R, "hevcrc.csv"))
info = {}
for label in ("old", "new"):
    for s, v in HEVC:
        r = rows.get((label, s, "h265", "rkv", str(v)))
        sz = sizes(R, label, s, "h265", "rkv", v)
        if not r or not sz:
            continue
        st = stats(sz, s, v)
        st["psnr"], st["pss"] = psnr_of(R, label, s, "h265", "rkv", v, st["ss0"], st["m"])
        st["row"] = r
        info[(label, s, v)] = st

fails = 0
print(f"== H.265 CBR: new ({REV['new']}) vs old ({REV['old']}); PSNR from per-picture MSE, "
      "dPSNR at equal achieved bitrate")
print(f"{'case':16s} {'err%':>5s} {'gop%':>5s} {'old%':>5s} {'peak':>5s} {'lim':>5s} {'psnrG':>7s} "
      f"{'dGOPs':>6s} {'dSS':>6s} {'spike':>5s} {'idrR':>5s} {'fps':>6s} {'oldfps':>6s}  checks")
dfull_all = []
for s, v in HEVC:
    n, o = info.get(("new", s, v)), info.get(("old", s, v))
    name = f"{s}:{v}"
    if not n or not o or n["psnr"] is None or o["psnr"] is None:
        print(f"{name:16s} MISSING (row, sizes or psnr stats) FAIL")
        fails += 1
        continue
    nr = n["row"]
    err, gerr = float(nr["err_pct"]), float(nr["gop_err_pct"])
    c = []
    hi = 5.0 if n["partial"] else 3.0
    if -3.0 <= gerr <= 1.0 and -3.0 <= err <= hi:
        c.append("RATE ok")
    else:
        ff = floor_frac(s, v)
        if gerr <= 1.0 and err < -3.0 and ff is not None and ff >= 0.5:
            c.append(f"RATE ok(FLOOR {ff:.0%})")
        else:
            c.append("RATE FAIL")
    lim = peak_limit(s, n["gop"])
    c.append("PEAK ok" if n["peak"] <= lim else "PEAK FAIL")
    of = [(math.log(info[("old", s, x)]["kbps"]), info[("old", s, x)]["psnr"])
          for y, x in HEVC if y == s and ("old", s, x) in info]
    oss = [(math.log(info[("old", s, x)]["kss"]), info[("old", s, x)]["pss"])
           for y, x in HEVC if y == s and ("old", s, x) in info]
    pf, pss = interp(of, math.log(n["kbps"])), interp(oss, math.log(n["kss"]))
    dfull = n["psnr"] - pf if pf is not None else None
    dss = n["pss"] - pss if pss is not None and n["pss"] is not None else None
    ok = dfull is not None and dss is not None and dfull >= -0.15 and dss >= -0.05
    c.append("PSNR ok" if ok else "PSNR FAIL")
    if dfull is not None:
        dfull_all.append(dfull)
    c.append("SPIKE ok" if float(nr["spike"]) <= 2.0 else "SPIKE FAIL")
    c.append("FPS ok" if float(nr["enc_fps"]) >= 0.85 * float(o["row"]["enc_fps"]) else "FPS FAIL")
    kok = nr["kernel"].endswith(REV["new"]) and o["row"]["kernel"].endswith(REV["old"])
    c.append("KERNEL ok" if kok else "KERNEL FAIL")
    fails += sum("FAIL" in x for x in c)
    fmt = lambda x: f"{x:6.3f}" if x is not None else "    NA"
    print(f"{name:16s} {err:5.1f} {gerr:5.1f} {float(o['row']['err_pct']):5.1f} {n['peak']:5.2f} {lim:5.2f} "
          f"{n['psnr']:7.3f} {fmt(dfull)} {fmt(dss)} {float(nr['spike']):5.2f} "
          f"{float(nr['idr_ratio_max']):5.2f} {float(nr['enc_fps']):6.1f} {float(o['row']['enc_fps']):6.1f}  "
          + " ".join(c))
mean_d = statistics.fmean(dfull_all) if dfull_all else None
ok = mean_d is not None and mean_d >= 0.0 and len(dfull_all) == len(HEVC)
fails += not ok
print(f"mean dGOPs over {len(dfull_all)} cases: "
      f"{'NA' if mean_d is None else f'{mean_d:+.3f}'} dB  {'ok' if ok else 'FAIL'}")
for res in ("1080", "2160"):
    fn = [float(info[("new", s, v)]["row"]["enc_fps"]) for s, v in HEVC if res in s and ("new", s, v) in info]
    fo = [float(info[("old", s, v)]["row"]["enc_fps"]) for s, v in HEVC if res in s and ("old", s, v) in info]
    ok = fn and fo and statistics.median(fn) >= 0.95 * statistics.median(fo)
    fails += not ok
    print(f"median fps {res}p: new {statistics.median(fn) if fn else 0:.1f} "
          f"old {statistics.median(fo) if fo else 0:.1f}  {'ok' if ok else 'FAIL'}")

print("== H.264 regression of the shared helper: new vs old")
for s, e, v in H264:
    n, o = rows.get(("new", s, "h264", e, str(v))), rows.get(("old", s, "h264", e, str(v)))
    name = f"{s}:{e}:{v}"
    if not n or not o:
        print(f"{name:22s} MISSING FAIL")
        fails += 1
        continue
    pn = os.path.join(R, "sizes", f"sizes-new-{s}-h264-{e}-{v}.txt")
    po = os.path.join(R, "sizes", f"sizes-old-{s}-h264-{e}-{v}.txt")
    same = os.path.exists(pn) and os.path.exists(po) and open(pn).read() == open(po).read()
    kn, ko = float(n["kbps"]), float(o["kbps"])
    # local slope dPSNR/dlog(kbps) of the old H.265 curve of the same clip
    pts = sorted((math.log(info[("old", s, x)]["kbps"]), info[("old", s, x)]["psnr"])
                 for y, x in HEVC if y == s and ("old", s, x) in info)
    slope = (pts[-1][1] - pts[0][1]) / (pts[-1][0] - pts[0][0]) if len(pts) > 1 else 0
    d = float(n["psnr_y"]) - float(o["psnr_y"]) - slope * math.log(kn / ko)
    err, gerr = float(n["err_pct"]), float(n["gop_err_pct"])
    rok = -3.0 <= gerr <= 1.0 and -3.0 <= err <= 5.0
    ok = rok and d >= -0.05 and len(pts) > 1
    fails += not ok
    print(f"{name:22s} kbps {kn:.0f} vs {ko:.0f} (err {err:+.1f}% gop {gerr:+.1f}%)  psnr {n['psnr_y']} vs "
          f"{o['psnr_y']}  dPSNR@rate {d:+.3f}  sizes identical: {same}  {'ok' if ok else 'FAIL'}")

print("== H.265 wider than 4096 (new)")
wrows = {}
if os.path.exists(os.path.join(R, "wide.csv")):
    with open(os.path.join(R, "wide.csv")) as f:
        for r in csv.DictReader(f):
            wrows[(r["label"], r["name"])] = r
for name in WIDE:
    r = wrows.get(("new", name))
    if not r:
        print(f"{name:16s} MISSING FAIL")
        fails += 1
        continue
    thr = 36.0 if r["rc"] == "cqp" else 32.0
    why = []
    if r["gst_rc"] != "0" or r["bytes"] == "0":
        why.append("encode failed rc=" + r["gst_rc"])
    if r["dec_frames"] != r["frames"]:
        why.append(f"decoded {r['dec_frames']}/{r['frames']}")
    if r["dec_errs"] != "0":
        why.append("ffmpeg messages=" + r["dec_errs"])
    if r["dmesg_bad"] != "0":
        why.append("dmesg lines=" + r["dmesg_bad"])
    if not r["kernel"].endswith(REV["new"]):
        why.append("kernel " + r["kernel"])
    for k in ("psnr_y", "psnr_left", "psnr_right"):
        if r[k] in ("NA", "inf"):
            continue
        try:
            bad = float(r[k]) < thr
        except ValueError:
            bad = True
        if bad:
            why.append(f"{k}={r[k]}<{thr:g}")
    fails += bool(why)
    print(f"{name:16s} {r['w']}x{r['h']} {r['rc']:>6s} psnr {r['psnr_y']} left {r['psnr_left']} "
          f"right {r['psnr_right']} fps {r['enc_fps']}  {'PASS' if not why else 'FAIL ' + '; '.join(why)}")

print("== reference only: hevcrc-1 15hrc1 (k15 base, same HEVC rate control as k16-venc8k)")
r1 = load(os.path.join(REF1, "hevcrc.csv"))
for s, v in HEVC:
    r = r1.get(("new", s, "h265", "rkv", str(v)))
    sz = sizes(REF1, "new", s, "h265", "rkv", v)
    n = info.get(("new", s, v))
    if r and sz:
        st = stats(sz, s, v)
        print(f"{s}:{v:<10d} hrc1 err {float(r['err_pct']):5.1f} peak {st['peak']:.2f} idrR {r['idr_ratio_max']}"
              f" psnr(ffmpeg) {r['psnr_y']}  | hrc2 peak {n['peak'] if n else float('nan'):.2f}"
              f" idrR {n['row']['idr_ratio_max'] if n else 'NA'} psnr(ffmpeg) {n['row']['psnr_y'] if n else 'NA'}")

print()
print(f"new (16hrc2): {fails} failed checks")
print(f"OVERALL {'PASS' if fails == 0 else 'FAIL'}")
