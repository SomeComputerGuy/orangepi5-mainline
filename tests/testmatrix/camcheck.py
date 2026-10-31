#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0
"""Webcam picture check (pure Python; GStreamer only for capture and JPEG decode).

  camcheck.py find                         print the webcam's /dev/videoN (name match, capture node)
  camcheck.py capture <prefix>             grab frames -> <prefix>.jpg (1080p, for people) + <prefix>.rgb (small RGB)
  camcheck.py calib <white> <black> <out.json>   screen quadrilateral + levels from full-white / full-black frames
  camcheck.py classify <calib.json> <img> <pattern> [code]   -> JSON {verdict: GOOD|BLACK|FLAT|SCRAMBLED|WRONGCASE}
  camcheck.py rescore <run dir>            re-classify every saved frame of a display-matrix run (see README)
  camcheck.py selftest                     synthetic frames, incl. a steep perspective view
Images: .rgb (raw RGB, size inferred) or .jpg (decoded with gst-launch when available).

The camera may look at the screen from any angle: calibration finds the screen as the largest bright region of
(white - black), takes its 4 corners and computes a homography; every capture is warped to a canonical
rectangle and judged against the pattern layout there. The classifier is self-normalising: per channel it
rescales the bar means between the darkest and the brightest bar (auto exposure / white balance do not matter);
the black 8th bar is measured inside the screen, so it cannot blend into the bezel.
Patterns: "bars" (kmsctl.py: 8 bars, 16 stripes, 16-bit case code), "smpte" (modetest / videotestsrc).
"""
import json, os, re, shutil, subprocess, sys, tempfile

SIZES = [(192, 108), (384, 216), (320, 180), (640, 360)]
CAP_W, CAP_H = 384, 216                      # size of new captures
GW, GH = 128, 72                             # canonical (warped) grid
CAM_NAME = os.environ.get("CAM_NAME", "Aluratek")
TH = {"bars_min": 0.87, "stripes_min": 0.85, "black_frac": 0.12, "min_contrast": 0.25, "texture_min": 0.08,
      "gap_min": 0.04}


# ---------------------------------------------------------------- I/O
def find():
    base = "/sys/class/video4linux"
    for d in sorted(os.listdir(base), key=lambda s: int(s[5:]) if s[5:].isdigit() else 999):
        try:
            name = open(f"{base}/{d}/name").read()
            idx = open(f"{base}/{d}/index").read().strip()
        except OSError:
            continue
        if CAM_NAME in name and idx == "0":
            return "/dev/" + d
    return ""


def capture(prefix, dev=None, frames=None):
    dev = dev or os.environ.get("CAM_DEV") or find()
    if not dev:
        raise RuntimeError(f"no webcam matching {CAM_NAME!r}")
    frames = frames or int(os.environ.get("CAM_FRAMES", "30"))
    caps = os.environ.get("CAM_CAPS", "image/jpeg,width=1920,height=1080")
    p = (f"v4l2src device={dev} num-buffers={frames} ! {caps} ! tee name=t "
         f"t. ! queue ! multifilesink location={prefix}.jpg "
         f"t. ! queue ! jpegdec ! videoconvert ! videoscale ! "
         f"video/x-raw,format=RGB,width={CAP_W},height={CAP_H},pixel-aspect-ratio=1/1 ! multifilesink location={prefix}.rgb")
    r = subprocess.run(["gst-launch-1.0", "-q"] + p.split(), capture_output=True, text=True, timeout=60)
    if r.returncode or not os.path.exists(prefix + ".rgb"):
        raise RuntimeError(f"capture failed: {r.stderr.strip()[-300:]}")
    return prefix + ".rgb"


def load(path):
    """-> (w, h, bytes RGB)"""
    if path.endswith(".jpg"):
        rgb = path[:-4] + ".rgb"
        if shutil.which("gst-launch-1.0"):
            with tempfile.NamedTemporaryFile(suffix=".rgb") as t:
                subprocess.run(["gst-launch-1.0", "-q", "filesrc", f"location={path}", "!", "jpegdec", "!", "videoconvert",
                                "!", "videoscale", "!", f"video/x-raw,format=RGB,width={CAP_W},height={CAP_H}", "!",
                                "filesink", f"location={t.name}"], capture_output=True, timeout=60)
                b = open(t.name, "rb").read()
            if len(b) == CAP_W * CAP_H * 3:
                return CAP_W, CAP_H, b
        if os.path.exists(rgb):
            return load(rgb)
        raise RuntimeError(f"{path}: cannot decode (no gst-launch-1.0) and no .rgb next to it")
    b = open(path, "rb").read()
    for w, h in SIZES:
        if len(b) == w * h * 3:
            return w, h, b
    for w, h in SIZES:   # several frames appended: take the last one
        if len(b) % (w * h * 3) == 0 and len(b):
            return w, h, b[-w * h * 3:]
    raise RuntimeError(f"{path}: unknown frame size {len(b)}")


def lum_at(img, x, y):
    w, _, b = img
    o = 3 * (y * w + x)
    return (b[o] * 299 + b[o + 1] * 587 + b[o + 2] * 114) / 1000.0


# ---------------------------------------------------------------- geometry
def solve(a, y):
    n = len(y)
    m = [row[:] + [y[i]] for i, row in enumerate(a)]
    for c in range(n):
        p = max(range(c, n), key=lambda r: abs(m[r][c]))
        m[c], m[p] = m[p], m[c]
        if abs(m[c][c]) < 1e-12:
            raise RuntimeError("degenerate screen quadrilateral")
        for r in range(n):
            if r != c:
                f = m[r][c] / m[c][c]
                m[r] = [x - f * z for x, z in zip(m[r], m[c])]
    return [m[i][n] / m[i][i] for i in range(n)]


def homography(quad):
    """unit square (0,0),(1,0),(1,1),(0,1) -> quad TL,TR,BR,BL (camera coords, fractions)"""
    a, y = [], []
    for (u, v), (x, yy) in zip(((0, 0), (1, 0), (1, 1), (0, 1)), quad):
        a.append([u, v, 1, 0, 0, 0, -u * x, -v * x])
        y.append(x)
        a.append([0, 0, 0, u, v, 1, -u * yy, -v * yy])
        y.append(yy)
    return solve(a, y) + [1.0]


def apply_h(H, u, v):
    d = H[6] * u + H[7] * v + H[8]
    return (H[0] * u + H[1] * v + H[2]) / d, (H[3] * u + H[4] * v + H[5]) / d


def warp(img, quad, gw=GW, gh=GH):
    """canonical gw x gh grid of RGB tuples (bilinear) of the screen"""
    w, h, b = img
    H = homography(quad)
    out = []
    for j in range(gh):
        for i in range(gw):
            x, y = apply_h(H, (i + .5) / gw, (j + .5) / gh)
            x, y = min(max(x * w - .5, 0), w - 1.001), min(max(y * h - .5, 0), h - 1.001)
            x0, y0 = int(x), int(y)
            fx, fy = x - x0, y - y0
            px = []
            for c in range(3):
                o = 3 * (y0 * w + x0) + c
                top = b[o] * (1 - fx) + b[o + 3] * fx
                bot = b[o + 3 * w] * (1 - fx) + b[o + 3 * w + 3] * fx
                px.append(top * (1 - fy) + bot * fy)
            out.append(px)
    return out


def quad_of(img_w, img_k):
    """TL, TR, BR, BL corners (fractions) of the largest bright component of white - black"""
    w, h, _ = img_w
    diff = [lum_at(img_w, x, y) - lum_at(img_k, x, y) for y in range(h) for x in range(w)]
    mx = max(diff)
    if mx < 40:
        raise RuntimeError(f"white/black frames differ by only {mx:.0f}: camera not on the monitor?")
    srt = sorted(diff)
    thr = max(mx * 0.35, (srt[len(srt) // 10] + mx) / 2 * 0.6)
    mask = bytearray(1 if d > thr else 0 for d in diff)
    best, seen = [], bytearray(w * h)
    for s in range(w * h):
        if mask[s] and not seen[s]:
            comp, st = [], [s]
            seen[s] = 1
            while st:
                p = st.pop()
                comp.append(p)
                x, y = p % w, p // w
                for q in ((p - 1) if x else -1, (p + 1) if x < w - 1 else -1, p - w, p + w):
                    if 0 <= q < w * h and mask[q] and not seen[q]:
                        seen[q] = 1
                        st.append(q)
            if len(comp) > len(best):
                best = comp
    if len(best) < w * h * 0.02:
        raise RuntimeError("screen region too small")
    pts = [((p % w + .5) / w, (p // w + .5) / h) for p in best]
    # extreme points along the diagonals (aspect-weighted) are the corners of a convex quadrilateral
    ax = w / h
    tl = min(pts, key=lambda p: p[0] * ax + p[1])
    br = max(pts, key=lambda p: p[0] * ax + p[1])
    tr = max(pts, key=lambda p: p[0] * ax - p[1])
    bl = min(pts, key=lambda p: p[0] * ax - p[1])
    # push the corners out by half a pixel so the quad covers the screen edge pixels
    cx, cy = sum(p[0] for p in (tl, tr, br, bl)) / 4, sum(p[1] for p in (tl, tr, br, bl)) / 4
    q = []
    for x, y in (tl, tr, br, bl):
        dx, dy = x - cx, y - cy
        n = max((dx * dx + dy * dy) ** .5, 1e-9)
        q.append([x + dx / n * .5 / w, y + dy / n * .5 / h])
    return q, len(best) / (w * h)


def calib(white, black):
    iw, ik = load(white), load(black)
    if iw[:2] != ik[:2]:
        raise RuntimeError("white/black frames differ in size")
    quad, area = quad_of(iw, ik)
    gw_, gk = warp(iw, quad, 64, 36), warp(ik, quad, 64, 36)
    wl = sum(sum(p) / 3 for p in gw_) / len(gw_)
    kl = sum(sum(p) / 3 for p in gk) / len(gk)
    xs, ys = [p[0] for p in quad], [p[1] for p in quad]
    cal = {"quad": quad, "area": round(area, 3), "white_lum": wl, "black_lum": kl,
           "box": [round(min(xs) * iw[0]), round(min(ys) * iw[1]), round(max(xs) * iw[0]), round(max(ys) * iw[1])],
           "thresholds": dict(TH)}
    cal["thresholds"]["texture_min"] = max(TH["texture_min"], 4 * texture(gk) / max(wl - kl, 1))
    if wl - kl < 30:
        raise RuntimeError(f"screen white {wl:.0f} vs black {kl:.0f}: too little contrast")
    return cal


# ---------------------------------------------------------------- classification on the canonical grid
def region(g, fx0, fy0, fx1, fy1, flip=False, inner=0.5, gw=GW, gh=GH):
    if flip:
        fx0, fx1 = 1 - fx1, 1 - fx0
    mx, my = (fx1 - fx0) * (1 - inner) / 2, (fy1 - fy0) * (1 - inner) / 2
    x0, x1 = int((fx0 + mx) * gw), max(int((fx1 - mx) * gw), int((fx0 + mx) * gw) + 1)
    y0, y1 = int((fy0 + my) * gh), max(int((fy1 - my) * gh), int((fy0 + my) * gh) + 1)
    s, n = [0.0, 0.0, 0.0], 0
    for y in range(y0, min(y1, gh)):
        for x in range(x0, min(x1, gw)):
            p = g[y * gw + x]
            s[0] += p[0]
            s[1] += p[1]
            s[2] += p[2]
            n += 1
    return [v / max(n, 1) for v in s]


def texture(g, gw=None):
    """mean |neighbour difference| of luminance on a canonical grid"""
    gw = gw or (GW if len(g) == GW * GH else 64)
    gh = len(g) // gw
    L = [p[0] * .299 + p[1] * .587 + p[2] * .114 for p in g]
    s, n = 0.0, 0
    for y in range(1, gh - 1):
        for x in range(1, gw - 1):
            i = y * gw + x
            s += abs(L[i] - L[i + 1]) + abs(L[i] - L[i + gw])
            n += 2
    return s / max(n, 1)


ON = {"W": (1, 1, 1), "Y": (1, 1, 0), "C": (0, 1, 1), "G": (0, 1, 0), "M": (1, 0, 1), "R": (1, 0, 0),
      "B": (0, 0, 1), "K": (0, 0, 0)}


def layout(pattern):
    """(bars [(fx0,fy0,fx1,fy1,colour)], stripes [(..., on)], code cells [(...)])"""
    if pattern == "smpte":   # libdrm util/pattern.c (and videotestsrc): top 2/3 = 7 bars at 75 %, then reverse cells
        bars = [(i / 7, 0, (i + 1) / 7, 6 / 9, c) for i, c in enumerate("WYCGMRB")]
        bars += [(i / 7, 6 / 9, (i + 1) / 7, 3 / 4, c) for i, c in enumerate("BKMKCKW")]
        return bars, [], []
    bars = [(i / 8, 0, (i + 1) / 8, .55, c) for i, c in enumerate("WYCGMRBK")]
    stripes = [(i / 16, .55, (i + 1) / 16, .70, i % 2 == 0) for i in range(16)]
    cells = [((i % 8) / 8, .70 if i < 8 else .85, (i % 8 + 1) / 8, .85 if i < 8 else 1.0) for i in range(16)]
    return bars, stripes, cells


def code_bits(code):  # same as kmsctl.code_bits
    code &= 0xfff
    return [(code >> i) & 1 for i in range(12)] + [((code * 7 + 3) >> i) & 1 for i in range(4)]


def score(g, cal, pattern, flip):
    bars, stripes, cells = layout(pattern)
    means = [region(g, *b[:4], flip) for b in bars]
    lo = [min(m[c] for m in means) for c in range(3)]
    hi = [max(m[c] for m in means) for c in range(3)]
    rng = max(cal["white_lum"] - cal["black_lum"], 1)
    contrast = min(hi[c] - lo[c] for c in range(3)) / rng
    # rank-based per channel: the pattern says how many regions have each channel on, so the brightest k are
    # "on". This survives the camera's desaturation/over-exposure (a yellow bar can read B=212 of 255) where
    # any fixed threshold fails; a wrong picture still gets the positions wrong.
    on = [set() for _ in range(3)]
    gap = 1.0
    for c in range(3):
        k = sum(ON[b[4]][c] for b in bars)
        order = sorted(range(len(bars)), key=lambda i: -means[i][c])
        on[c] = set(order[:k])
        if 0 < k < len(bars):
            gap = min(gap, (means[order[k - 1]][c] - means[order[k]][c]) / max(hi[c] - lo[c], 1e-6))
    ok = sum(tuple(int(i in on[c]) for c in range(3)) == ON[b[4]] for i, b in enumerate(bars))
    r = {"flip": flip, "bars": ok / len(bars), "contrast": round(contrast, 3), "gap": round(gap, 3)}
    if stripes:
        sl = [sum(region(g, *s[:4], flip, inner=0.4)) / 3 for s in stripes]
        a, b = min(sl), max(sl)
        r["stripes"] = sum(((v - a) / max(b - a, 1e-6) > 0.5) == s[4] for v, s in zip(sl, stripes)) / len(stripes)
        cl = [sum(region(g, *c, flip, inner=0.4)) / 3 for c in cells]
        r["code_bits"] = [int((v - a) / max(b - a, 1e-6) > 0.5) for v in cl]
    return r


def screen_stats(img, cal):
    """(level 0..1 between calibrated black and white, texture relative to that range) of the screen"""
    g = warp(img, cal["quad"]) if "quad" in cal else None
    if g is None:
        raise RuntimeError("calibration has no screen quadrilateral (old calib.json): rerun calibration")
    rng = max(cal["white_lum"] - cal["black_lum"], 1)
    lvl = sum(sum(p) / 3 for p in g) / len(g)
    return (lvl - cal["black_lum"]) / rng, texture(g) / rng


def classify(cal, img, pattern, code=None):
    th = cal.get("thresholds", TH)
    g = warp(img, cal["quad"])
    rng = max(cal["white_lum"] - cal["black_lum"], 1)
    best = max((score(g, cal, pattern, f) for f in (False, True)), key=lambda r: r["bars"] + r.get("stripes", 0))
    best["level"] = round((sum(sum(p) / 3 for p in g) / len(g) - cal["black_lum"]) / rng, 3)
    best["texture"] = round(texture(g) / rng, 3)
    if best["contrast"] < th["min_contrast"]:
        if best["texture"] >= th.get("texture_min", 0.08):
            best["verdict"] = "SCRAMBLED"      # structure, but not the bars (noise, stripes, tearing)
        else:
            best["verdict"] = "BLACK" if best["level"] < th["black_frac"] else "FLAT"
    elif best["bars"] >= th["bars_min"] and best.get("stripes", 1) >= th["stripes_min"] and \
            best["gap"] >= th.get("gap_min", 0.04):
        best["verdict"] = "GOOD"
        if code is not None and "code_bits" in best:
            best["code_ok"] = best["code_bits"] == code_bits(code)
            if not best["code_ok"]:
                best["verdict"] = "WRONGCASE"
    else:
        best["verdict"] = "SCRAMBLED"
    return best


def cam_summary(r):
    return f"{r['verdict']}:bars={r['bars']:.2f},st={r.get('stripes', 1):.2f},c={r['contrast']:.2f}"


# ---------------------------------------------------------------- offline re-score of a display-matrix run
def frame(d):
    for n in ("cam.jpg", "cam.rgb"):
        if os.path.exists(f"{d}/{n}") and (n == "cam.rgb" or shutil.which("gst-launch-1.0")):
            return f"{d}/{n}"
    return f"{d}/cam.rgb" if os.path.exists(f"{d}/cam.rgb") else None


def rescore(run):
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import dmatrix
    info, cases = json.load(open(f"{run}/cases.json"))
    byidx = {c["idx"]: c for c in cases}
    white = next((c for c in cases if c["group"] == "calib" and c["pattern"] == "white"), None)
    black = next((c for c in cases if c["group"] == "calib" and c["pattern"] == "black"), None)
    if not (white and black):
        sys.exit("run has no white/black calibration cases")
    cal = calib(frame(f"{run}/case/{white['idx']:04d}"), frame(f"{run}/case/{black['idx']:04d}"))
    json.dump(cal, open(f"{run}/calib-rescore.json", "w"), indent=1)
    print(f"calibration: quad={[[round(x, 3) for x in p] for p in cal['quad']]} area={cal['area']} "
          f"white={cal['white_lum']:.0f} black={cal['black_lum']:.0f}")
    for n in ("results.tsv", "results-final.tsv", "camera-spans.json"):
        o = f"{run}/{n}".replace(".tsv", ".orig.tsv").replace(".json", ".orig.json")
        if os.path.exists(f"{run}/{n}") and not os.path.exists(o):
            shutil.copy(f"{run}/{n}", o)
    src = f"{run}/results.orig.tsv"
    lines = open(src).read().splitlines()
    cols = lines[0].split("\t")
    out, changed, calib_ok = [lines[0]], 0, True
    for line in lines[1:]:
        r = dict(zip(cols, line.split("\t")))
        c = byidx.get(int(r["idx"])) if r["idx"].isdigit() else None
        f = frame(f"{run}/case/{int(r['idx']):04d}") if c else None
        if c and f and c["pattern"] not in ("white", "black") and r.get("cam") not in ("", "-"):
            res = classify(cal, load(f), c["pattern"], c["idx"] if c["pattern"] == "bars" else None)
            new = cam_summary(res)
            rs = [x for x in r["reasons"].split("; ") if x and not x.startswith("webcam:")]
            if "expect" in c:
                match = (res["verdict"] == "GOOD") == (c["expect"] == "GOOD")
                calib_ok &= match
                r["verdict"] = "CALIB-" + ("MATCH" if match else "MISMATCH")
            else:
                if res["verdict"] != "GOOD":
                    rs.append(f"webcam: picture {res['verdict']}")
                if r["verdict"] in ("PASS", "FAIL", "UNTRUSTED"):
                    r["verdict"] = "FAIL" if rs else "PASS"
            changed += new != r["cam"]
            r["cam"], r["reasons"] = new, "; ".join(rs)
        out.append("\t".join(r.get(k, "") for k in cols))
    open(f"{run}/results.tsv", "w").write("\n".join(out) + "\n")
    # controls: re-judge them too; the old spans came from the old classifier and are dropped
    ctl = sorted(d for d in os.listdir(f"{run}/ctl")) if os.path.isdir(f"{run}/ctl") else []
    cv = []
    ctrl = next((c for c in cases if c.get("expect") == "GOOD"), None)
    for d in ctl:
        f = frame(f"{run}/ctl/{d}")
        if d.endswith("-control") and f and ctrl:
            cv.append(classify(cal, load(f), ctrl["pattern"], ctrl["idx"])["verdict"])
    if os.path.exists(f"{run}/camera-spans.json"):
        json.dump({"spans": [], "last_good": -1, "rescored": True}, open(f"{run}/camera-spans.json", "w"))
    if not calib_ok:
        print("WARNING: known-result cases do not match after rescoring: camera verdicts are not trustworthy")
    dmatrix.summarize(run, cases)
    print(f"rescored {changed} camera verdicts; controls: {', '.join(cv) or 'none'}; known results "
          f"{'match' if calib_ok else 'MISMATCH'}; originals kept as results.orig.tsv / results-final.orig.tsv")


# ---------------------------------------------------------------- synthetic self test
def synth(fn, quad=((20, 10), (172, 10), (172, 96), (20, 96)), w=192, h=108):
    """fn(fx, fy) -> rgb on the screen; the screen is the quadrilateral 'quad' (pixels) on a dim background"""
    H = homography([[x / w, y / h] for x, y in quad])
    # inverse mapping: camera pixel -> screen fraction (invert the 3x3)
    a, b_, c, d, e, f, g, h_, i = H
    det = a * (e * i - f * h_) - b_ * (d * i - f * g) + c * (d * h_ - e * g)
    inv = [(e * i - f * h_) / det, (c * h_ - b_ * i) / det, (b_ * f - c * e) / det,
           (f * g - d * i) / det, (a * i - c * g) / det, (c * d - a * f) / det,
           (d * h_ - e * g) / det, (b_ * g - a * h_) / det, (a * e - b_ * d) / det]
    buf = bytearray(w * h * 3)
    for y in range(h):
        for x in range(w):
            u, v = apply_h(inv, (x + .5) / w, (y + .5) / h)
            px = fn(u, v) if 0 <= u < 1 and 0 <= v < 1 else (25, 25, 30)
            buf[3 * (y * w + x):3 * (y * w + x) + 3] = bytes(int(max(0, min(255, cc))) for cc in px)
    return (w, h, bytes(buf))


def selftest():
    import random
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import kmsctl  # pattern source of truth
    rects = kmsctl.pattern_rects("bars", 3840, 2160, 1234)

    def bars(fx, fy, gain=200, off=30, cast=(1, .9, 1.1)):
        for x0, y0, x1, y1, rgb in rects:
            if x0 <= fx * 3840 < x1 and y0 <= fy * 2160 < y1:
                return [off + gain * c * k for c, k in zip(rgb, cast)]
        return (0, 0, 0)
    rnd = random.Random(1)
    bad = 0
    for qname, quad in (("frontal", ((20, 10), (172, 10), (172, 96), (20, 96))),
                        ("steep", ((34, 20), (152, 12), (188, 83), (7, 86)))):   # like the wall TV from below-left
        def save(name, img):
            p = f"/tmp/camst-{qname}-{name}.rgb"
            open(p, "wb").write(img[2])
            return p
        cal = calib(save("white", synth(lambda fx, fy: (230, 230, 230), quad)),
                    save("black", synth(lambda fx, fy: (35, 35, 38), quad)))
        cases = {
            "good": (synth(bars, quad), "GOOD"),
            "good-dim": (synth(lambda fx, fy: bars(fx, fy, gain=90, off=50), quad), "GOOD"),
            "mirrored": (synth(lambda fx, fy: bars(1 - fx, fy), quad), "GOOD"),
            "black": (synth(lambda fx, fy: (36 + rnd.random() * 4,) * 3, quad), "BLACK"),
            "noise": (synth(lambda fx, fy: [rnd.random() * 255 for _ in range(3)], quad), "SCRAMBLED"),
            "hshift": (synth(lambda fx, fy: bars((fx + .3) % 1, fy), quad), "SCRAMBLED"),
            "vflip": (synth(lambda fx, fy: bars(fx, 1 - fy), quad), "SCRAMBLED"),
            "hstripes": (synth(lambda fx, fy: (230,) * 3 if int(fy * 40) % 2 else (30,) * 3, quad), "SCRAMBLED"),
            "flat-grey": (synth(lambda fx, fy: (128, 128, 128), quad), "FLAT"),
        }
        for name, (img, want) in cases.items():
            r = classify(cal, img, "bars", 1234)
            print(f"{qname:8s} {name:10s} want {want:9s} got {r['verdict']:9s} {cam_summary(r)}")
            bad += r["verdict"] != want
        r = classify(cal, cases["good"][0], "bars", 1235)
        print(f"{qname:8s} {'wrongcase':10s} want WRONGCASE got {r['verdict']}")
        bad += r["verdict"] != "WRONGCASE"
    return bad


def main(a):
    if not a:
        sys.exit(__doc__)
    if a[0] == "find":
        print(find())
    elif a[0] == "capture":
        print(capture(a[1]))
    elif a[0] == "calib":
        c = calib(a[1], a[2])
        json.dump(c, open(a[3], "w"))
        print(json.dumps(c))
    elif a[0] == "classify":
        cal = json.load(open(a[1]))
        print(json.dumps(classify(cal, load(a[2]), a[3], int(a[4]) if len(a) > 4 else None)))
    elif a[0] == "rescore":
        rescore(a[1])
    elif a[0] == "selftest":
        sys.exit(selftest())
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main(sys.argv[1:])
