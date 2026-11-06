#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""rga-fu judge (from rga3-nv15; run on the host with python3 -I).

judge.py CASES INPUTS RESULTDIR  -> one line per case: PASS|FAIL|INFO <id> <details>
RESULTDIR has cases.tsv (id rc) and per case <id>.log / <id>.raw from board.sh.

check = KIND[@MOD]... with MODs (all must hold, besides the KIND check):
  crop=L,T,W,H     the driver kept this crop rectangle ("CROP" line); the input reference is cropped to it
  compose=L,T,W,H  the driver kept this compose rectangle ("COMPOSE" line); the KIND check runs on that region
                   of the output and every byte outside it must still be the 0x5a fill (XR24 only)
  obpl=A[,B] / cbpl=A[,B]  bytesperline of the OUTPUT / CAPTURE planes after S_FMT ("OUT"/"CAP" line)
  ref=FMT          read the reference as FMT (REF10 = 16-bit 4:2:0, REF422 = 16-bit 4:2:2)
"""
import os, re, sys
import numpy as np

CASES, INP, RES = sys.argv[1:4]


def unpack_nv15(b, rows, w):
    a = np.frombuffer(b, np.uint8).reshape(rows, w * 5 // 4 // 5, 5).astype(np.uint64)
    v = sum(a[..., i] << (8 * i) for i in range(5))
    s = np.stack([(v >> (10 * i)) & 0x3ff for i in range(4)], axis=-1)
    return s.reshape(rows, w).astype(np.int32)


def planes(path, fcc, w, h, frame=0):
    """Tight frame -> (Y or RGB array, chroma array or None) as int32. 10-bit formats -> 10-bit samples."""
    if fcc == 'NV20':
        rb = w * 5 // 4
        fs = rb * h * 2
        a = open(path, 'rb').read()[frame * fs:(frame + 1) * fs]
        return unpack_nv15(a[:rb * h], h, w), unpack_nv15(a[rb * h:], h, w)
    if fcc == 'REF422':
        fs = w * h * 2
        a = np.fromfile(path, '<u2', fs, offset=frame * fs * 2).astype(np.int32)
        return a[:w * h].reshape(h, w), a[w * h:].reshape(h, w)
    if fcc in ('NV12', 'NM12', 'NV16'):
        ch = h // 2 if fcc != 'NV16' else h
        fs = w * h + w * ch
        a = np.fromfile(path, np.uint8, fs, offset=frame * fs).astype(np.int32)
        return a[:w * h].reshape(h, w), a[w * h:].reshape(ch, w)
    if fcc == 'NV15':
        rb = w * 5 // 4
        fs = rb * h * 3 // 2
        a = open(path, 'rb').read()[frame * fs:(frame + 1) * fs]
        return unpack_nv15(a[:rb * h], h, w), unpack_nv15(a[rb * h:], h // 2, w)
    if fcc in ('P010', 'REF10', 'P010RAW'):
        fs = w * h * 3 // 2
        a = np.fromfile(path, '<u2', fs, offset=frame * fs * 2).astype(np.int32)
        if fcc == 'P010':
            a = a >> 6
        return a[:w * h].reshape(h, w), a[w * h:].reshape(h // 2, w)
    if fcc == 'XR24':
        fs = w * h * 4
        a = np.fromfile(path, np.uint8, fs, offset=frame * fs).astype(np.int32)
        return a.reshape(h, w, 4)[..., :3], None   # B, G, R
    raise ValueError(fcc)


def psnr(a, b, peak):
    m = np.mean((a.astype(np.float64) - b) ** 2)
    return 99.0 if m == 0 else 10 * np.log10(peak * peak / m)


def dims(s):
    m = re.match(r'(\d+)x(\d+):(\w+)', s)
    return int(m[1]), int(m[2]), m[3]


def chroma_pairs(c):
    return c.reshape(c.shape[0], -1, 2)


ROT = {  # transform name -> function on (H, W, ...) arrays; flips first, then clockwise rotation
    'id': lambda a: a, 'hflip': lambda a: a[:, ::-1], 'vflip': lambda a: a[::-1], 'rot180': lambda a: a[::-1, ::-1],
    'rot90': lambda a: np.rot90(a, -1), 'rot270': lambda a: np.rot90(a, 1),
    'hflip+rot90': lambda a: np.rot90(a[:, ::-1], -1), 'vflip+rot90': lambda a: np.rot90(a[::-1], -1),
}


def wanted(args):
    """V4L2 semantics used here: hflip/vflip apply to the source, then the clockwise rotation."""
    r = int(re.search(r'-r (\d+)', args)[1]) if '-r ' in args else 0
    t = np.arange(12).reshape(3, 4)
    if '-H' in args:
        t = t[:, ::-1]
    if '-V' in args:
        t = t[::-1]
    t = np.rot90(t, -(r // 90))
    base = np.arange(12).reshape(3, 4)
    for name, fn in ROT.items():
        x = fn(base)
        if x.shape == t.shape and np.array_equal(x, t):
            return name
    raise ValueError(args)


def xform_planes(y, c, t):
    """Apply a transform to luma (or RGB) and to the chroma plane as CbCr pairs."""
    ty = ROT[t](y)
    if c is None:
        return ty, None
    tc = ROT[t](chroma_pairs(c))
    return ty, tc.reshape(tc.shape[0], -1)


def detect(oy, oc, iy, ic):
    hit = []
    for t in ROT:
        ty, tc = xform_planes(iy, ic, t)
        if ty.shape == oy.shape and np.array_equal(ty, oy) and (oc is None or (tc.shape == oc.shape and np.array_equal(tc, oc))):
            hit.append(t)
    return ','.join(hit) or 'none'


def rect(s):
    return tuple(int(x) for x in s.split(','))


def vsub(fcc):
    return 2 if fcc in ('NV12', 'NM12', 'NV15', 'P010', 'REF10') else 1


def crop_planes(y, c, fcc, r):
    """Cut rectangle r (l, t, w, h) out of luma/RGB and the interleaved chroma plane."""
    l, t, w, h = r
    y = y[t:t + h, l:l + w]
    if c is not None:
        v = vsub(fcc)
        c = c[t // v:(t + h) // v, l:l + w]
    return y, c


def mod_checks(mods, log, df, out, dw, dh):
    """Rectangle/stride checks; returns (ok, text)."""
    res = []
    for k, v in mods.items():
        if k in ('crop', 'compose'):
            m = re.search(rf'^{k.upper()} (-?\d+) (-?\d+) (\d+) (\d+)$', log, re.M)
            got = tuple(map(int, m.groups())) if m else None
            res.append((got == rect(v), f'{k} {got} want {rect(v)}'))
        elif k in ('obpl', 'cbpl'):
            m = re.search(rf'^{"OUT" if k == "obpl" else "CAP"} \S+ \S+ planes (\d+) bpl (\d+) (\d+)', log, re.M)
            want = rect(v)
            got = (int(m[2]), int(m[3]))[:int(m[1])] if m else None
            res.append((got == want, f'{k} {got} want {want}'))
    if 'compose' in mods:
        l, t, w, h = rect(mods['compose'])
        if df == 'XR24':
            a = np.fromfile(out, np.uint8, dw * dh * 4).reshape(dh, dw, 4).copy()
            a[t:t + h, l:l + w] = 0x5a
            n = int(np.count_nonzero(a != 0x5a))
            res.append((n == 0, f'bytes changed outside compose {n}'))
        else:
            res.append((False, 'compose check needs XR24'))
    return all(r[0] for r in res), '; '.join(r[1] for r in res) or 'no rectangle/stride checks'


rows = {}
for l in open(os.path.join(RES, 'cases.tsv')):
    k, rc = l.split()[:2]
    rows[k] = int(rc)
for line in open(CASES):
    if line.startswith('#') or not line.strip():
        continue
    cid, node, inp, src, dst, args, nfr, kind, ref = line.rstrip('\n').split('|')
    nfr = int(nfr)
    kind, *ml = kind.split('@')
    mods = dict(m.split('=', 1) for m in ml)
    cr = rect(mods['crop']) if 'crop' in mods else None
    co = rect(mods['compose']) if 'compose' in mods else None
    out = os.path.join(RES, cid + '.raw')
    if cid not in rows:
        print('FAIL', cid, 'not run')
        continue
    rc = rows[cid]
    sw, sh, sf = dims(src)
    fsw, fsh = sw, sh                  # whole OUTPUT frame (the input file)
    dw, dh, df = dims(dst)
    fw, fh = dw, dh                    # whole CAPTURE frame (the raw file)
    if co:
        dw, dh = co[2], co[3]          # the KIND check sees the compose region only

    def outp(fcc, fr):
        """Output planes (of the compose region)."""
        y, c = planes(out, fcc, fw, fh, fr)
        return crop_planes(y, c, fcc, co) if co else (y, c)

    def refp(path, fcc, fr):
        """Reference planes (of the crop rectangle)."""
        y, c = planes(path, fcc, fsw, fsh, fr)
        return crop_planes(y, c, fcc, cr) if cr else (y, c)
    if kind == 'reject':
        log = open(os.path.join(RES, cid + '.log')).read()
        ok = rc == 4 and 'CTRL rotate=90 refused' in log
        print('PASS' if ok else 'FAIL', cid, f'rc={rc} (want 4: rotation refused for YUV 4:2:2)')
        continue
    if rc != 0:
        print('INFO' if kind.startswith('info') else 'FAIL', cid, f'rc={rc}', open(os.path.join(RES, cid + '.log')).read().strip().splitlines()[-1:])
        continue
    log = open(os.path.join(RES, cid + '.log')).read()
    nerr = len(re.findall(r'^frame \d+ ERROR', log, re.M))
    if nerr:
        print('FAIL', cid, f'{nerr} frames with V4L2_BUF_FLAG_ERROR')
        continue
    try:
        res = []
        if mods:
            res.append(mod_checks(mods, log, df, out, fw, fh))
        if cr:
            sw, sh = cr[2], cr[3]
        for fr in range(nfr):
            if kind in ('10to8', 'p010', '8to10', 'rgb709', 'rgb2020'):
                ry, rc_ = refp(os.path.join(INP, ref), mods.get('ref', 'NV12' if kind == '8to10' else 'REF10'),
                               fr % 4 if ref not in ('hevc10-f0.ref10', 'pic10.ref422') else 0)
            if kind == '10to8':
                oy, oc = outp(df, fr)
                d = [np.abs(o - r / 4) for o, r in ((oy, ry), (oc, rc_))]
                p = psnr(np.concatenate([oy.ravel(), oc.ravel()]), np.concatenate([ry.ravel(), rc_.ravel()]) / 4, 255)
                tr = np.mean(np.concatenate([(oy == ry >> 2).ravel(), (oc == rc_ >> 2).ravel()]))
                rn = np.mean(np.concatenate([(oy == np.minimum((ry + 2) >> 2, 255)).ravel(), (oc == np.minimum((rc_ + 2) >> 2, 255)).ravel()]))
                mx = max(float(np.max(x)) for x in d)
                res.append((p >= 45 and mx <= 1.0, f'f{fr} psnr {p:.2f} dB max|d| {mx:.2f} trunc-exact {tr:.4f} round-exact {rn:.4f}'))
            elif kind == 'p010':
                oy, oc = outp('P010', fr)
                ly, lc = outp('P010RAW', fr)
                ok = np.array_equal(oy, ry) and np.array_equal(oc, rc_) and not (ly & 0x3f).any() and not (lc & 0x3f).any()
                lsb = np.array_equal(ly & 0x3ff, ry) and np.array_equal(lc & 0x3ff, rc_)
                res.append((ok, f'f{fr} bit-exact {ok}' + ('' if ok else f' (LSB-aligned instead: {lsb}; Y mismatches {np.count_nonzero(oy != ry)})')))
            elif kind == 'exact10':
                ry, rc_ = refp(os.path.join(INP, ref), mods.get('ref', ref.rsplit('.', 1)[1].upper()), fr)
                oy, oc = outp(df, fr)
                ok = np.array_equal(oy, ry) and np.array_equal(oc, rc_)
                res.append((ok, f'f{fr} bit-exact {ok} (Y mismatches {np.count_nonzero(oy != ry)}, C {np.count_nonzero(oc != rc_)})'))
            elif kind == '8to10':
                oy, oc = outp('P010', fr)
                o = np.concatenate([oy.ravel(), oc.ravel()]); r = np.concatenate([ry.ravel(), rc_.ravel()])
                p = psnr(o, r * 4.0, 1023)
                res.append((p >= 45, f'f{fr} psnr {p:.2f} dB (10-bit), exact <<2 {np.mean(o == r << 2):.4f}, exact *1023/255 {np.mean(o == np.round(r * 1023 / 255)):.4f}'))
            elif kind in ('rgb709', 'rgb2020'):
                oy, _ = outp('XR24', fr)
                kr, kb = (0.2126, 0.0722) if kind == 'rgb709' else (0.2627, 0.0593)
                kg = 1 - kr - kb
                cb = np.repeat(np.repeat(chroma_pairs(rc_)[..., 0], 2, 0), 2, 1)
                cr = np.repeat(np.repeat(chroma_pairs(rc_)[..., 1], 2, 0), 2, 1)
                Y = (ry - 64) / 876.0; Cb = (cb - 512) / 896.0; Cr = (cr - 512) / 896.0
                R = Y + 2 * (1 - kr) * Cr; B = Y + 2 * (1 - kb) * Cb; G = (Y - kr * R - kb * B) / kg
                ref_rgb = np.clip(np.stack([B, G, R], -1) * 255, 0, 255)
                p = psnr(oy, ref_rgb, 255)
                res.append((p >= 30, f'f{fr} psnr {p:.2f} dB vs float {kind[3:]} limited -> full RGB'))
            elif kind == 'scale':
                ry, rc_ = planes(os.path.join(INP, ref), 'NV12', dw, dh, fr)
                oy, oc = planes(out, 'NV12', dw, dh, fr)
                p = psnr(np.concatenate([oy.ravel(), oc.ravel()]), np.concatenate([ry.ravel(), rc_.ravel()]), 255)
                res.append((p >= 30, f'f{fr} psnr {p:.2f} dB vs FFmpeg bicubic'))
            elif kind in ('xform', 'xform10', 'info-xform'):
                if kind == 'xform10':
                    iy, ic = refp(os.path.join(INP, ref), mods.get('ref', 'REF10'), 0)
                else:
                    iy, ic = refp(os.path.join(INP, ref), sf, 0)
                oy, oc = outp(df, fr)
                want = wanted(args)
                ty, tc = xform_planes(iy, ic, want)
                ok = ty.shape == oy.shape and np.array_equal(ty, oy) and (oc is None or np.array_equal(tc, oc))
                got = detect(oy, oc, iy, ic)
                res.append((ok, f'want {want} got {got}'))
            elif kind == 'dmabuf':
                iy, _ = refp(os.path.join(INP, ref), 'XR24', 0)
                oy, _ = outp('XR24', fr)
                ok = np.array_equal(iy, oy)
                res.append((ok, f'f{fr} copy bit-exact {ok}'))
            elif kind == 'up422':
                # 4:2:0 -> 4:2:2: luma bit-exact; every chroma sample of output rows 2k, 2k+1 within the range
                # of input chroma rows k-1..k+1 (row doubling and any linear interpolation pass)
                ry, rc_ = refp(os.path.join(INP, ref), 'REF10', 0)
                oy, oc = outp(df, fr)
                ye = np.array_equal(oy, ry)
                pad = np.concatenate([rc_[:1], rc_, rc_[-1:]])
                lo = np.minimum(np.minimum(pad[:-2], pad[1:-1]), pad[2:])
                hi = np.maximum(np.maximum(pad[:-2], pad[1:-1]), pad[2:])
                lo2, hi2 = np.repeat(lo, 2, 0), np.repeat(hi, 2, 0)
                nb = int(np.count_nonzero((oc < lo2) | (oc > hi2)))
                dup = np.mean(oc == np.repeat(rc_, 2, 0))
                res.append((ye and nb == 0, f'f{fr} Y bit-exact {ye}; chroma outside neighbour range {nb}; row-doubling exact {dup:.4f}'))
            elif kind == 'rect':
                res.append((True, 'rc=0'))
            elif kind == 'info':
                res.append((True, 'rc=0'))
            elif kind == 'same-as':
                ok = open(out, 'rb').read() == open(os.path.join(RES, ref + '.raw'), 'rb').read()
                res.append((ok, f'output identical to {ref}: {ok}'))
            else:
                res.append((False, 'unknown check ' + kind))
    except Exception as e:  # missing/short output files
        res = [(False, f'judge error: {e!r}')]
    ok = all(r[0] for r in res)
    tag = 'INFO' if kind.startswith('info') else ('PASS' if ok else 'FAIL')
    print(tag, cid, '; '.join(r[1] for r in res))
