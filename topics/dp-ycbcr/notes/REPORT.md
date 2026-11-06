# DP never outputs YCbCr on 7.3.0-15: root cause, fix, results

State: DONE, verified on the board. Branch `k15-dpycc` in src/linux (worktree build/wt-k15dpycc) is k15-v4 plus 4 commits.
Test kernel 15ycc1: debs in out/test/k15ycc1/debs. It was built from the same tree; only commit messages were reworded after the build.
The board is back on stock `#15 SMP PREEMPT_DYNAMIC Wed Nov 4 20:25:22` (restore rc=0, usb_missing empty, 04:30:02).
Nothing was sent anywhere.

## Summary

On the USB-C (DP alt mode) chain the connector "color format" property was never applied.
`drm_atomic_bridge_chain_select_bus_fmts()` checks it only against the **last** bridge's output formats.
On this board the last bridge is the USB-C connector's AUX HPD bridge, which has no bus-format hooks.
So the chain ends in `MEDIA_BUS_FMT_FIXED`, which `bus_format_is_color_fmt()` accepts for every colour format.
dw-dp then receives FIXED, offers its whole output list, and the first entry (RGB101010 or RGB888) wins.

The fix is in dw-dp, the layer that owns the format list and receives FIXED:
- it filters its output formats by the requested colour format, as the vendor driver does;
- it offers 4:2:0 only for 4:2:0-capable modes;
- in the core, a failed bus-format negotiation now returns -EINVAL instead of the internal -ENOTSUPP (524).

Effect on the full native-DP matrix (370 cases, 37 modes x 8/10 bpc x 5 formats):
- YCbCr 4:4:4 and 4:2:2: before, 0/148 got the requested bus format; after, 148/148, all camera GOOD.
- YCbCr 4:2:0 (the LU28R55 EDID has no 4:2:0): before, 74/74 accepted and sent as RGB; after, 74/74 refused with EINVAL.
- AUTO and RGB: unchanged, 148/148 GOOD.
- The HDR smoke on DP passes at both modes, with RGB, 4:4:4 and 4:2:2 under PQ.

## Root cause (code refs are k15-v4, build/wt-k15v4)

Bridge chain for DP0 on the OPi5:
`dw-dp` (drivers/gpu/drm/bridge/synopsys/dw-dp.c) -> `drm_aux_bridge` registered by the USB-DP PHY
(drivers/phy/rockchip/phy-rockchip-usbdp.c:1649, drivers/gpu/drm/bridge/aux-bridge.c:107) -> `drm_aux_hpd_bridge` of the
Type-C DP alt mode (drivers/gpu/drm/bridge/aux-hpd-bridge.c:168). Neither aux bridge implements
`atomic_get_output_bus_fmts`/`atomic_get_input_bus_fmts`. The DT is rk3588s-orangepi-5-5b.dtsi: `dp0_out -> usbdp_phy0_dp_in`.

1. `drm_atomic_bridge_chain_select_bus_fmts()` (drivers/gpu/drm/drm_bridge.c:1264): the last bridge has no
   `atomic_get_output_bus_fmts`, so `out_bus_fmts[0] = MEDIA_BUS_FMT_FIXED`. The colour format filter
   `bus_format_is_color_fmt()` (drm_bridge.c:1188) returns true for FIXED whatever the request is. This is the
   only place the "color format" is applied.
2. `select_bus_fmt_recursive()`: the bridges without `atomic_get_input_bus_fmts` pass FIXED upstream (drm_bridge.c:1124).
   At the first bridge (dw-dp), `input_bus_cfg.format = in_bus_fmts[0]` (drm_bridge.c:1164).
3. `dw_dp_bridge_atomic_get_input_bus_fmts()` (dw-dp.c:2474) returns its full output list for FIXED.
   `dw_dp_bridge_atomic_get_output_bus_fmts()` (dw-dp.c:2414) filters by max bpc, sink colour formats, VSC SDP,
   bandwidth and DFP TMDS clock, but never by the colour format request. `dw_dp_output_formats[]` starts
   RGB101010, RGB888, so the result is RGB101010 at max bpc 10 and RGB888 at 8.
4. `dw_dp_bridge_atomic_check()` (dw-dp.c:1799) and `dw_dp_encoder_atomic_check()` (rockchip/dw_dp-rockchip.c) use that
   input format for the MSA/VSC SDP and the VOP2 output mode, so VOP2 reads back 0x100a/0x1018.

Confirmed on stock 15 with drm.debug=0x14 (probe-stock15/, 20 commits on DP-1, modes 0 = 3840x2160@60 and
5 = 1920x1080@60, max bpc 8/10). Every commit was accepted, the log said `Found bridge chain ending with bus format 0x0001`
(FIXED), and VP2 (DP-1) read back RGB888/RGB101010 for every request, 4:2:0 included.

Patch 2264 (259e5a61, "drm/rockchip: dw_dp: Attach the "color format" connector property") rests on this wrong premise.
Its commit message and code comment say the chain negotiation already honours the request; on this chain it never did.

### Vendor BSP (linux-orangepi 6.1, drivers/gpu/drm/rockchip/dw-dp.c)
- In the vendor tree dw-dp is the connector itself (last bridge). `dw_dp_bridge_atomic_get_output_bus_fmts()` (V61 :4595)
  filters `possible_output_fmts[]` by its own "color_format"/"color_depth" connector properties (RK_IF_PROP_COLOR_FORMAT).
  The colour request is therefore applied inside dw-dp, which is the approach used here, with the mainline property.
- The vendor driver offers 4:2:0 only when `drm_mode_is_420(di, &mode)` is true; mainline dw-dp lacked that check (patch 1).

### Does accepted-but-ignored violate the property contract?
Yes. drm_connector.c, DOC "Color format": whether a format can be output "is determined during the atomic check phase",
and a userspace that sets a non-AUTO value "should check whether its atomic commit succeeded". A commit that succeeds must
therefore output the requested format. Before the fix, 222/222 YCbCr requests succeeded and were sent as RGB; 74 of them were
4:2:0, which the sink cannot take at all.

### HDR path (VSC SDP colorimetry, our 0009 = c8201140)
It does not assume YCbCr. `dw_dp_send_vsc_sdp()` derives pixel encoding, colorimetry (BT2020_RGB vs BT2020_YCC) and
dynamic range from `state->color_format`, i.e. from the negotiated bus format. Before the fix the YCbCr branches were
unreachable on native DP except through AUTO fallback. The DP HDR smoke on 15ycc1 now exercises them:
YUV10 4:4:4 and YUYV10 4:2:2 under PQ commit and read back correctly. The MSA MISC0 and VOP2 BT.2020 matrix selection follow the
same bus format.

### Why the USB-C -> HDMI adapter (PCON) did show YCbCr 4:2:0
Same bridge chain, same bug: the colour format request is ignored there too. Those runs used "AUTO". dw-dp's own filters
(`dw_dp_dfp_tmds_clock_ok()`, bandwidth) removed every RGB format at 4K60 behind the 300 MHz TMDS converter, so the
first remaining entry was 4:2:0. That is a correct AUTO fallback, not the colour format property working.

## Patches (branch k15-dpycc, `git format-patch` in patches/)

1 and 2 are the fix. 3 is a fixup to squash into 2264 (its comment was wrong). 4 is the core errno fix the new behaviour
exposes. checkpatch: clean, except the expected "ENOTSUPP is not a SUSV4 error code" on patch 4, which is the line that
removes ENOTSUPP from the uAPI path.
When these go into patches/linux, 2264's commit message should also drop the claim that the negotiation "already skips every
output bus format that does not match"; reorder so patch 2 comes before 2264.

#### bee9b643f073 drm/bridge: synopsys: dw-dp: Offer YCbCr 4:2:0 only for 4:2:0 capable modes

```
drm/bridge: synopsys: dw-dp: Offer YCbCr 4:2:0 only for 4:2:0 capable modes

dw_dp_bridge_atomic_get_output_bus_fmts() lists the YCbCr 4:2:0 bus
formats whenever the sink declares YCbCr 4:2:0 support for any mode and
the link can carry the VSC SDP. A sink only accepts YCbCr 4:2:0 for the
modes listed in its YCbCr 4:2:0 Video Data Block or Capability Map Data
Block, so a mode outside those lists (e.g. 1920x1080 on a TV that does
4:2:0 at 3840x2160 only) could be driven as YCbCr 4:2:0 and show no
picture.

Skip the 4:2:0 formats for modes that are neither 4:2:0-only nor
4:2:0-also, as dw_dp_bridge_mode_valid() already does when it sizes the
minimum bandwidth, and as the downstream Rockchip driver and i915 do.

Assisted-by: LLM
Signed-off-by: Arun Iyengar <aiyengar1990@gmail.com>

```

Diffstat:  1 file changed, 1 insertion(+), 1 deletion(-)

#### 87bd9354dc7f drm/bridge: synopsys: dw-dp: Honour the connector color format

```
drm/bridge: synopsys: dw-dp: Honour the connector color format

drm_atomic_bridge_chain_select_bus_fmts() applies the connector "color
format" only to the output bus formats of the last bridge in the chain.
On RK3588 the DW DP controller is followed by bridges that do not take
part in bus format negotiation (the USB-DP PHY's AUX bridge and the
USB-C connector's AUX HPD bridge for DP alt mode, or a dp-connector).
The last of them has no atomic_get_output_bus_fmts(), so the chain ends
in MEDIA_BUS_FMT_FIXED, which matches every color format, and dw-dp gets
FIXED as its output format and picks the first entry of its own list.
With the "color format" property attached to the connector, every YCbCr
4:4:4, 4:2:2 and 4:2:0 request was accepted by the atomic check and then
sent as RGB: on a DP monitor with RGB, 4:4:4 and 4:2:2 support all 222
YCbCr test cases came out as RGB888 or RGB101010, and 4:2:0 was accepted
although the sink has no 4:2:0 support at all. The property
documentation promises the opposite: a commit that succeeds outputs the
requested format, one that cannot be met fails.

Filter the DP output formats by the requested color format in
dw_dp_bridge_atomic_get_output_bus_fmts(), which also serves as the
input format list when the next bridge reports FIXED. A request the
sink, the link or a protocol converter cannot carry now leaves no format
and fails the atomic check. With "AUTO" nothing changes. When dw-dp is
the last bridge, the core filter becomes redundant but agrees.

The downstream Rockchip driver filters its output format list by its
own "color_format" connector property the same way.

Assisted-by: LLM
Signed-off-by: Arun Iyengar <aiyengar1990@gmail.com>

```

Diffstat:  1 file changed, 31 insertions(+)

#### 950372cb5aaf fixup! drm/rockchip: dw_dp: Attach the "color format" connector property

```
fixup! drm/rockchip: dw_dp: Attach the "color format" connector property

The comment claimed the bridge chain negotiation honours the requested
color format; on the USB-C chain it does not, dw-dp applies it.

Assisted-by: LLM
Signed-off-by: Arun Iyengar <aiyengar1990@gmail.com>

```

Diffstat:  1 file changed, 2 insertions(+), 3 deletions(-)

#### a875690f77ea drm/bridge: Fail an unsatisfiable bus format negotiation with -EINVAL

```
drm/bridge: Fail an unsatisfiable bus format negotiation with -EINVAL

drm_atomic_bridge_chain_select_bus_fmts() reports that no chain of bus
formats fits with -ENOTSUPP, and drm_atomic_bridge_chain_check() passes
that straight back through drm_atomic_helper_check_modeset() to the
atomic and legacy modeset ioctls. -ENOTSUPP (524) is a kernel-internal
code that userspace does not know; for a configuration the hardware
cannot do the atomic API returns -EINVAL. Since the connector "color
format" property makes the negotiation fail for any requested format a
bridge chain cannot output, userspace now hits this routinely: a DW DP
connector asked for YCbCr 4:2:0 on a sink without 4:2:0 support gets
here with no matching format and would fail the atomic commit with
errno 524, where an HDMI connector asked for the same returns EINVAL
from the HDMI state helper.

Return -EINVAL when the negotiation finds no chain, with a debug
message naming the encoder.

Assisted-by: LLM
Signed-off-by: Arun Iyengar <aiyengar1990@gmail.com>

```

Diffstat:  1 file changed, 11 insertions(+)

## Before / after

### Targeted probe, DP-1 (kmsctl commit + VOP2 summary + drm.debug), probe-stock15/ and probe-ycc1/

Before (stock 7.3.0-15): every request accepted, DP-1 bus format always RGB:

| mode | max bpc | color format | commit | errno/err | DP-1 bus format | output_mode | last-bridge fmt |
|---|---|---|---|---|---|---|---|
| 0 | 8 | AUTO | OK |  | 100a RGB888_1X24 | f | 0x0001 |
| 0 | 8 | RGB | OK |  | 100a RGB888_1X24 | f | 0x0001 |
| 0 | 8 | YUV444 | OK |  | 100a RGB888_1X24 | f | 0x0001 |
| 0 | 8 | YUV422 | OK |  | 100a RGB888_1X24 | f | 0x0001 |
| 0 | 8 | YUV420 | OK |  | 100a RGB888_1X24 | f | 0x0001 |
| 0 | 10 | AUTO | OK |  | 1018 RGB101010_1X30 | f | 0x0001 |
| 0 | 10 | RGB | OK |  | 1018 RGB101010_1X30 | f | 0x0001 |
| 0 | 10 | YUV444 | OK |  | 1018 RGB101010_1X30 | f | 0x0001 |
| 0 | 10 | YUV422 | OK |  | 1018 RGB101010_1X30 | f | 0x0001 |
| 0 | 10 | YUV420 | OK |  | 1018 RGB101010_1X30 | f | 0x0001 |
| 5 | 8 | AUTO | OK |  | 100a RGB888_1X24 | f | 0x0001 |
| 5 | 8 | RGB | OK |  | 100a RGB888_1X24 | f | 0x0001 |
| 5 | 8 | YUV444 | OK |  | 100a RGB888_1X24 | f | 0x0001 |
| 5 | 8 | YUV422 | OK |  | 100a RGB888_1X24 | f | 0x0001 |
| 5 | 8 | YUV420 | OK |  | 100a RGB888_1X24 | f | 0x0001 |
| 5 | 10 | AUTO | OK |  | 1018 RGB101010_1X30 | f | 0x0001 |
| 5 | 10 | RGB | OK |  | 1018 RGB101010_1X30 | f | 0x0001 |
| 5 | 10 | YUV444 | OK |  | 1018 RGB101010_1X30 | f | 0x0001 |
| 5 | 10 | YUV422 | OK |  | 1018 RGB101010_1X30 | f | 0x0001 |
| 5 | 10 | YUV420 | OK |  | 1018 RGB101010_1X30 | f | 0x0001 |

After (15ycc1):

| mode | max bpc | color format | commit | errno/err | DP-1 bus format | output_mode | last-bridge fmt |
|---|---|---|---|---|---|---|---|
| 0 | 8 | AUTO | OK |  | 100a RGB888_1X24 | f | 0x0001 |
| 0 | 8 | RGB | OK |  | 100a RGB888_1X24 | f | 0x0001 |
| 0 | 8 | YUV444 | OK |  | 2025 YUV8_1X24 | f | 0x0001 |
| 0 | 8 | YUV422 | OK |  | 2011 YUYV8_1X16 | c | 0x0001 |
| 0 | 8 | YUV420 | FAIL | Invalid argument (22) | - | - | 0x0001 |
| 0 | 10 | AUTO | OK |  | 1018 RGB101010_1X30 | f | 0x0001 |
| 0 | 10 | RGB | OK |  | 1018 RGB101010_1X30 | f | 0x0001 |
| 0 | 10 | YUV444 | OK |  | 2016 YUV10_1X30 | f | 0x0001 |
| 0 | 10 | YUV422 | OK |  | 200d YUYV10_1X20 | c | 0x0001 |
| 0 | 10 | YUV420 | FAIL | Invalid argument (22) | - | - | 0x0001 |
| 5 | 8 | AUTO | OK |  | 100a RGB888_1X24 | f | 0x0001 |
| 5 | 8 | RGB | OK |  | 100a RGB888_1X24 | f | 0x0001 |
| 5 | 8 | YUV444 | OK |  | 2025 YUV8_1X24 | f | 0x0001 |
| 5 | 8 | YUV422 | OK |  | 2011 YUYV8_1X16 | c | 0x0001 |
| 5 | 8 | YUV420 | FAIL | Invalid argument (22) | - | - | 0x0001 |
| 5 | 10 | AUTO | OK |  | 1018 RGB101010_1X30 | f | 0x0001 |
| 5 | 10 | RGB | OK |  | 1018 RGB101010_1X30 | f | 0x0001 |
| 5 | 10 | YUV444 | OK |  | 2016 YUV10_1X30 | f | 0x0001 |
| 5 | 10 | YUV422 | OK |  | 200d YUYV10_1X20 | c | 0x0001 |
| 5 | 10 | YUV420 | FAIL | Invalid argument (22) | - | - | 0x0001 |

("last-bridge fmt" stays 0x0001: the AUX HPD bridge still ends the chain with FIXED; dw-dp now applies the request itself.
output_mode c = ROCKCHIP_OUT_MODE_S888_DUMMY for 4:2:2, f = AAAA.)

### Native-DP colour x bpc matrix (lists dp_00..dp_03, 370 cases, camera judged; tools/cmp.py)

Before = work/_out/k14/hdmi-formats/run-dp_0[0-3]-2* (stock 15); after = run-15ycc1-dp_0[0-3].c* (15 cases per chunk).

#### before: stock 7.3.0-15 (370 cases)

| requested | cases | commit accepted | rejected (errno) | bus format = request | camera GOOD (of accepted) |
|---|---|---|---|---|---|
| AUTO | 74 | 74 | 0  | 74/74 | 74/74 |
| RGB | 74 | 74 | 0  | 74/74 | 74/74 |
| 444 | 74 | 74 | 0  | 0/74 | 74/74 |
| 422 | 74 | 74 | 0  | 0/74 | 74/74 |
| 420 | 74 | 74 | 0  | 0/74 | 74/74 |

#### after: 15ycc1 (k15-dpycc) (370 cases)

| requested | cases | commit accepted | rejected (errno) | bus format = request | camera GOOD (of accepted) |
|---|---|---|---|---|---|
| AUTO | 74 | 74 | 0  | 74/74 | 74/74 |
| RGB | 74 | 74 | 0  | 74/74 | 74/74 |
| 444 | 74 | 74 | 0  | 74/74 | 74/74 |
| 422 | 74 | 74 | 0  | 74/74 | 74/74 |
| 420 | 74 | 0 | 74 22 | 0/0 | 0/0 |

#### after: accepted cases that are not GOOD or not the requested format


cases in before but not after: 0 

After, bus format per request and bpc (accepted cases, 37 modes each): 8 bpc RGB/AUTO 100a, 4:4:4 2025, 4:2:2 2011;
10 bpc RGB/AUTO 1018, 4:4:4 2016, 4:2:2 200d. 4:2:0: 74/74 EINVAL. The LU28R55 EDID has no 4:2:0
(feature byte 0x3b = RGB+4:4:4+4:2:2, CTA byte3 0xf0, no Y420 blocks), so this is the correct refusal.
Under the display rules it counts as NOT TESTED, not FAIL.
No WARNING/BUG/Oops in any dmesg.

### DP HDR smoke (lists/dp_hdr15.tsv, run-15ycc1-dp_hdr15.c00; PQ metadata, max bpc 10, XR30 AFBC)

| case | commit | VOP2 bus fmt |
|---|---|---|
| DH0_10_AUTO_RGB_pq | OK | 1018/f |
| DH0_10_RGB_RGB_pq | OK | 1018/f |
| DH0_10_YUV444_YCC_pq | OK | 2016/f |
| DH0_10_YUV422_YCC_pq | OK | 200d/c |
| DH0_10_YUV420_YCC_pq | EINVAL | - |
| DH0_10_YUV444_RGB_pq | OK | 2016/f |
| DH0_10_AUTO_sdr | OK | 1018/f cam GOOD |
| DH5_10_AUTO_RGB_pq | OK | 1018/f |
| DH5_10_RGB_RGB_pq | OK | 1018/f |
| DH5_10_YUV444_YCC_pq | OK | 2016/f |
| DH5_10_YUV422_YCC_pq | OK | 200d/c |
| DH5_10_YUV420_YCC_pq | EINVAL | - |
| DH5_10_YUV444_RGB_pq | OK | 2016/f |
| DH5_10_AUTO_sdr | OK | 1018/f cam GOOD |

PQ cases use the "levels" kind (frames kept in c/<id>/, no verdict); the SDR return cases are camera GOOD.

### Sanity

- DP sane (run-15ycc1-dp_sane.c00): D0_8_RGB, D5_8_AUTO, D5_10_AUTO all GOOD.
- HDMI sane (run-15ycc1-sane.c00 and .try1-darkcam): H0_8_420 GOOD, H19_8_RGB GOOD. H16_10_444 (2560x1440, 10 bpc 4:4:4, FRL) was
  judged SCRAMBLED twice. Its readback is identical to the stock-15 GOOD run: bus 2016/f, same AVI, FRL 10G x4, dclk 497.75 MHz.
  The frames show the correct pattern with the same code cells as the stock GOOD frame. The room was nearly dark (ambient 2.3)
  and camcheck_shared's pattern fit scored 2.79, under its 3.0 threshold; H19 in the same light scored 3.01.
  This is a low-light camera margin on an HDMI path the patches do not touch.
  -> work-list item: camcheck fit threshold is too tight in a dark room (owner of k14/hdmi-formats/tools).

## How it was run (files)

- tools/ycc.sh: resumable harness (dev/test modes, BOARD-WANT/BOARD-PAUSE aware, FCFS queue, chunked fmtck, results copied per
  chunk, stock 15 restored on every yield). tools/probetab.py, tools/cmp.py: tables. ycc.log: full session log.
- Lists are copies of k14/hdmi-formats/lists plus lists/dp_hdr15.tsv (new).
- Incident (11:45-12:04 on 11-05): on BOARD-PAUSE my harness started a stock restore. I SIGSTOPped install-check after dpkg
  to avoid the reboot; the coordinator resumed it. The harness now holds position with the lock on BOARD-PAUSE and never stops children.
