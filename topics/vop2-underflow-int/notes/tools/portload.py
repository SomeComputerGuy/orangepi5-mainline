#!/usr/bin/python3 -I
# SPDX-License-Identifier: GPL-2.0
# portload.py: active VOP2 windows, their AXI port (from the window registers) and estimated
# fetch rate (src w*h*bpp*refresh), summed per port. Needs root (debugfs + /dev/mem).
import mmap, os, re, struct
BPP = {'XR24': 32, 'AR24': 32, 'XB24': 32, 'AB24': 32, 'NV12': 12, 'NV15': 15, 'RG16': 16}
fd = os.open('/dev/mem', os.O_RDONLY | os.O_SYNC)
m = mmap.mmap(fd, 0x4000, mmap.MAP_SHARED, mmap.PROT_READ, offset=0xfdd90000)
rd = lambda off: struct.unpack('<I', m[off:off + 4])[0]
def port(name):
    n = int(name[-1])
    if name.startswith('Cluster'):
        return rd(0x1100 + n * 0x200) >> 13 & 1
    return rd(0x1808 + n * 0x200) >> 1 & 1
load = [0.0, 0.0]; out = []
vp = None; hz = 0
for line in open('/sys/kernel/debug/dri/0/vop2/summary'):
    s = line.strip()
    if s.startswith('Video Port'):
        vp = s.split(':')[0]
    mm = re.match(r'Display mode: \d+x\d+p(\d+)', s)
    if mm:
        hz = int(mm.group(1))
    mw = re.match(r'(\w+)-win0: ACTIVE', s)
    if mw:
        win = mw.group(1); fmt = None
    mf = re.match(r'format: (\w+)', s)
    if mf:
        fmt = mf.group(1)
    ms = re.match(r'src: pos\[\d+, \d+\] rect\[(\d+) x (\d+)\]', s)
    if ms:
        w, h = int(ms.group(1)), int(ms.group(2))
        gbs = w * h * BPP.get(fmt, 32) / 8 * hz / 1e9
        p = port(win); load[p] += gbs
        out.append('%s %s %dx%d@%d AXI%d %.2fGB/s' % (win, fmt, w, h, hz, p, gbs))
print(' | '.join(out), ' => AXI0 %.2f AXI1 %.2f GB/s' % tuple(load))
