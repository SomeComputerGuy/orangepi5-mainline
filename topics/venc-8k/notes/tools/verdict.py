#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
#
# venc8k verdict: reads <results>/venc8k.csv, prints the tables and "OVERALL PASS|FAIL".
# Wide cases (new kernel): encode ok, all frames decoded by FFmpeg (software) with no decoder
# message, no dmesg line (iommu/fault/timeout/watchdog/venc/WARNING), PSNR-Y over the whole
# picture and over both the left 4096 columns and the columns right of 4096 >= threshold
# (CQP 26/28: 36 dB, CBR: 32 dB).
# Regression cases (1080p, 2160p, 4096 wide): new must be bit-identical to old (SAME), or for
# CBR within 0.05 dB PSNR-Y and 0.5% size (CLOSE); every new row also passes the wide checks.
import csv
import sys

R = sys.argv[1]
rows = {}
with open(R + "/venc8k.csv") as f:
    for r in csv.DictReader(f):
        rows[(r["label"], r["name"])] = r


def num(v):
    try:
        return float(v)
    except (TypeError, ValueError):
        return None


def check(r):
    thr = 36.0 if r["rc"] == "cqp" else 32.0
    why = []
    if r["gst_rc"] != "0" or r["bytes"] == "0":
        why.append("encode failed rc=" + r["gst_rc"])
    if r["dec_frames"] != r["frames"]:
        why.append("decoded %s/%s frames" % (r["dec_frames"], r["frames"]))
    if r["dec_errs"] != "0":
        why.append("ffmpeg messages=" + r["dec_errs"])
    if r["dmesg_bad"] != "0":
        why.append("dmesg lines=" + r["dmesg_bad"])
    for k in ("psnr_y", "psnr_left", "psnr_right"):
        if r[k] == "NA":
            continue
        v = num(r[k])
        if r[k] == "inf":
            continue
        if v is None or v < thr:
            why.append("%s=%s<%g" % (k, r[k], thr))
    return why


ok = True
print("== wide and regression cases on the new kernel ==")
print("%-16s %-11s %4s %-6s %7s %7s %7s %7s %s" %
      ("case", "size", "frm", "rc", "psnrY", "left", "right", "fps", "verdict"))
best = {"h264": None, "h265": None}
for (label, name), r in sorted(rows.items()):
    if label != "new":
        continue
    why = check(r)
    v = "PASS" if not why else "FAIL " + "; ".join(why)
    if why:
        ok = False
    elif int(r["w"]) > 4096:
        px = int(r["w"]) * 10000 + int(r["h"])
        if best[r["codec"]] is None or px > best[r["codec"]][0]:
            best[r["codec"]] = (px, r["w"] + "x" + r["h"])
    print("%-16s %-11s %4s %-6s %7s %7s %7s %7s %s" %
          (name, r["w"] + "x" + r["h"], r["frames"], r["rc"], r["psnr_y"], r["psnr_left"],
           r["psnr_right"], r["enc_fps"], v))

print()
print("== regression: new (15v8k1) vs old (15hrc1) ==")
for (label, name), o in sorted(rows.items()):
    if label != "old":
        continue
    n = rows.get(("new", name))
    if not n:
        print("%-16s MISSING on new" % name)
        ok = False
        continue
    if check(o):
        print("%-16s old run itself failed: %s" % (name, "; ".join(check(o))))
        ok = False
        continue
    if n["md5"] == o["md5"]:
        v = "SAME"
    else:
        po, pn = num(o["psnr_y"]), num(n["psnr_y"])
        bo, bn = num(o["bytes"]), num(n["bytes"])
        close = (po is not None and pn is not None and abs(pn - po) <= 0.05 and
                 bo and bn is not None and abs(bn - bo) / bo <= 0.005)
        v = "CLOSE" if close and o["rc"] != "cqp" else "DIFF"
        if v == "DIFF":
            ok = False
    print("%-16s bytes %s -> %s  psnr %s -> %s  fps %s -> %s  %s" %
          (name, o["bytes"], n["bytes"], o["psnr_y"], n["psnr_y"], o["enc_fps"], n["enc_fps"], v))

expected_new = 9 + 16
got_new = sum(1 for (l, _) in rows if l == "new")
if got_new < expected_new:
    print("\nnew rows: %d of %d expected" % (got_new, expected_new))
    ok = False
print()
for c in ("h264", "h265"):
    print("largest passing wide size %s: %s" % (c, best[c][1] if best[c] else "none"))
print("OVERALL " + ("PASS" if ok else "FAIL"))
