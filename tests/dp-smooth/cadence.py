#!/usr/bin/python3 -I
# cadence.py <trace>...: from drm trace events, per CRTC: vblank interval stats, and for
# userspace-requested vblank events (file!=0) and kernel commit events (file=0) the histogram
# of vblank-sequence deltas between consecutive events (1 = one new frame every refresh).
import re, sys, statistics as st, collections
for fn in sys.argv[1:]:
    vb = collections.defaultdict(list); q = collections.defaultdict(list); k = collections.defaultdict(list)
    for l in open(fn):
        m = re.search(r'drm_vblank_event: crtc=(\d+), seq=(\d+), time=(\d+)', l)
        if m: vb[int(m[1])].append((int(m[2]), int(m[3]))); continue
        m = re.search(r'drm_vblank_event_queued: file=(\w+), crtc=(\d+), seq=(\d+)', l)
        if m: q[int(m[2])].append(int(m[3])); continue
        m = re.search(r'drm_vblank_event_delivered: file=(\w+), crtc=(\d+), seq=(\d+)', l)
        if m and int(m[1], 16) == 0: k[int(m[2])].append(int(m[3]))
    print(fn)
    for c in sorted(vb):
        v = vb[c]; d = [(b[1]-a[1])/1e6 for a, b in zip(v, v[1:]) if b[0]-a[0] == 1]
        if d: print('  crtc%d vblank n=%d mean=%.3f sd=%.3f min=%.3f max=%.3f ms' % (c, len(d), st.mean(d), st.pstdev(d), min(d), max(d)))
        for name, s in (('kmssink vblank-wait', q[c]), ('commit-done', k[c])):
            h = collections.Counter(b-a for a, b in zip(s, s[1:]))
            if h: print('    %-20s n=%3d seq-delta histogram %s' % (name, len(s), dict(sorted(h.items()))))
