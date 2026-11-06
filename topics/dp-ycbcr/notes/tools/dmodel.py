#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0
"""DP-1 accept/refuse + expected format model (dw-dp bus format negotiation), sink parameters from a JSON
(sink-DP-1.json, filled from the board: DPCD 0x0000-0x000f + 0x2210, EDID): {"lanes": 4, "rate_khz": 540000,
"edid_bpc": 10, "color_formats": ["RGB", "444", "422"], "y420_vics": [...], "vsc_sdp": true, "dfp_tmds_khz": 0,
"dfp_max_bpc": 0, "y420_passthrough": false}

expect(mode, cf, maxbpc) -> None or dict(fmt, bpc). Mirrors dw_dp_bridge_atomic_get_output_bus_fmts(): the
first entry of dw_dp_output_formats[] (RGB10, RGB8, 444-10, 444-8, 422-10, 422-8, 420-10, 420-8, RGB6) that
passes bpc <= max_bpc (drm core: min(property, EDID bpc or 8)), sink colour formats, 4:2:0 rules (VSC SDP,
mode 4:2:0 capable), link bandwidth (lanes x rate x 8/10) and a downstream TMDS converter's clock; then
filtered by the "color format" property."""
import json

TABLE = [("RGB", 10, 30), ("RGB", 8, 24), ("444", 10, 30), ("444", 8, 24), ("422", 10, 20), ("422", 8, 16),
         ("420", 10, 15), ("420", 8, 12), ("RGB", 6, 18)]
CF = {"AUTO": None, "RGB": "RGB", "YUV 4:4:4": "444", "YUV 4:2:2": "422", "YUV 4:2:0": "420", None: None}


def load(p):
    return json.load(open(p))


def bw_ok(s, clock, bpp):
    # dw_dp_bandwidth_ok(): mode clock x bpp against lanes x link rate x 8/10 (8b/10b)
    return clock * bpp <= s["lanes"] * s["rate_khz"] * 8


def tmds_ok(s, clock, bpc, fmt):
    if not s.get("dfp_tmds_khz"):
        return True
    t = clock if fmt == "422" else (clock / 2 if fmt == "420" else clock) * bpc / 8
    return t <= s["dfp_tmds_khz"]


def expect(s, m, vic420, cf, maxbpc):
    eff = min(maxbpc if maxbpc else 99, s.get("edid_bpc") or 8)
    want = CF[cf]
    for fmt, bpc, bpp in TABLE:
        if bpc > eff:
            continue
        if s.get("dfp_max_bpc") and bpc > s["dfp_max_bpc"]:
            continue
        if fmt not in s["color_formats"] + ["RGB"]:
            continue
        if fmt == "420" and not (s["vsc_sdp"] and (not s.get("dfp_tmds_khz") or s.get("y420_passthrough")) and vic420):
            continue
        if not bw_ok(s, m["clock"], bpp) or not tmds_ok(s, m["clock"], bpc, fmt):
            continue
        if want and fmt != want:
            continue
        return dict(fmt=fmt, bpc=bpc)
    return None
