#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0
# Replace the first (preferred) DTD of an EDID base block with
# 3840x2160@30 CVT-RB (262.75 MHz, h 3840/3888/3920/4000 v 2160/2163/2168/2191 +h -v).
import sys
e = bytearray(open(sys.argv[1], 'rb').read())
d = bytes([0xa3, 0x66, 0x00, 0xa0, 0xf0, 0x70, 0x1f, 0x80, 0x30, 0x20, 0x35, 0x00]) + e[0x36+12:0x36+17] + bytes([0x1a])
e[0x36:0x36+18] = d
e[127] = (-sum(e[:127])) & 0xff
open(sys.argv[2], 'wb').write(e)
