import sys
# hw file: GStreamer I420 (strides rounded up to 4); ref: tightly packed yuv420p
a, b, w, h = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4])
r4 = lambda x: (x + 3) & ~3
cw, ch = (w + 1) // 2, (h + 1) // 2
ys, cs = r4(w), r4(cw)
fsa = ys * h + 2 * cs * ch
fsb = w * h + 2 * cw * ch
A = open(a, 'rb').read(); B = open(b, 'rb').read()
na, nb = len(A) // fsa, len(B) // fsb
def planes(buf, off, ys, cs):
    out = []
    for (o, st, pw, ph) in ((0, ys, w, h), (ys * h, cs, cw, ch), (ys * h + cs * ch, cs, cw, ch)):
        out.append(b''.join(buf[off + o + y * st: off + o + y * st + pw] for y in range(ph)))
    return out
print(f"{w}x{h} hw_frames={na} ref_frames={nb}")
bad = []
for i in range(min(na, nb)):
    pa = planes(A, i * fsa, ys, cs); pb = planes(B, i * fsb, w, cw)
    if pa != pb:
        bad.append((i, [sum(1 for x, y in zip(p, q) if x != y) for p, q in zip(pa, pb)]))
print("mismatching frames:", len(bad))
for x in bad[:25]:
    print(x)
