#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Lighting-invariant webcam classifier for the kmsctl "bars" test pattern (pure Python, no numpy).

Shared by the FRL trials, the VOP2 checks and the display-matrix harnesses. The camera, its exposure and the
room light may change between frames, so nothing is judged against absolute levels:

 1. Screen outline per frame: the calibrated quad (calib-<CONN>.json from testmatrix camcheck.py calib) is
    only a prior. The frame is warped with a margin around it and the pattern layout (16 black/white
    stripes, white and black bars, and the expected code's cells when known) is fitted over shifts and
    separate x/y scales (summed-area tables), coarse to fine. A screen cut off by the frame edge is fine: samples outside the image are just missing.
    A mode whose aspect differs from the calibration mode may be shown pillarboxed/letterboxed by the sink (the TV
    shows 640x480 as a centred 4:3 picture): when the calibrated size does not give GOOD, those sizes are fitted
    too and the better-fitting geometry is judged.
 2. Per-frame references: white = the white stripes + white bar, black = the black stripes + black bar of
    the fitted pattern, robust (masked medians). Every region is decoded by its contrast between those two
    references: n = (v - black) / (white - black), on above 0.5, "unsure" within 0.5 +- MARGIN.
 3. Specular highlights (ceiling lights on the panel): while the white reference is below clipping, pixels
    with a clipped channel or > 1.8x brighter than it are masked before the median when they are a minority
    of the region (excluded, not decoded; the panel's own white varies by ~30 % across the screen);
    when the white reference clips, the region median (a highlight is a small spot) excludes them.
 4. Bars: per channel, the bars with that channel on must all read brighter than those with it off (a rank
    test inside the frame, no level threshold); a channel whose on/off boundary is clipped is skipped.
 5. "Is the pattern there" gate: the layout fit must score >= 3.0, either raw or after dividing the panel's
    smooth brightness falloff out of the white regions (_flat_score; a dark room shows a 3x falloff that the
    raw score would count as noise).

classify(cal, img, code) -> dict with verdict:
    GOOD       pattern fitted, stripes right, all 16 code cells = code, bars consistent
    WRONGCASE  pattern fitted and stripes right, but the code cells show another code
    SCRAMBLED  structure on the screen, but not this pattern (noise, shift, tearing, or something in front)
    NOSIGNAL   no pattern and 3/4 of the calibrated screen area is near black (glare spots and the TV's own
               "No Signal" box are small; noise or something in front of the screen lifts that quantile)
plus fit/levels details. A single frame is never final: judge() requires the same non-GOOD verdict on
CONFIRM captures >= 20 s apart and retries while the room light changes (frame brightness jump).

CLI:  camcheck.py classify <calib.json> <frame.rgb|.jpg> <code>
      camcheck.py validate <calib.json> <truth.tsv>   (truth: path<TAB>code<TAB>GOOD|NOSIGNAL)
"""
import json, os, sys

SIZES = [(192, 108), (384, 216), (320, 180), (640, 360), (960, 540), (1280, 720)]
CLIP = 248          # a channel at/above this is clipped (blown highlight or over-exposed)
GLARE = 1.8         # luminance above GLARE * white reference = glare, masked (white varies ~30 % over the panel)
MARGIN = 0.2        # |n - 0.5| below this is "unsure"
GW, GH = 192, 108   # canonical screen grid
PAD = 0.10          # search margin around the prior quad (fraction of the screen size, each side)
CONFIRM = 3         # captures with the same non-GOOD verdict before it is final
SPACING = 20        # seconds between those captures
LIGHT_JUMP = 0.25   # relative change of the surroundings' brightness that means "the light changed"
ON = {"W": (1, 1, 1), "Y": (1, 1, 0), "C": (0, 1, 1), "G": (0, 1, 0), "M": (1, 0, 1), "R": (1, 0, 0),
      "B": (0, 0, 1), "K": (0, 0, 0)}


# ---------------------------------------------------------------- frames and geometry
def load(path):
    """-> (w, h, bytes RGB); .jpg is decoded via the .rgb written next to it by capture()"""
    if path.endswith(".jpg"):
        path = path[:-4] + ".rgb"
    b = open(path, "rb").read()
    for w, h in SIZES:
        if len(b) == w * h * 3:
            return w, h, b
    for w, h in SIZES:
        if b and len(b) % (w * h * 3) == 0:
            return w, h, b[-w * h * 3:]
    raise RuntimeError(f"{path}: unknown frame size {len(b)}")


def code_bits(code):  # same as kmsctl.code_bits
    code &= 0xfff
    return [(code >> i) & 1 for i in range(12)] + [((code * 7 + 3) >> i) & 1 for i in range(4)]


def _solve(a, y):
    n = len(y)
    m = [row[:] + [y[i]] for i, row in enumerate(a)]
    for c in range(n):
        p = max(range(c, n), key=lambda r: abs(m[r][c]))
        m[c], m[p] = m[p], m[c]
        for r in range(n):
            if r != c:
                f = m[r][c] / m[c][c]
                m[r] = [x - f * z for x, z in zip(m[r], m[c])]
    return [m[i][n] / m[i][i] for i in range(n)]


def homography(quad):
    """unit square (u, v) -> image fraction (x, y) for quad tl, tr, br, bl"""
    src = [(0, 0), (1, 0), (1, 1), (0, 1)]
    a, y = [], []
    for (u, v), (x, yy) in zip(src, quad):
        a.append([u, v, 1, 0, 0, 0, -u * x, -v * x]); y.append(x)
        a.append([0, 0, 0, u, v, 1, -u * yy, -v * yy]); y.append(yy)
    return _solve(a, y)


def _apply(H, u, v):
    d = H[6] * u + H[7] * v + 1
    return (H[0] * u + H[1] * v + H[2]) / d, (H[3] * u + H[4] * v + H[5]) / d


def prior_quad(cal):
    q = cal["quad"]
    e = cal.get("top_ext", 0)
    if not e:
        return q
    tl, tr, br, bl = q
    return [[tl[0] + (tl[0] - bl[0]) * e, tl[1] + (tl[1] - bl[1]) * e],
            [tr[0] + (tr[0] - br[0]) * e, tr[1] + (tr[1] - br[1]) * e], br, bl]


def warp_padded(img, quad):
    """grid of the quad grown by PAD on every side: list of (r, g, b) or None (outside the frame).
    Grid size (GW, GH) * (1 + 2 PAD); the screen at the prior sits at offset (PAD*GW, PAD*GH)."""
    w, h, b = img
    H = homography(quad)
    pw, ph = int(GW * (1 + 2 * PAD)), int(GH * (1 + 2 * PAD))
    g = []
    for j in range(ph):
        v = (j + .5) / GH - PAD
        for i in range(pw):
            u = (i + .5) / GW - PAD
            x, y = _apply(H, u, v)
            px, py = int(x * w), int(y * h)
            if 0 <= px < w and 0 <= py < h:
                o = (py * w + px) * 3
                g.append((b[o], b[o + 1], b[o + 2]))
            else:
                g.append(None)
    return g, pw, ph


def lum(p):
    return p[0] * .299 + p[1] * .587 + p[2] * .114


# ---------------------------------------------------------------- layout and fitting
def layout():
    """bars [(fx0,fy0,fx1,fy1,colour)], stripes [(..., on)], code cells [(...)] in screen fractions"""
    bars = [(i / 8, 0, (i + 1) / 8, .55, c) for i, c in enumerate("WYCGMRBK")]
    stripes = [(i / 16, .55, (i + 1) / 16, .70, i % 2 == 0) for i in range(16)]
    cells = [((i % 8) / 8, .70 if i < 8 else .85, (i % 8 + 1) / 8, .85 if i < 8 else 1.0) for i in range(16)]
    return bars, stripes, cells


def _sat(vals, pw, ph):
    """summed-area tables of value and count (None = missing)"""
    S = [[0.0] * (pw + 1) for _ in range(ph + 1)]
    N = [[0] * (pw + 1) for _ in range(ph + 1)]
    for j in range(ph):
        rs, rn = 0.0, 0
        for i in range(pw):
            v = vals[j * pw + i]
            if v is not None:
                rs += v
                rn += 1
            S[j + 1][i + 1] = S[j][i + 1] + rs
            N[j + 1][i + 1] = N[j][i + 1] + rn
    return S, N


def _box(T, x0, y0, x1, y1):
    S, N = T
    s = S[y1][x1] - S[y0][x1] - S[y1][x0] + S[y0][x0]
    n = N[y1][x1] - N[y0][x1] - N[y1][x0] + N[y0][x0]
    return s, n


def _rect(fit, r, inner=.5):
    """screen-fraction rect -> padded-grid integer box (inner part only, away from edges/blur)"""
    ox, oy, sw, sh = fit
    fx0, fy0, fx1, fy1 = r[:4]
    mx, my = (fx1 - fx0) * (1 - inner) / 2, (fy1 - fy0) * (1 - inner) / 2
    x0, x1 = int(ox + (fx0 + mx) * sw), int(ox + (fx1 - mx) * sw)
    y0, y1 = int(oy + (fy0 + my) * sh), int(oy + (fy1 - my) * sh)
    return x0, y0, max(x1, x0 + 1), max(y1, y0 + 1)


def _fit_score(T, fit, pw, ph, bits=None):
    """layout contrast: (mean of should-be-white - mean of should-be-black) / spread, over the stripes and
    the white/black bars, plus the code cells when the expected code is given (they pin the bottom edge;
    the decode afterwards still reads what the cells show)"""
    bars, stripes, cells = layout()
    regs = [(s, s[4]) for s in stripes] + [(bars[0], True), (bars[7], False)]
    if bits:
        regs += [(c, bool(b)) for c, b in zip(cells, bits)]
    on, off = [], []
    for r, want in regs:
        x0, y0, x1, y1 = _rect(fit, r)
        if x0 < 0 or y0 < 0 or x1 > pw or y1 > ph:
            continue
        s, n = _box(T, x0, y0, x1, y1)
        if n:
            (on if want else off).append(s / n)
    if len(on) < 5 or len(off) < 5:
        return -1.0
    mo, mf = sum(on) / len(on), sum(off) / len(off)
    sd = (sum((v - mo) ** 2 for v in on) / len(on) + sum((v - mf) ** 2 for v in off) / len(off)) ** .5
    return (mo - mf) / (sd + 0.05 * abs(mo - mf) + 1.0)


def _flat_score(T, fit, pw, ph, bits=None):
    """_fit_score() of the fitted layout after dividing out the panel's smooth shading, for the "is the
    pattern there" gate. The raw score counts the spread of the white regions as noise; but a panel's
    brightness falls off smoothly and multiplicatively towards its edges (viewing angle, backlight), and in a
    dark room nothing hides that (no ambient light on the black, no clipped white): the white stripes/cells of
    a correct picture then read 39..120 for black 1, and the raw score stays under the gate. Per frame, the
    white readings are fitted with a smooth shading s(x, y) = a + b x + c x^2 + d y (4 terms for ~17 regions,
    across the whole width and three heights: it cannot follow a stripe-to-stripe pattern, only a gradient)
    and each is divided by s / mean(s); black readings are left as they are (shading scales the light, black
    has little). A wrong picture or geometry does not gain: its "white" regions are a mix of light and dark,
    which no smooth shading explains, and the separation stays small."""
    bars, stripes, cells = layout()
    regs = [(s, s[4]) for s in stripes] + [(bars[0], True), (bars[7], False)]
    if bits:
        regs += [(c, bool(b)) for c, b in zip(cells, bits)]
    on, off = [], []
    for r, want in regs:
        x0, y0, x1, y1 = _rect(fit, r)
        if x0 < 0 or y0 < 0 or x1 > pw or y1 > ph:
            continue
        s, n = _box(T, x0, y0, x1, y1)
        if n:
            if want:
                on.append((s / n, (r[0] + r[2]) - 1, (r[1] + r[3]) - 1))   # centre in -1..1
            else:
                off.append(s / n)
    if len(on) < 8 or len(off) < 5:
        return -1.0
    rows = [[1.0, x, x * x, y] for _, x, y in on]
    a = [[sum(r[i] * r[j] for r in rows) + (1e-3 if i == j else 0) for j in range(4)] for i in range(4)]
    y = [sum(r[i] * v for r, (v, _, _) in zip(rows, on)) for i in range(4)]
    try:
        k = _solve(a, y)
    except ZeroDivisionError:
        return -1.0
    sh = [sum(ki * ri for ki, ri in zip(k, r)) for r in rows]
    ms = sum(sh) / len(sh)
    if ms <= 0 or min(sh) < 0.25 * ms:         # not a plausible shading (no positive smooth white level)
        return -1.0
    onv = [v * ms / s for (v, _, _), s in zip(on, sh)]
    mo, mf = sum(onv) / len(onv), sum(off) / len(off)
    sd = (sum((v - mo) ** 2 for v in onv) / len(onv) + sum((v - mf) ** 2 for v in off) / len(off)) ** .5
    return (mo - mf) / (sd + 0.05 * abs(mo - mf) + 1.0)


STD_SCALES = [(sx, sy) for sx in (0.94, 0.97, 1.0, 1.03, 1.06) for sy in (0.94, 0.97, 1.0, 1.03, 1.06)]
# Display aspect ratios of the modes under test. A sink that keeps the aspect of a mode whose ratio differs from
# the mode the screen was calibrated with shows it pillarboxed (narrower, centred) or letterboxed (lower,
# centred): e.g. the TV shows 640x480 as a 4:3 picture in the middle of its 16:9 panel (x scale 0.75).
ASPECTS = (256 / 135, 16 / 9, 16 / 10, 3 / 2, 4 / 3, 5 / 4)


def _boxed_scales():
    """coarse (sx, sy) for every pillarbox/letterbox ratio between two ASPECTS that the standard search (down
    to 0.94) does not reach; ratios within 2 % are merged, each is searched at +-3 %"""
    ks = []
    for k in sorted(a / b for a in ASPECTS for b in ASPECTS if a / b < 0.92):
        if not ks or k > ks[-1] * 1.02:
            ks.append(k)
    out = []
    for k in ks:
        for f in (0.97, 1.0, 1.03):
            for o in (0.97, 1.0, 1.03):
                out += [(k * f, o), (o, k * f)]
    return out


BOXED_SCALES = _boxed_scales()


def fit_screen(T, pw, ph, bits=None, scales=None):
    """best (ox, oy, sw, sh) of the screen inside the padded grid: shift +-PAD around the centred position, x
    and y scale from `scales` (default STD_SCALES: 0.94..1.06 each), coarse (4 cells) then fine (1 cell,
    +-1 % scale)"""
    best = (-2.0, None)
    bx, by = PAD * GW, PAD * GH
    cands = []
    for sx, sy in scales or STD_SCALES:
        for dx in range(-int(PAD * GW), int(PAD * GW) + 1, 4):
            for dy in range(-int(PAD * GH), int(PAD * GH) + 1, 4):
                cands.append((bx + dx - (sx - 1) * GW / 2, by + dy - (sy - 1) * GH / 2, GW * sx, GH * sy))
    for c in cands:
        sc = _fit_score(T, c, pw, ph, bits)
        if sc > best[0]:
            best = (sc, c)
    if best[1] is None:
        return best
    ox, oy, sw, sh = best[1]
    for dsx in (-0.01, 0, 0.01):
        for dsy in (-0.01, 0, 0.01):
            for dx in range(-3, 4):
                for dy in range(-3, 4):
                    c = (ox + dx - dsx * GW / 2, oy + dy - dsy * GH / 2, sw + dsx * GW, sh + dsy * GH)
                    sc = _fit_score(T, c, pw, ph, bits)
                    if sc > best[0]:
                        best = (sc, c)
    return best


# ---------------------------------------------------------------- per-region robust readings
def _pixels(g, pw, ph, box):
    x0, y0, x1, y1 = box
    out = []
    for j in range(max(y0, 0), min(y1, ph)):
        for i in range(max(x0, 0), min(x1, pw)):
            p = g[j * pw + i]
            if p is not None:
                out.append(p)
    return out


def _median(v):
    v = sorted(v)
    return v[len(v) // 2] if v else None


def _reading(px, white_l=None):
    """robust per-region reading -> (median luminance, median rgb, masked fraction) or None.
    With an unclipped white reference, glare is excluded first: pixels with a clipped channel or brighter
    than GLARE x white cannot be screen content. When the white reference itself clips, saturated pixels are
    real white, so nothing is masked and the median (a highlight is a small spot) does the work."""
    if not px:
        return None
    use, masked = px, 0.0
    if white_l is not None and white_l < CLIP - 8:
        keep = [p for p in px if max(p) < CLIP and lum(p) <= GLARE * white_l]
        masked = 1 - len(keep) / len(px)
        if len(keep) > len(px) // 2:        # glare is a small spot; a mostly "bright" region is content
            use = keep
    return _median([lum(p) for p in use]), [_median([p[c] for p in use]) for c in range(3)], masked


def classify(cal, img, code=None):
    """verdict of one frame (see the module doc). The screen is first fitted at its calibrated size (+-6 %).
    When that does not give GOOD, the pillarboxed/letterboxed sizes (BOXED_SCALES) are fitted too and the
    geometry with the better pattern fit is judged: a mode of another aspect ratio that the sink shows boxed is
    the same pattern, smaller in one direction, and must be decoded where it actually is."""
    g, pw, ph = warp_padded(img, prior_quad(cal))
    L = [None if p is None else lum(p) for p in g]
    T = _sat(L, pw, ph)
    bits = code_bits(code) if code is not None else None
    score, fit = fit_screen(T, pw, ph, bits)
    r = _judge_fit(g, pw, ph, L, score, fit, code, _flat_score(T, fit, pw, ph, bits) if fit else -1.0)
    if r["verdict"] != "GOOD":
        s2, f2 = fit_screen(T, pw, ph, bits, BOXED_SCALES)
        if f2 and s2 > score:
            r2 = _judge_fit(g, pw, ph, L, s2, f2, code, _flat_score(T, f2, pw, ph, bits))
            r2["boxed"] = [round(f2[2] / GW, 3), round(f2[3] / GH, 3)]
            r = r2
    return r


def _judge_fit(g, pw, ph, L, score, fit, code, flat=-1.0):
    bars, stripes, cells = layout()
    r = {"fit": round(score, 2), "fit_flat": round(flat, 2)}
    # screen statistics inside the calibrated screen area (not the padded search area: bezel and wall stay
    # out), for the no-pattern verdicts; surroundings brightness = everything outside it
    x0, y0 = int(PAD * GW), int(PAD * GH)
    scr = sorted(L[j * pw + i] for j in range(y0, y0 + GH) for i in range(x0, x0 + GW) if L[j * pw + i] is not None)
    r["scr_p50"], r["scr_p75"], r["scr_p90"] = (round(scr[len(scr) * k // 100]) for k in (50, 75, 90)) if scr else (0, 0, 0)
    out = [l for idx, l in enumerate(L) if l is not None and not (x0 <= idx % pw < x0 + GW and y0 <= idx // pw < y0 + GH)]
    r["ambient"] = round(sum(out) / len(out), 1) if out else 0
    # references from the fitted pattern itself
    wr = [_reading(_pixels(g, pw, ph, _rect(fit, s, .6))) for s in stripes if s[4]] if fit else []
    kr = [_reading(_pixels(g, pw, ph, _rect(fit, s, .6))) for s in stripes if not s[4]] if fit else []
    wr, kr = [x for x in wr if x], [x for x in kr if x]
    if wr and kr:
        white = _median([x[0] for x in wr])
        black = _median([x[0] for x in kr])
    else:
        white = black = 0
    r["white"], r["black"] = round(white), round(black)
    rng = white - black
    # no pattern: dark screen = NOSIGNAL, anything else = SCRAMBLED
    # gate: the layout fit, raw or with the panel's smooth shading divided out (_flat_score), must reach 3.0
    if not fit or max(score, flat) < 3.0 or rng < 25:
        # dark screen: 3/4 of the screen area is near black, whatever the room light. Glare spots and the
        # TV's own "No Signal" box are small and stay above that quantile; noise or something in front of the
        # screen (cat, person) lifts it -> SCRAMBLED
        dark = r["scr_p75"] < max(20, 0.3 * r["ambient"])
        r["verdict"] = "NOSIGNAL" if dark else "SCRAMBLED"
        return r

    def norm(box, inner=.6):
        x = _reading(_pixels(g, pw, ph, _rect(fit, box, inner)), white)
        return None if x is None else ((x[0] - black) / rng, x)
    # stripes and code cells: contrast against this frame's own white/black
    sb, unsure = [], 0
    for s in stripes:
        n = norm(s)
        if n is None:
            continue
        unsure += abs(n[0] - .5) < MARGIN
        sb.append((n[0] > .5) == s[4])
    r["stripes"] = round(sum(sb) / max(len(sb), 1), 3)
    bits = []
    for c in cells:
        n = norm(c, .5)
        if n is None:
            bits.append(None)
            continue
        unsure += abs(n[0] - .5) < MARGIN
        bits.append(int(n[0] > .5))
    r["code_bits"], r["unsure"] = bits, unsure
    # bars, per channel and within this frame only: the bars that have the channel on must read brighter
    # than every bar that has it off (rank test, no level threshold). A channel whose on/off boundary lies in
    # clipped readings cannot be told apart and is skipped; a channel that orders the bars wrongly fails.
    rd = [norm(b) for b in bars]
    okb = chk = 0
    if None not in rd:
        for c in range(3):
            v = [x[1][1][c] for x in rd]
            on = [v[i] for i, b in enumerate(bars) if ON[b[4]][c]]
            off = [v[i] for i, b in enumerate(bars) if not ON[b[4]][c]]
            if min(on) >= CLIP and max(off) >= CLIP:
                continue
            # a tie at the top of the range is a saturation plateau (clipped, then scaled): undecidable
            if abs(min(on) - max(off)) <= 3 and min(min(on), max(off)) >= 0.9 * max(v):
                continue
            chk += 1
            okb += min(on) > max(off)
    r["bars"] = round(okb / chk, 3) if chk else None
    if r["stripes"] < 0.85:
        r["verdict"] = "SCRAMBLED"
    elif code is not None and None not in bits and bits != code_bits(code):
        r["verdict"] = "WRONGCASE"
    elif None in bits or (r["bars"] is not None and r["bars"] < 1.0):
        r["verdict"] = "SCRAMBLED"
    else:
        r["verdict"] = "GOOD"
    return r


# ---------------------------------------------------------------- multi-capture judgement
def judge(capture, cal, code, sleep, log=print, max_tries=8):
    """capture(i) -> frame path; returns (final verdict, [per-frame verdicts]). GOOD on the first GOOD frame.
    A non-GOOD verdict is final only after CONFIRM captures SPACING s apart agree; a change of the room light
    between captures (surroundings brightness jump > LIGHT_JUMP) restarts the confirmation instead."""
    hist, run, last_amb = [], [], None
    for i in range(max_tries):
        if i:
            sleep(SPACING)
        try:
            r = classify(cal, load(capture(i)), code)
        except Exception as e:  # noqa: BLE001
            hist.append("CAMERR:" + repr(e)[:60])
            run = []
            continue
        v = r["verdict"]
        hist.append(v)
        if v == "GOOD":
            return "GOOD", hist
        amb = r["ambient"]
        if last_amb and abs(amb - last_amb) > LIGHT_JUMP * max(last_amb, 10):
            log(f"camcheck: light changed ({last_amb:.0f} -> {amb:.0f}), confirmation restarted")
            run = []
        last_amb = amb
        run = run + [v] if run and run[-1] == v else [v]
        if len(run) >= CONFIRM:
            return v, hist
    return "UNSURE", hist


# ---------------------------------------------------------------- CLI
def main(a):
    if a[:1] == ["classify"]:
        r = classify(json.load(open(a[1])), load(a[2]), int(a[3], 0) if len(a) > 3 else None)
        print(json.dumps(r))
        return 0 if r["verdict"] == "GOOD" else 3
    if a[:1] == ["validate"]:
        cal = json.load(open(a[1]))
        fp = fn = n = 0
        for line in open(a[2]):
            path, code, truth = line.rstrip("\n").split("\t")[:3]
            r = classify(cal, load(path), int(code, 0))
            v = r["verdict"]
            n += 1
            if truth == "GOOD" and v != "GOOD":
                fn += 1
                print(f"FALSE-FAIL\t{path}\t{v}\t{json.dumps(r)}")
            elif truth != "GOOD" and v == "GOOD":
                fp += 1
                print(f"FALSE-GOOD\t{path}\t{v}\t{json.dumps(r)}")
        print(f"frames {n}: false fails {fn}, false GOOD {fp}")
        return 0 if not (fp or fn) else 1
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
