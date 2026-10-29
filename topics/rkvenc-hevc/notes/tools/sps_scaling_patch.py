#!/usr/bin/python3 -I
# sps_scaling_patch.py in.h265 out.h265: rewrite every SPS with
# scaling_list_enabled_flag = 1 and sps_scaling_list_data_present_flag = 0
# (the default scaling lists), leaving everything else unchanged.
# Debugging aid to test which quantisation matrices the hardware uses.
import os
import sys

sys.path.insert(0, os.path.expanduser('~/orangepi5/work/_out/hevc-enc-uapi/tools'))
import hevc_ref  # noqa: E402


class PosReader(hevc_ref.Reader):
    def u(self, n, name=None):
        if name == 'scaling_list_enabled_flag':
            self.sl_pos = self.pos
        return super().u(n, name)


def patch_sps(nal):
    rd = {}

    class R(PosReader):
        def __init__(self, data):
            super().__init__(data)
            rd['r'] = self
    orig = hevc_ref.Reader
    hevc_ref.Reader = R
    try:
        list(hevc_ref.parse(nal, {}))
    finally:
        hevc_ref.Reader = orig
    r = rd['r']
    bits = r.bits
    p = r.sl_pos
    assert bits[p] == '0'
    bits = bits[:p] + '10' + bits[p + 1:]
    bits = bits.rstrip('0')[:-1] + '1'
    while len(bits) % 8:
        bits += '0'
    rbsp = bytes(int(bits[i:i + 8], 2) for i in range(0, len(bits), 8))
    return rbsp[:2] + hevc_ref.epb(rbsp[2:])


data = open(sys.argv[1], 'rb').read()
out = bytearray()
i = 0
starts = []
while i < len(data) - 3:
    if data[i:i + 4] == b'\x00\x00\x00\x01':
        starts.append(i)
        i += 4
    else:
        i += 1
starts.append(len(data))
n = 0
for k in range(len(starts) - 1):
    seg = data[starts[k]:starts[k + 1]]
    nal = seg[4:]
    if (nal[0] >> 1) & 0x3f == 33:
        nal = patch_sps(nal)
        n += 1
    out += b'\x00\x00\x00\x01' + nal
open(sys.argv[2], 'wb').write(out)
print('patched %d SPS' % n)
