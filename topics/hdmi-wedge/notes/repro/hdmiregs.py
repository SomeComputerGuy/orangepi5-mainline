#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0
# Read a few dw-hdmi-qp (HDMI0 @0xfde80000) status registers through /dev/mem. Only read while HDMI0 is enabled.
import mmap, os, struct, sys
BASE = 0xfde80000
REGS = {"GLOBAL_SWDISABLE": 0x44, "RESET_MANAGER_STATUS0": 0x50, "RESET_MANAGER_STATUS1": 0x54,
        "RESET_MANAGER_STATUS2": 0x58, "CMU_STATUS": 0xb0, "CMU_IPI_CLK_FREQ": 0xb4, "CMU_VIDQPCLK_FREQ": 0xb8, "CMU_LINKQPCLK_FREQ": 0xbc, "MAINUNIT_STATUS0": 0x180,
        "VIDEO_INTERFACE_CONFIG0": 0x800, "VIDEO_INTERFACE_STATUS0": 0x814,
        "VIDEO_MONITOR_STATUS0": 0x884, "VIDEO_MONITOR_STATUS1": 0x888, "VIDEO_MONITOR_STATUS2": 0x88c,
        "VIDEO_MONITOR_STATUS3": 0x890, "VIDEO_MONITOR_STATUS4": 0x894, "VIDEO_MONITOR_STATUS5": 0x898,
        "VIDEO_MONITOR_STATUS6": 0x89c, "LINK_CONFIG0": 0x968, "FLT_CONFIG1": 0x164,
        "FRL_RSFEC_STATUS0": 0xa30, "FRL_PKTZ_STATUS1": 0xa54, "PKTSCHED_PKT_EN": 0xaa8,
        "PKTSCHED_PKT_CONTROL0": 0xaac, "PKTSCHED_PKT_STATUS0": 0xab4, "PKTSCHED_PKT_STATUS1": 0xab8}
fd = os.open("/dev/mem", os.O_RDONLY | os.O_SYNC)
m = mmap.mmap(fd, 0x4000, mmap.MAP_SHARED, mmap.PROT_READ, offset=BASE)
for k, off in REGS.items():
    if off is None:
        continue
    print(f"{k:26s} 0x{off:04x} = 0x{struct.unpack_from('<I', m, off)[0]:08x}")
