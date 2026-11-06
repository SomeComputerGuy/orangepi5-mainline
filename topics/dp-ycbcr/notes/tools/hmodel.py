#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0
"""HDMI accept/refuse + expected wire format model for the Beyond TV EDID (k14/hdr/edid/HDMI-A-1.edid) on RK3588
dw-hdmi-qp, mirroring drm_hdmi_state_helper (hdmi_compute_config) plus the source limits.

expect(mode, cf, maxbpc) -> None (refuse) or dict(fmt, bpc, tmds_khz, frl, vic, q, yq, c)
  fmt: RGB|444|422|420 actually chosen; bpc: output bpc; q: AVI RGB quantization expected (L/F) for RGB,
  yq for YCbCr (L); c: AVI colorimetry field (0 none, 1 601, 2 709)."""
import json, sys

# CEA timings we may meet: vic -> (hact, vact, htotal, vtotal, clock kHz at the integer rate)
CEA = {1: (640, 480, 800, 525, 25200), 2: (720, 480, 858, 525, 27027), 4: (1280, 720, 1650, 750, 74250),
       16: (1920, 1080, 2200, 1125, 148500), 19: (1280, 720, 1980, 750, 74250), 31: (1920, 1080, 2640, 1125, 148500),
       32: (1920, 1080, 2750, 1125, 74250), 33: (1920, 1080, 2640, 1125, 74250), 34: (1920, 1080, 2200, 1125, 74250),
       63: (1920, 1080, 2200, 1125, 297000), 64: (1920, 1080, 2640, 1125, 297000),
       93: (3840, 2160, 5500, 2250, 297000), 94: (3840, 2160, 5280, 2250, 297000), 95: (3840, 2160, 4400, 2250, 297000),
       96: (3840, 2160, 5280, 2250, 594000), 97: (3840, 2160, 4400, 2250, 594000), 98: (4096, 2160, 5500, 2250, 297000),
       99: (4096, 2160, 5280, 2250, 297000), 100: (4096, 2160, 4400, 2250, 297000), 101: (4096, 2160, 5280, 2250, 594000),
       102: (4096, 2160, 4400, 2250, 594000), 117: (3840, 2160, 5280, 2250, 1188000), 118: (3840, 2160, 4400, 2250, 1188000)}
SD_VICS = {2, 3, 6, 7, 17, 18, 21, 22}
Y420_ALSO = {97, 96, 102, 101, 118}     # Y420CMDB 0x1f over the first 5 SVDs of the VDB
Y420_ONLY = set()
DC_RGB = {10, 12}; DC_Y444 = {10, 12}; DC_Y420 = {10, 12}   # EDID: DC_30 + DC_36 (+ DC_Y444), HF-VSDB DC_420 30/36/48
MAX_TMDS = 600000                         # HF-VSDB max TMDS 600 MHz
FRL_GBPS = 40                            # sink 12G x4, source capped at 10G x4 (rk3588_hdmi_cfg.max_frl_rate_per_lane)
SRC_MAX_BPC = 10                         # plat_data.max_bpc (hardware: up to 10 bit, datasheet + vendor GRF)
QS = True                                # VCDB QS=1, QY=1


def vic_of(m):
    for v, (ha, va, ht, vt, clk) in CEA.items():
        if (m["hdisplay"], m["vdisplay"], m["htotal"], m["vtotal"]) == (ha, va, ht, vt) and \
                (abs(m["clock"] - clk) <= 1 or abs(m["clock"] - clk / 1.001) <= 2):
            if v == 2 and (m.get("flags", 0) >> 19) & 0xf == 2:   # DRM_MODE_FLAG_PIC_AR_16_9
                return 3
            return v
    return 0


def tmds(clock, bpc, fmt):
    if fmt == "422":
        return clock
    r = clock / 2 if fmt == "420" else clock
    return r * bpc / 8


def frl_ok(clock, bpc, fmt):
    bpp = {"RGB": 3 * bpc, "444": 3 * bpc, "422": 24, "420": 1.5 * bpc}[fmt]
    return clock * 1e3 * bpp <= FRL_GBPS * 1e9 * 16 / 18


def sink_ok(vic, fmt, bpc, m):
    if vic == 1 and bpc != 8:
        return False
    if fmt == "420":
        if vic not in Y420_ALSO | Y420_ONLY:
            return False
        return bpc == 8 or bpc in DC_Y420
    if vic in Y420_ONLY:
        return False
    if fmt == "RGB":
        return bpc == 8 or bpc in DC_RGB
    if fmt == "444":
        return bpc == 8 or bpc in DC_Y444
    return bpc <= 12            # 422


def try_fmt(m, vic, fmt, maxbpc):
    for bpc in range(maxbpc, 7, -2):
        if not sink_ok(vic, fmt, bpc, m):
            continue
        t = tmds(m["clock"], bpc, fmt)
        if t <= MAX_TMDS:
            return bpc, t, False
        if frl_ok(m["clock"], bpc, fmt):
            return bpc, t, True
    return None


def expect(m, cf, maxbpc):
    maxbpc = max(8, min(maxbpc, SRC_MAX_BPC))
    vic = vic_of(m)
    order = {"AUTO": ["RGB", "420"], "RGB": ["RGB"], "YUV 4:4:4": ["444"], "YUV 4:2:2": ["422"],
             "YUV 4:2:0": ["420"]}[cf]
    for fmt in order:
        r = try_fmt(m, vic, fmt, maxbpc)
        if r:
            bpc, t, frl = r
            lim_default = vic not in (0, 1)
            q = ("L" if lim_default else "F") if fmt == "RGB" else "L"
            c = 0 if fmt == "RGB" else (1 if vic in SD_VICS else 2)
            return dict(fmt=fmt, bpc=bpc, tmds_khz=round(t), frl=frl, vic=vic, q=q, c=c)
    return None


if __name__ == "__main__":
    lst = json.load(open(sys.argv[1]))
    hc = next(c for c in lst["connectors"] if c["name"] == "HDMI-A-1")
    for i, m in enumerate(hc["modes"]):
        print(i, m["name"], m["clock"], vic_of(m), {cf: expect(m, cf, 10) for cf in ("AUTO",)})
