#!/usr/bin/python3 -I
# sps_patch.py in.h265 out.h265 field=value ...: rewrite ue(v)/u(1) fields of
# every SPS (debugging aid: test which coding-tool settings the hardware
# assumes, without re-encoding). Special field "scaling_default=1" turns on
# the default scaling lists.
import os
import sys

sys.path.insert(0, os.path.expanduser('~/orangepi5/work/_out/hevc-enc-uapi/tools'))
import hevc_ref  # noqa: E402


def ue_bits(v):
    code = v + 1
    n = code.bit_length()
    return '0' * (n - 1) + format(code, 'b')


class FieldReader(hevc_ref.Reader):
    last = None

    def __init__(self, data):
        super().__init__(data)
        self.fields = {}
        FieldReader.last = self

    def u(self, n, name=None):
        if name:
            self.fields[name] = (self.pos, n, 'u')
        return super().u(n, name)

    def ue(self, name=None):
        start = self.pos
        v = super().ue(name)
        if name:
            self.fields[name] = (start, self.pos - start, 'ue')
        return v


def patch_sps(nal, changes):
    orig = hevc_ref.Reader
    hevc_ref.Reader = FieldReader
    try:
        list(hevc_ref.parse(nal, {}))
    finally:
        hevc_ref.Reader = orig
    r = FieldReader.last
    bits = r.bits
    edits = []
    for name, val in changes.items():
        if name == 'scaling_default':
            pos, n, _ = r.fields['scaling_list_enabled_flag']
            edits.append((pos, n, '10' if val else '0'))
            continue
        pos, n, kind = r.fields[name]
        edits.append((pos, n, ue_bits(val) if kind == 'ue' else format(val, '0%db' % n)))
    for pos, n, new in sorted(edits, reverse=True):
        bits = bits[:pos] + new + bits[pos + n:]
    bits = bits.rstrip('0')[:-1] + '1'
    while len(bits) % 8:
        bits += '0'
    rbsp = bytes(int(bits[i:i + 8], 2) for i in range(0, len(bits), 8))
    return rbsp[:2] + hevc_ref.epb(rbsp[2:])


changes = dict((a.split('=')[0], int(a.split('=')[1])) for a in sys.argv[3:])
data = open(sys.argv[1], 'rb').read()
starts, i = [], 0
while i < len(data) - 3:
    if data[i:i + 4] == b'\x00\x00\x00\x01':
        starts.append(i)
        i += 4
    else:
        i += 1
starts.append(len(data))
out, n = bytearray(), 0
for k in range(len(starts) - 1):
    nal = data[starts[k] + 4:starts[k + 1]]
    if (nal[0] >> 1) & 0x3f == 33:
        nal = patch_sps(nal, changes)
        n += 1
    out += b'\x00\x00\x00\x01' + nal
open(sys.argv[2], 'wb').write(out)
print('patched %d SPS: %s' % (n, changes))
