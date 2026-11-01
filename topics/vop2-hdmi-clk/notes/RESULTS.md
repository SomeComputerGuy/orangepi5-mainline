# HDMI0 DCLK / FRL-state / sync-polarity fixes (Orange Pi 5, kernel 7.3.0-7 + 1207-1209)

Status: DONE - 5 patches in patches/, deployed as drop-ins (updates/opi5-hdmi-clk), verified.

Bugs (from hdmi-wedge/RESULTS.md): (a) VOP2 DCLK for FRL modes silently rounded by the CRU,
(b) rk3588_calc_cru_cfg() uninitialised *dclk_out_div for HDMI/eDP, (c) dw-hdmi-qp leaves FRL state
(OPMODE_FRL_4LANES, FLT_CONFIG1) in TMDS mode, (d) RK3588 HDMI sync polarity / dclk polarity vs BSP.

## Log
1. 20:24 board watchdog reboot caused by me: ran hdmiregs.py (dw-hdmi-qp /dev/mem reads) while gdm had
   HDMI0 blanked (dclk_vop0 enable_count 0). Confirms the safety note: the controller registers must
   only be read while HDMI0 is enabled. From now on only through tools/hdmiregs-safe.sh, which checks
   that dclk_vop0 is enabled and the HDMI-A-1 CRTC is active first.
2. Measurement method. tools/vblank.py measures the real pixel clock from DRM vblank timestamps
   (refresh x htotal x vtotal; the vblank IRQ comes from the VOP timing generator, which runs on DCLK);
   repeatability 10-25 ppm (crystal/timer). clk_summary gives what the CRU/PHY is programmed to.
   Note: dw-hdmi-qp CMU_IPI_CLK_FREQ is NOT a DCLK measurement in FRL mode: gdm's 3840x2160@60 10 bpc
   FRL reads 120015 kHz while DCLK is measured at 594.010 MHz (TMDS modes read exactly pixel/4). The
   "gdm 534.7 MHz" in hdmi-wedge item 17 came from that counter; gdm actually runs the 594.000 MHz
   mode at 594.01 MHz (vblank). tools/snap.py / clkrun.py / matrix.sh = capture per step
   (clk_summary subset, vblank pixel clock, VOP DSP_IF_*/VP0_CLK_CTRL from debugfs active_regs,
   dw-hdmi-qp safe status registers only when HDMI0 is enabled).
3. Baseline (7.3.0-7 + hdmi-wedge 1207-1209 drop-ins), cap/base.summary, camera GOOD in all 15 steps:
   | mode | DCLK (clk_summary, parent) | measured | error |
   |---|---|---|---|
   | 3840x2160@60 594.000 8 bpc TMDS | 594 MHz (PHY PLL) | 594.006 | +10 ppm |
   | 3840x2160@59.94 593.407 8 bpc TMDS | 593.4069 (PHY PLL) | 593.418 | +19 ppm |
   | 3840x2160@60 10 bpc FRL | 594 (GPLL/2) | 594.014 | ok |
   | 3840x2160@59.94 10 bpc FRL | **500 (CPLL/3)** | 500.007 | **-15.7 %** (50.5 Hz) |
   | 4096x2160@60 10 bpc FRL | 594 (GPLL/2) | 594.010 | ok |
   | 4096x2160@59.94 10 bpc FRL | **500 (CPLL/3)** | 500.006 | **-15.7 %** |
   | 3840x2160@120 8 bpc / 10 bpc FRL | 1188 (GPLL/1) | 1188.020 / 1188.027 | ok |
   | 3840x2160@119.88 8 / 10 bpc FRL | **786.432 (AUPLL/1!)** | 786.445 / 786.452 | **-33.7 %** (79.5 Hz) |
   | 4096x2160@59.94 YUV420 TMDS | 296.703 (PHY PLL) | 593.420 pixel | ok |
   | 720x480@60 (-h -v), 2560x1440@120 497.75, 1080p | PHY PLL | exact | ok |
   The TV shows a picture even at -34 %, so the bug is silent. Also seen: LINK_CONFIG0 = 0x100 (FRL_4LANES)
   and FLT_CONFIG1 = 0x0f in every TMDS step after FRL (bug c); VP0_CLK_CTRL = 0x0e (dclk_out_div field 3,
   garbage, bug b); DSP_IF_POL HDMI bits never written (0x10000000).
   GRF VO1_CON0 (0xfd5a8000) reads back 0 through /dev/mem in every mode (also CON3/CON4), so the GRF
   polarity bits cannot be observed that way; not read again (possibly a gated pclk, risk of a hang).
4. BSP comparison (hdmi-frl/bsp + rockchip-linux develop-6.1 clk-rk3588.c/clk-pll.c in
   _downloads/hdmi-clk-bsp):
   - VP0/VP1 DCLK parent in FRL: the BSP uses the CRU too (vop2_is_dclk_switch_to_cru_pll(): "hdmi must
     use frl mode, and the parent clock of dclk cannot use hdmi phy pll, but must use the cru pll").
     dclk_vop0_src parents are GPLL/CPLL/V0PLL/AUPLL with an integer divider, no CLK_SET_RATE_PARENT
     (BSP: CLK_SET_RATE_NO_REPARENT); V0PLL is reserved for VP2 (rk3588s.dtsi assigned-clock-parents),
     and the "hdmi0/1_phy_pll" extend clocks are only used when the PHY runs TMDS (or for DP via the
     other, idle HDMI PHY; RK3588S has only one HDPTX PHY). So the BSP cannot make 593.407 MHz in FRL
     either. Its vop2_crtc_mode_valid() rejects HDMI/DP modes above 600 MHz whose CRU round_rate does
     not equal the request ("Hdmi or DisplayPort request a Accurate clock", MODE_CLOCK_RANGE); for
     <= 600 MHz HDMI it assumes the PHY PLL makes any rate (so the BSP has the same 59.94 Hz 10 bpc bug).
   - An exact FRL DCLK would need a dedicated, fractional, rate-settable PLL for VP0 (V0PLL with
     CLK_SET_RATE_PARENT and computed PLL parameters; mainline's rk3588 PLL is table-only and V0PLL is
     the VP2/eDP/DSI PLL in upstream DTs) - not an upstreamable VOP fix. -> fix = refuse, like the BSP.
   - Sync polarity: BSP vop2_get_hdmi_pol(vop2, adjusted_mode->flags): RK3588 sets the GRF_VO1_CON0
     bit for NHSYNC/NVSYNC (bit = negative). Mainline feeds POLFLAG bits into the same decoder.
   - DSP_IF_POL hdmi_dclk_pol: BSP's rk3588_vop_ctrl does NOT define hdmi_pin_pol/hdmi_dclk_pol ("HDMI
     pol control by GRF_VO1_CON0"), and vop2_mask_write() returns for mask 0, so VOP_CTRL_SET(..,
     hdmi_dclk_pol, 1) is a no-op on RK3588 (only RK3568/RK3562 have that field). Mainline RK3588 already
     matches the BSP here -> nothing to change (hdmi-wedge item 12 was based on the RK3568 table).
   - FRL state: BSP hdmi_set_op_mode() clears OPMODE_FRL and OPMODE_FRL_4LANES for TMDS; it writes
     FLT_CONFIG1 = 0 when training passes.
5. Patches (git/, on top of the 7.3.0-7 stack incl. 1207-1209):
   - b: drm/rockchip: vop2: Don't use uninitialised dividers on RK3588
   - d: drm/rockchip: vop2: Fix the HDMI sync polarity on RK3588
   - c: drm/bridge: dw-hdmi-qp: Clear the FRL link state when leaving FRL
   - a1: drm/rockchip: vop2: Don't take DCLK from the HDMI PHY PLL in FRL mode (use crtc_state
     frl_enabled instead of the bpc/rate guess; helper shared with atomic_check)
   - a2: drm/rockchip: vop2: Reject HDMI modes the CRU cannot clock exactly (atomic_check, new
     vop2_ops.dclk_rate for RK3588)
   Deployed 20:43 as updates/opi5-hdmi-clk/{drm_display_helper,dw-hdmi-qp,rockchipdrm}.ko (built in
   build/, all three incl. 1207-1209), opi5-hdmi-wedge moved to /var/tmp/hc/updates-opi5-hdmi-wedge.bak.
6. Run 1 with the fixes (cap/board/fix.summary) is INVALID for the camera: the TV was in CEC standby
   (BLACK frames); clocks/registers from it agree with run 2. Re-run with CEC wake + control frame.
7. **Verification (cap/board/fix2.summary, control frame c0 GOOD before the matrix):**
   | step | commit | camera | DCLK (clk_summary) | measured | notes |
   |---|---|---|---|---|---|
   | 1080p RGB | ok | GOOD | 148.5 PHY | 148.503 | LINK_CONFIG0 0, FLT_CONFIG1 0 (c) |
   | 3840@60 8 bpc TMDS | ok | GOOD | 594 PHY | 594.010 | |
   | 3840@59.94 8 bpc TMDS | ok | GOOD | 593.407 PHY | 593.419 | (59.94 Hz still available at 8 bpc, exact) |
   | 3840@60 10 bpc FRL | ok | GOOD | 594 GPLL/2 | 594.022 | |
   | 3840@59.94 10 bpc FRL | **-EINVAL** | previous mode kept | - | - | was 500 MHz |
   | 4096@60 10 bpc FRL | ok | GOOD | 594 | 594.011 | |
   | 4096@59.94 10 bpc FRL | **-EINVAL** | previous mode kept | - | - | was 500 MHz |
   | 3840@120 8 / 10 bpc FRL | ok | GOOD / GOOD | 1188 GPLL | 1188.022 / 1188.030 | |
   | 3840@119.88 8 / 10 bpc FRL | **-EINVAL** | previous mode kept | - | - | was 786 MHz (AUPLL) |
   | 4096@59.94 YUV420 TMDS | ok | GOOD | 296.703 PHY | 593.418 pixel | VP0_CLK_CTRL 0x05 |
   | 720x480 (-h-v) | ok | GOOD | 27 PHY | 27.0005 | |
   | 2560x1440@120 | ok | GOOD | 497.75 PHY | 497.756 | |
   ("WRONGCASE" = the TV still shows the previous step's pattern because the commit was refused.)
   dmesg (drm.debug): "vp0: DCLK 1186813000 Hz not available from the CRU (closest 786431991 Hz)".
   VP0_CLK_CTRL = 0x0a in RGB modes (dclk_out_div = dclk_core_div, was 0x0e with garbage 3) (b).
   TMDS after FRL: LINK_CONFIG0 = 0x0, FLT_CONFIG1 = 0x0 (were 0x100 / 0x0f) (c).
8. Sync polarity (d), seen in dw-hdmi-qp VIDEO_INTERFACE_STATUS0 bits 17/18 (what the controller's
   input sees; they follow the GRF bits): before: 1080p (+h+v) 0x40000 (bit 17 clear = hsync seen
   negative), 720x480 (-h-v) 0x60000 (both seen positive); after: 1080p 0x60000, 720x480 0x00000, i.e.
   the polarities now match the modes (BSP semantics: GRF bit = negative sync). Camera GOOD for both.
   Note: bit 18 is therefore "vsync positive", not a general input lock (hdmi-wedge used it as a lock
   indicator; valid there because all its modes are +v). The minimal-repro.sh "VIF=0x0004" grep must
   not be used for -v modes.
9. **Regression: wedge trigger** (cap/board/wedge594): minimal-repro uses 4096@59.94 10 bpc FRL, which
   is now refused (cap/board/wedge5: commit rc=1, 5/5 refused - not a wedge test). Re-run with the
   594.000 MHz 4096x2160@60 10 bpc FRL: [4096 YUV420 TMDS -> 4096 10 bpc FRL] x5 = 10/10 GOOD, then
   1080p, 3840@60 8 bpc TMDS x2 GOOD, every FRL step VIF 0x60560, DCLK 594.
   DP-1 (VP2, 3840x2160@30 297 MHz GPLL) unaffected: 297.005 MHz with and without gdm.
   gdm after reboot and after the runs: HDMI-A-1 3840x2160@60 10 bpc FRL at 594.011 MHz, picture lit
   (cap/board/gdm-cam3.jpg, same as hdmi-wedge cap/gdm-after.jpg).

## Board state
updates/opi5-hdmi-clk/{drm_display_helper,dw-hdmi-qp,rockchipdrm}.ko = 7.3.0-7 + 1207-1209 + patches
0001-0005 (in initramfs). Undo: remove that dir, restore /var/tmp/hc/updates-opi5-hdmi-wedge.bak to
updates/opi5-hdmi-wedge, depmod -a 7.3.0-opi5, update-initramfs -u -k 7.3.0-opi5, reboot.

## Files
patches/0001-0005 (format-patch, Arun Iyengar, Assisted-by only; apply after 1209), git/ (scratch repo),
build/ (sources + build.sh, out/*.ko), tools/ (vblank.py, snap.py, clkrun.py, matrix.sh,
hdmiregs-safe.sh), cap/ (base = before, board/fix2 + wedge594 = after).
