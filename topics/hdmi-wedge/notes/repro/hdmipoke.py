#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0
# DIAGNOSTIC ONLY: read-modify-write one dw-hdmi-qp (HDMI0) register via /dev/mem while HDMI0 is enabled.
# usage: hdmipoke.py <offset> <value> [mask]   (mask given: new = (old & ~mask) | (value & mask))
import mmap, os, struct, sys
off, val = int(sys.argv[1], 0), int(sys.argv[2], 0)
mask = int(sys.argv[3], 0) if len(sys.argv) > 3 else 0xffffffff
fd = os.open("/dev/mem", os.O_RDWR | os.O_SYNC)
m = mmap.mmap(fd, 0x4000, mmap.MAP_SHARED, mmap.PROT_READ | mmap.PROT_WRITE, offset=0xfde80000)
old = struct.unpack_from("<I", m, off)[0]
new = (old & ~mask) | (val & mask) if mask != 0xffffffff else val
struct.pack_into("<I", m, off, new)
print(f"0x{off:04x}: 0x{old:08x} -> 0x{new:08x} (now 0x{struct.unpack_from('<I', m, off)[0]:08x})")
