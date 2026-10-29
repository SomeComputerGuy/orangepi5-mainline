#!/usr/bin/python3 -I
# hevc_dump.py out.h265 [max_nals]: print the parameter sets and the
# hardware-written slice segment headers of an Annex-B stream, using the
# independent parser of the HEVC uAPI work (hevc_ref.py). Host-side only.
import os
import sys

sys.path.insert(0, os.path.expanduser('~/orangepi5/work/_out/hevc-enc-uapi/tools'))
import hevc_ref  # noqa: E402


def nals(stream):
    """Split on 3- and 4-byte start codes."""
    starts, i = [], 0
    while i < len(stream) - 3:
        if stream[i:i + 3] == b'\x00\x00\x01':
            starts.append(i + 3)
            i += 3
        else:
            i += 1
    for k, s in enumerate(starts):
        e = starts[k + 1] - 3 if k + 1 < len(starts) else len(stream)
        if k + 1 < len(starts) and stream[e - 1] == 0:
            e -= 1
        yield stream[s:e]


def main():
    data = open(sys.argv[1], 'rb').read()
    limit = int(sys.argv[2]) if len(sys.argv) > 2 else 12
    ctx = {}
    for n, nal in enumerate(nals(data)):
        if n >= limit:
            break
        nut = (nal[0] >> 1) & 0x3f
        print('== nal %d: type %d tid1 %d, %d bytes, %s...' %
              (n, nut, nal[1] & 7, len(nal), nal[:12].hex()))
        try:
            for k, v in hevc_ref.parse(nal, ctx):
                print('  %-48s %d' % (k, v))
        except Exception as e:  # slice data follows the header
            print('  (parse stopped: %r)' % e)


if __name__ == '__main__':
    main()
