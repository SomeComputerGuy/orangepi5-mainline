# VOP2 POST_BUF_EMPTY on vp0: the three HDMI-RUN1 matrix cases (v2, 2026-11-01)

Status: **3 patches written and build-tested (W=1, checkpatch --strict clean). Board test script and drop-in
module are ready but have not been run, because the board is busy.** Branch `opi5/vop2-uf2`
(worktree `~/orangepi5/build/wt-vop2-uf2`) = `opi5/stack-337` + 3 commits.
The first round (AXI port balancing and the IRQ storm, already in the stack as 1301/1302) is described in `../RESULTS.md`.

## Verdicts per case

### (i) 4K120, linear XR24 on Esmart0 (plane 59): 30x POST_BUF_EMPTY. **Hardware limit. Fix: reject in atomic_check.**
- Matrix case: `modetest -a -s HDMI -P 59@83:3840x2160@XR24`. In atomic mode modetest leaves the primary plane alone, so the
  fbcon framebuffer stays on **Cluster0** (linear, full screen), now at 4K120. DP-1 stays lit by fbcon on **Cluster1**.
  The layers are therefore C0 + E0 (two full-screen RGB layers at 4K120) + DP C1 (4K30). That is exactly the over-budget row
  of the first round (279 bad frames in 720).
- Per-line fetch rate (source line bytes x line rate): 4K120 XR24 = 3840*4*1188e6/4400 = 4.15 GB/s per layer. DP 4K30 = 1.04 GB/s,
  and it always adds up, because VP2 isn't line-synchronised with VP0. Every way of splitting {4.15, 4.15, 1.04} over the two
  ports gives at least 5.19 GB/s on one port. The measured per-port limit is between 4.41 (clean) and 4.93 GB/s (fails),
  from the round-1 geometry tests converted to this model. Raising ACLK to 850 MHz or changing QoS doesn't help (round 1).
- No register setting fixes this. 1301 already balances the ports, and no split fits.
- **Patch 0003**: estimate each port's fetch in the CRTC atomic_check. It predicts the 1301 port choice (fetching windows keep
  their port, new ones get one by the same rule, now factored into `vop2_axi_pick_bus()`). Same-VP windows add up only where
  their display lines overlap (round 1 showed 3840x64 overlap rows fail, so the limit is per line, not per frame); windows on
  different VPs always add up. It refuses the state (drm_dbg_kms "AXI port N would fetch X MB/s, more than 4600 MB/s",
  -EINVAL) if a port goes over 4.6 GB/s **and** the commit makes that port busier than it is now. So an unrelated commit is
  never blocked by layers it doesn't touch. AFBC is estimated uncompressed (worst case: content changes without a new check).
  Compositors then fall back to GPU composition (TEST_ONLY fails).
- Still fits: C0 4K120 + E0 NV12 overlay + DP (3.98 | 2.49 average), and E0 alone at 4K120 + DP.

### (ii) RG16 AFBC 0x0800000000000051 on Cluster 35/47/53 at 4K60: black + 20x POST_BUF_EMPTY. **The decoder can't do this format/modifier combination. Fix: don't advertise or accept it.**
- 0x51 = AFBC 16x16 | SPARSE | YTR. Only these modifiers can reach the matrix for RG16: those panfrost can render (Mesa
  26.2 `PAN_SUPPORTED_MODIFIERS`) that the clusters also list, which is **0x41 and 0x51**. Only 0x51 failed: 3 FAILs, one per
  plane. So RG16 + SPARSE without YTR displays, RG16 + YTR doesn't, and XR24 + YTR (0x51) displays.
  BG16 was never exercised: Mesa's dri image table has no BGR565, so GBM/EGL can't make one.
- The register programming matches the BSP exactly (AFBC format 0 | YTR bit 4, same stride, tile, half-block and
  auto-gating; the BSP also lists RGB565 with every AFBC modifier). This is a decoder limitation, not wrong programming.
  Supporting evidence: Documentation/gpu/afbc.rst requires R, G, B component order when YTR is used, and DRM_FORMAT_RGB565 has B
  in component 0. Arm's own komeda/D71 supports AFBC only for BGR565.
- **Patch 0002**: `rockchip_vop2_mod_supported()` returns false for RGB565/BGR565 with AFBC_FORMAT_MOD_YTR on RK3588
  (drm_dbg_kms "No AFBC YTR support for 16 bpp RGB"). That removes them from IN_FORMATS, so ADDFB2 and atomic reject them and
  clients pick 0x41.
- Assumption to confirm on the board: RG16 0x41 PASSed in run 1 (raw data lost with the reflashed SD). Test ii-rg16-noytr-*
  checks this.

### (iii) 4K120 YCbCr 4:2:0 8 bpc: POST_BUF_EMPTY, scrambled. **Mainline programs the clock wrong. Fix: ACLK.**
- The VOP2 dividers for HDMI 4:2:0 match the BSP after 1211/1214/1215. Mainline: DCLK = 594 MHz, dclk_core = 297
  (div 2), if_pixclk = 297, if_dclk = 148.5. BSP rk3588_calc_cru_cfg (K=2): the same rates. No half-pixel or other VP mode is
  missing for RK3588 (the BSP's extra 4:2:0 handling is for RK3568/RK3576/RK3572 only). So dividers and pixels-per-clock are not
  the problem.
- 4K120 4:2:0 8 bpc has a TMDS character rate of 594 MHz (at most 600), so `hdmi_clock_valid()` in drm_hdmi_state_helper chooses
  **TMDS, not FRL**. That means `frl_enabled = false`, so **ACLK stays at 500 MHz** (0300-096 raises it only for FRL), while the
  VP processes 1188 Mpixel/s. 0300-096 itself documents that 500 MHz underflows 4K120. The matrix label "4K120 FRL" was the mode
  group; the link was not recorded.
- **Patch 0001**: raise ACLK whenever the VP's pixel clock is above 600 MHz, or the link is FRL. It also tracks the boost per VP
  (`vp->aclk_boost`), so atomic_enable's error path no longer leaks the reference.
- **Open point, possibly a second root cause in the HDMI layer.** The BSP never sends pixel clocks above 600 MHz over TMDS. It
  uses FRL whenever `mode.clock >= 600000` (dw_hdmi_qp-rockchip.c `hdmi_select_link_config`), and without FRL it rejects those
  modes (MODE_BAD in mode_valid). If iii-4k120-420-* is still SCRAMBLED with ACLK at 750 MHz and no POST_BUF_EMPTY, the
  dw-hdmi-qp TMDS path can't take a 1188 MHz pixel clock. The fix then belongs in the HDMI layer: refuse TMDS when
  mode->clock > 600 MHz, i.e. a `hdmi_tmds_char_rate_valid` in dw-hdmi-qp, or let the FRL helper prefer FRL. That is not
  done here, so the board test decides first.

## Patches (`patches/`, author Arun Iyengar, one `Assisted-by: Claude:claude-opus-5-5`, no SoB)
1. `0001-drm-rockchip-vop2-Raise-ACLK-for-every-video-port-ab.patch`: ACLK by pixel rate (iii)
2. `0002-drm-rockchip-vop2-Don-t-accept-AFBC-YTR-for-RGB565-o.patch`: RGB565/BGR565 AFBC without YTR only (ii)
3. `0003-drm-rockchip-vop2-Reject-states-that-overload-an-AXI.patch`: AXI port fetch admission check (i); builds on 1301
Build: `v2/mk.sh` (O=~/orangepi5/build/wt-vop2-uf2-out, KCC as build-kernel.sh). `make W=1 drivers/gpu/drm/rockchip/` builds with no warnings.
Drop-in: `deploy/rockchipdrm.ko`, built with M= against build/linux's Module.symvers and signed with build/linux's key.
vermagic 7.3.0-opi5, srcversion 83755B1F2AFC15684BB1C92. src/linux's DRM/PHY sources are identical to stack-337.

## Board test plan (unattended, about 6 min)
1. Baseline (optional, current kernel): `sudo ~/vop2uf/test/vop2uf-test.sh /var/tmp/vop2uf/base`
2. Deploy: `sudo ~/vop2uf/deploy/deploy.sh install`, then `sudo reboot`. Check `cat /sys/module/rockchipdrm/srcversion` = 83755B1F2AFC15684BB1C92.
   The script checks vermagic, signing key and symbol CRCs (against /usr/src/linux-headers-$(uname -r)/Module.symvers) before
   installing. It moves an old updates/opi5-vop2 drop-in to /var/tmp. Undo with `deploy.sh undo` + reboot.
3. Test: `sudo ~/vop2uf/test/vop2uf-test.sh /var/tmp/vop2uf/fix`. The result is in **/var/tmp/vop2uf/fix/summary.txt**.
   Each case has its own directory with state.txt, vop2-summary.txt, kmsg.txt, cam.jpg and result.json.
   Copy to the host: `scp -r <user>@<board-ip>:/var/tmp/vop2uf ~/orangepi5/work/_out/vop2-underflow/v2/board/`
Setup: TV on HDMI-A-1 with a 3840x2160@120 (1188 MHz) mode, DP-1 connected (needed for i-*+dp), webcam on the TV (optional).
Copy the whole `v2/` directory to `~/vop2uf` on the board first.

Expected on the fixed kernel (each case is PASS/FAIL against these; the baseline FAILs show the bugs):
| case | expect | meaning |
|---|---|---|
| ctl-4k60-rgb, ctl-4k120-rgb | clean | controls; ctl-4k120 shows aclk 750000000 |
| i-c0+e0 | clean | two 4K120 layers, HDMI only, ports split |
| i-c0+e0+dp-test, i-c0+e0+dp | reject | matrix case (C0 linear forced like fbcon, E0, DP C1 4K30) |
| i-c0afbc+e0+dp | info | refused by the worst-case estimate; baseline shows whether the HW copes with compressed C0 |
| i-e0+dp | clean | E0 alone at 4K120 + DP fits |
| ii-rg16-ytr-p35/47/53 | reject | kmsctl reports "does not list RG16 0x...51" (removed from IN_FORMATS) |
| ii-rg16-noytr-p35/47/53, ii-rg16-auto-p35, ii-xr24-ytr-p35 | clean | 0x41 works; auto picks 0x41 |
| iii-4k60-420 | clean | 4:2:0 control (TMDS 297 MHz) |
| iii-4k120-420-lin / -afbc | clean | aclk 750000000; link column shows TMDS 594 MHz. If SCRAMBLED with pbe=0, see the open point in (iii) |
POST_BUF_EMPTY count = kmsg lines plus "callbacks suppressed" (1302 rate-limits); vop_irqs is the raw IRQ delta.
