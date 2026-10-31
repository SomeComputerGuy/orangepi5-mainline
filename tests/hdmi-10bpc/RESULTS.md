# HDMI-A-1 black at 3840x2160@60 10 bpc RGB (FRL): root cause and fix

Status: root cause identified from the code and from read-only board state. The fix builds. It has
**not** been tested on the board yet (see "Board test plan").

## What the board shows (read-only, via the serial console, kernel 7.3.0-opi5 / 7.3.0-6)
- Connector state: max_requested_bpc=10, output_bpc=10, output_format=RGB, tmds_char_rate=742500000.
- `HDMI-A-1/scdc_status`: **FRL Rate 10 Gbit/s x 4 lanes**, Channel 0-2 and Lane 3 locked, 0 errors on every
  lane, 0 RS corrections, Scrambling Enabled no, TMDS Bit Clock Ratio 1/10. So the source picked
  FRL and the link trained cleanly. The 742.5 MHz is *not* being sent over TMDS.
- Clocks: dclk_vop0 is 594 MHz from gpll (CRU). That is expected: 594 MHz > 600 MHz*8/10, so VOP2
  does not use the HDMI PHY PLL (same as the vendor kernel's `vop2_is_dclk_switch_to_cru_pll()`).
- When I read the state later, both CRTCs were inactive (greeter idle blank). So clock and ACLK values read
  at that point (aclk_vop 500 MHz) are not the live FRL state and are not evidence of anything.

## EDID facts (hdmi-a-1.edid, 4 blocks, all checksums OK; decoded in edid-hdmi-blocks.txt)
- Monitor name "Beyond TV". CTA rev 3, YCbCr 4:4:4 and 4:2:2 supported.
- HDMI VSDB: DC_30bit=1, DC_36bit=1, DC_Y444=1, Max_TMDS_Clock 340 MHz.
- HF-VSDB: **Max_TMDS_Character_Rate 600 MHz**, SCDC present, **Max_FRL_Rate 6 (12 Gbps x 4 = 48G)**,
  DC_420 30/36/48 = 1.
- So 4K60 RGB 10 bpc (742.5 MHz) cannot be sent over TMDS. It needs FRL, which both sink and source
  (RK3588: up to 10G x 4) support.

## Ruling out (a) and checking (b)
- (a) TMDS validation is correct. `hdmi_clock_valid()` (drm_hdmi_state_helper.c) sends any rate above
  `HDMI_2_0_TMDS_CHAR_RATE_MAX_HZ`, or above the source/sink max, down the FRL path. Without FRL on
  both ends it returns MODE_CLOCK_HIGH. `hdmi_compute_clock()` then sets frl_rate_per_lane/lanes and
  clears scrambler_needed. SCDC on the board confirms FRL. Existing KUnit cases already cover deep color
  over FRL and the TMDS fallback (`drm_test_check_frl_rate_rgb_12bpc`, `..._sink_unsupported`,
  `..._source_rate_capped`, ...). Choosing FRL here is legitimate, so I added no helper change or KUnit
  case.
- (b) The helper's choice is fine: 10G x 4 is the source maximum, and the FRL link itself is healthy. What
  breaks is the 10 bpc video path inside the FRL configuration.

## Root cause (c: Rockchip glue, from the 0300 series)
`drivers/phy/rockchip/phy-rockchip-samsung-hdptx.c: rk_hdptx_frl_lcpll_cmn_config()` programs
`CMN_REG(0086) PLL_PCG_CLK_SEL = (hdmi_cfg.bpc - 8) >> 1` in FRL mode too. That is the color-depth select
of the PHY pixel clock generator. But `dw_hdmi_qp_rockchip_encoder_atomic_check()`
(drivers/gpu/drm/rockchip/dw_hdmi_qp-rockchip.c, added by 0300-098 "Wire up FRL operating mode" and touched
by 0300-120) sets `phy_cfg.hdmi.bpc` **only in the TMDS branch**. For FRL it stays 0, and
`rk_hdptx_phy_verify_hdmi_config()` turns that into `bpc = 8`.

Result: at 10 bpc FRL, the GRF says 10 bpc (enc_init) and VOP2 sends 30-bit RGB, but the PHY PCG is
set up for 8 bpc. The link trains and locks (link-layer only) and the screen is black. 8 bpc FRL
(4K120, the earlier tests) matches the default, which is why it worked.

The vendor glue (`work/_downloads/hdmi-frl/bsp/dw_hdmi_qp-rockchip.c`, around line 2688) does
`phy_cfg.bpc = color_depth` in the FRL branch, so it does not have this bug.

The same omission is in `dw_hdmi_qp_rk3588_set_frl_rate()`, the FLT fallback path, which calls
`phy_configure()` with only rate and lanes. Any FRL rate fallback would reset the PHY to 8 bpc.

## Fix
`0001-drm-rockchip-dw_hdmi_qp-Pass-color-depth-to-the-PHY-.patch` (git format-patch against
build/linux = branch `opi5/hdmi-10bpc-7.3`, based on `opi5/image-k7-7.3`, worktree
`build/wt-hdmi-10bpc`). The patch has exactly one trailer, `Assisted-by: Claude:claude-opus-5-5`.
- Computes `phy_cfg.hdmi.bpc` once for both TMDS and FRL. The existing YUV422 → 8 override is kept.
- Caches it in `rockchip_hdmi_qp.phy_bpc` and passes it again in `.set_frl_rate()`.
- It could also be squashed into 0300-098 when the series is next refreshed, since the series is not
  posted yet.

Build: `make O=build/wt-hdmi-10bpc-out LOCALVERSION= W=1 drivers/gpu/drm/rockchip/` (config copied from
build/linux/.config) builds rockchipdrm.o with no warnings. checkpatch --strict reports only the expected
missing Signed-off-by.

## Not fixed / notes
- The 8G x 4 FRL path (`rk_hdptx_frl_lcpll_ropll_cmn_config`, cascade mode) uses a fixed init value
  `CMN_REG(0086)=0x11` (PCG_CLK_SEL=0) and ignores bpc. The vendor PHY driver does the same. RK3588 only
  reaches it on a training fallback. Leave it unless the board shows 10 bpc failing at 8G x 4.
- The vendor glue writes GRF COLOR_DEPTH=8BPC for YUV422 10-bit (YUYV10). Ours (enc_init) writes 10BPC
  whenever output_bpc==10. This does not matter here (RGB). It is worth checking if 10-bit YUV422 ever
  looks wrong.

## Board test plan (needs your scheduling; nothing was changed on the board)
1. Install the kernel with this patch (only rockchipdrm.ko changes). Boot the desktop image with the same
   two monitors.
2. At the GDM greeter (XR30 AFBC, max bpc 10), HDMI-A-1 should show a picture at 4K60. Check that the
   connector state is still output_bpc=10 RGB, tmds_char_rate=742500000, and that scdc_status shows FRL
   10G x 4 locked with 0 errors.
3. Regression: `modetest` 4K120 8 bpc (FRL), 4K60 8 bpc (TMDS), 1080p, and 4K60 10-bit YUV420/YUV422 if
   forced via the "color format" property. Check that HDMI audio still plays after mode changes.
4. Optional, if the setup allows: force a lower FRL rate to exercise `.set_frl_rate()` at 10 bpc.

---------------------------------------------------------------------------------------------------
## Update after board test of 1203 (coordinator): STILL BLACK

### Does 1203 reach the hardware?
The code path says it does:
- `atomic_check` → `phy_set_mode_ext(FRL)` → `phy_configure(bpc=10, frl 10x4)`.
  `verify_hdmi_config` sets hdmi_cfg.rate = 100M*4*10 = 4e9 and bpc = 10, and marks pll_config_dirty.
- Bridge enable → `phy.ops->init` → power_on/consumer_get → `rk_hdptx_pll_cmn_config()`. The rate is
  4e9, which is neither <= 600M nor FRL_8G4L_RATE, so it calls `rk_hdptx_frl_lcpll_cmn_config()`. That
  writes PCG_CLK_SEL = (10-8)>>1 = 1.
- `frl_configure` skips `set_frl_rate` when the rate is unchanged. The link trained at 10G, so there was
  no fallback.

This is not proven on the board yet. Dynamic debug (below) will show it.

On the live board (read-only), everything matches what the vendor kernel would program for 4K60 10-bit FRL:
- VP0: bus_format RGB101010_1X30, out_mode AAAA, 594 MHz.
- dclk_vop0 594 MHz from gpll (CRU).
- aclk_vop 750 MHz (FRL boost active).
- Cluster0 XR30 AFBC.

### Static comparison with the vendor stack (work/_downloads/hdmi-frl/bsp) for 4K60 RGB 10 bpc FRL
I found no other difference:
- **GRF:** VO1_CON3 COLOR_DEPTH = 10BPC (0x6) and VO1_CON4 HDMI21 = 1. Same values as the vendor
  `set_grf_cfg` and FRL GRF code. Our enc_init runs before the bridge enable and FLT, which is the
  vendor order too.
- **VOP2:** DCLK goes to the CRU. Vendor `vop2_is_dclk_switch_to_cru_pll()` uses the same 742.5 > 600
  logic. Dividers: if_pixclk = dclk/2, if_dclk = dclk/4, core = dclk/4. The vendor values are the same
  (`hdmi_edp_pixclk = 2*core/K`). out_mode AAAA. Vendor dither for RGB101010 is off.
- **Controller:** neither driver programs VIDEO_PACKING_CONFIG0 or any colour-depth or packing register.
  Both rely on the IPI depth from GRF. The FRL bring-up writes the same registers: LINK_CONFIG0
  FRL/4LANES, FLT_CONFIG1, and after FLT clear AVMUTE + GCP_TX_EN + video SWDISABLE=0.
- **ACR:** FRL N/CTS from the rate table. It does not affect video.
- **Link selection:** the vendor also uses the maximum rate, capped at 10G x 4.
- **AVI** (read from debugfs): RGB, VIC 97, limited range. **HDMI VSIF:** normal.

So 1203 is still a correct fix: it is consistent with what the PHY driver expects and with the vendor
glue. But it is not the fix for the black screen. The cause is not visible from a static read. It needs
the experiments below to narrow down.

### Experiments needed (coordinator to run; they need a modeset, so GDM must be stopped)
Prep:
  sudo systemctl stop gdm
  echo 'file phy-rockchip-samsung-hdptx.c +p; file dw-hdmi-qp.c +p; file dw_hdmi_qp-rockchip.c +p; file drm_hdmi_state_helper.c +p; file drm_hdmi_helper.c +p' | sudo tee /sys/kernel/debug/dynamic_debug/control
  echo 0x106 | sudo tee /sys/module/drm/parameters/debug    # DRIVER|KMS|ATOMIC
  modetest -M rockchip -c | sed -n '/^88/,/^[0-9][0-9]*\t/p' | grep -A8 -E 'max bpc|color format'   # enum ids
For each case: run it, look at the TV, then save
  `sudo dmesg -c > caseN.log; sudo grep -A12 'HDMI-A-1' /sys/kernel/debug/dri/0/state > caseN.state; sudo cat /sys/kernel/debug/dri/0/HDMI-A-1/scdc_status > caseN.scdc`
  (connector 88, crtc 83 = video_port0; -F drops the plane test pattern into a linear XR24 or XR30 fb)
  1. 4K60 8 bpc, TMDS 594 (baseline):     modetest -M rockchip -a -s 88@83:3840x2160-60 -w 88:'max bpc':8
  2. 1080p60 10 bpc, TMDS 185.6:          modetest -M rockchip -a -s 88@83:1920x1080-60 -w 88:'max bpc':10
  3. 4K30 10 bpc, TMDS 371.25 (scrambled): modetest -M rockchip -a -s 88@83:3840x2160-30 -w 88:'max bpc':10
  4. 4K60 10 bpc FRL, linear XR24:        modetest -M rockchip -a -s 88@83:3840x2160-60 -w 88:'max bpc':10
  5. 4K60 10 bpc FRL, linear XR30:        modetest -M rockchip -a -s 88@83:3840x2160-60@XR30 -w 88:'max bpc':10
  6. 4K60 10 bpc YUV420, TMDS 371.25:     ... -w 88:'max bpc':10 -w 88:'color format':<YCbCr420 id>
  7. 4K120 8 bpc FRL (re-confirm):        modetest -M rockchip -a -s 88@83:3840x2160-120 -w 88:'max bpc':8
  Afterwards: echo 0 | sudo tee /sys/module/drm/parameters/debug; sudo systemctl start gdm
How to read the results:
- Cases 2 and 3 black → the bug is 10-bit HDMI output in general (GRF depth, VOP 30-bit out, GCP CD), not FRL.
- Cases 2 and 3 fine but 4 and 5 black → FRL plus deep colour.
- 4 fine but 5 black → plane, AFBC or 10-bit fb path.
- The dmesg must show `rk_hdptx_phy_configure: FRL rate=4000000000 bpc=10` and
  `rk_hdptx_phy_power_on: rate=4000000000 bpc=10`. That is the check that 1203 reaches the hardware.

---------------------------------------------------------------------------------------------------
## Update 2: 1080p60 10 bpc over TMDS shows a picture, so the problem is FRL + 10 bpc only
Second static pass, comparing FRL 8 bpc (4K120, works) with FRL 10 bpc (4K60, black), against the vendor tree:
- **PHY:** `rk_hdptx_frl_lcpll_cmn_config` and `rk_hdptx_frl_lcpll_mode_config` are identical to the
  vendor PHY (only the macro spelling differs). In FRL the only bpc-dependent bit is PCG_CLK_SEL. With
  1203 we now program it the way the vendor does. The board is black both before and after 1203. So,
  if dynamic debug confirms bpc=10 reached the PHY, the PCG select is not the cause.
- **VOP2:** for 4K60 10 bpc the vendor also moves DCLK to the CRU at the pixel rate, 594 MHz
  (`vop2_is_dclk_switch_to_cru_pll`, plus clk_set_rate(dclk, v_pixclk) for v_pixclk <= 600 MHz). The
  interface dividers are the same. The vendor has nothing FRL- or bpc-specific in VOP2.
- **Controller (vendor dw-hdmi-qp.c):** it has no FRL bpc, packing-phase or GCP CD programming. The FLT
  LTS1-LTSP sequence matches the generic helper plus our bridge ops: video SWDISABLE and AVP reset at
  LTS1, then AVMUTE clear + GCP_TX_EN + video enable at FRL_START. The vendor `dclk_set` and
  `link_clk_set` only gate clocks. `link_clk` is set to the FRL rate in FRL mode, which is what our PHY
  clock already reports (4 GHz).
- **Glue/GRF:** the same as the vendor.

Conclusion: I found no remaining code difference from the vendor stack for this mode, so I don't have
a candidate fix that I can stand behind. The next step has to be the measurements below.

### Next board session (connector 88, crtc 83 only; GDM stopped; dynamic debug as in the previous plan)
  A. 4K60 10 bpc FRL, linear XR24:  modetest -M rockchip -a -s 88@83:3840x2160-60 -w 88:'max bpc':10
     → check dmesg for `rk_hdptx_phy_configure: ... FRL rate=4000000000 bpc=10` and
       `rk_hdptx_phy_power_on: rate=4000000000 bpc=10` (this confirms 1203 reached the PHY), plus the FLT
       trace (`FRL LTS:P training succeeded`).
  B. 4K60 10 bpc FRL, XR30 linear:  ... -s 88@83:3840x2160-60@XR30 -w 88:'max bpc':10
  C. 4K30 10 bpc TMDS 371 MHz (scrambled): ... -s 88@83:3840x2160-30 -w 88:'max bpc':10
  D. 4K120 8 bpc FRL (re-check):     ... -s 88@83:3840x2160-120 -w 88:'max bpc':8
  E. 4K120 YUV420 10 bpc → 742.5 MHz FRL with DCLK 594 (YUV420 halves it):
     ... -s 88@83:3840x2160-120 -w 88:'max bpc':10 -w 88:'color format':<YCbCr420 id>
  F. 4K60 YUV444 10 bpc FRL:         ... -s 88@83:3840x2160-60 -w 88:'max bpc':10 -w 88:'color format':<YCbCr444 id>
  How to read the results:
  - E or F show a picture but A does not → the problem is RGB-specific.
  - E and F black too → FRL deep colour in general.
  - C black → scrambled TMDS deep colour is broken too, so the problem is not FRL.
  - If anything that works in mainline does not work on the vendor kernel, or the reverse, that is the
    next lever. Running the vendor (BSP) kernel image for case A would show whether this TV accepts
    4K60 RGB 10 bpc over FRL from RK3588 at all.
