# HDMI0 "No Signal" after 4096x2160@60 10 bpc FRL (Orange Pi 5, kernel 7.3.0-7)

Status: ROOT-CAUSED AND FIXED (drop-in modules deployed and verified on the board, 2026-10-31 20:xx).

## Summary
- **Trigger:** leaving YCbCr 4:2:0 output with an active->active modeset (one atomic commit that disables
  and re-enables the VOP video port), e.g. 4096x2160@60 YUV420 (case 108) -> 4096x2160@60 10 bpc RGB FRL
  (case 109). About half of such modesets fail; RGB/4:4:4/4:2:2 predecessors never do (0/12). FRL itself
  is innocent: 420 -> 1080p RGB TMDS fails the same way. Minimal repro: repro/minimal-repro.sh.
- **Symptom in the hardware:** the dw-hdmi-qp input pixel interface (IPI) does not lock onto the new stream:
  VIDEO_INTERFACE_STATUS0 bit 18 clear, VIDEO_MONITOR_STATUS* garbage (htotal 2 / hactive 2). The TMDS/FRL
  link is fine (SCDC locked, CED 0), the VOP runs the mode normally, nothing is logged. The state can survive
  any number of further back-to-back modesets (the "wedge", incl. 1080p and gdm) until the output is turned
  off in a separate commit (DPMS off/on, all-off) or the board reboots.
- **Root cause:** the controller's clock management unit reinitializes the IPI only after it has detected
  that the IPI clock stopped (CMU_STATUS.IPI_CLK_OFF), which takes ~2 ms (measured 1.8-2.3 ms). No software
  reset covers the IPI (AVP_DATAPATH_SWINIT_P, VIDEO_SWDISABLE, GRF toggles, VOP DCLK/IF resets: all tested,
  none helps). In an active->active modeset VOP2 gates DCLK in .atomic_disable and ungates it in
  .atomic_enable almost immediately, so the IPI keeps the 4:2:0 state of the previous mode.
  Proof: 200 ms pause between CRTC disable and enable -> 10/10 GOOD; separate disable/enable commits ->
  16/16 GOOD; waiting for IPI_CLK_OFF in the encoder's .atomic_mode_set -> 10/10 + 5/5 GOOD.
- **Fix (patches/):**
  - 0002 drm/bridge: dw-hdmi-qp: Add helper to wait for the video input clock to stop
    (dw_hdmi_qp_wait_input_clk_off(): poll CMU_STATUS.IPI_CLK_OFF, 20 ms timeout)
  - 0003 drm/rockchip: dw_hdmi_qp: Let the controller see DCLK stop on a modeset
    (encoder .atomic_mode_set, which runs between the CRTC disable and the CRTC enable, calls it)
  - 0001 drm/display: hdmi: Don't reset an active FRL link on every connector probe (separate bug found on
    the way: drm_connector_hdmi_sync_scdc() checked the TMDS scrambling bit while in FRL, so every probe
    retrained FRL with a full modeset; now checks SCDC Config_1 FRL_Rate in FRL mode)
- **Deployed:** /lib/modules/7.3.0-opi5/updates/opi5-hdmi-wedge/{drm_display_helper,dw-hdmi-qp,rockchipdrm}.ko
  (built from build/final, copies in modules/), depmod + update-initramfs. Undo: remove that directory,
  depmod -a 7.3.0-opi5, update-initramfs -u -k 7.3.0-opi5, reboot.
- **Verification:** see items 34-35 below.
- **Other bugs found, NOT fixed here (follow-ups):** (a) VOP2 DCLK for FRL modes comes from the CRU and is
  silently rounded down: 593.407 MHz (4096/3840x2160@59.94 10 bpc) -> 500 MHz, gdm's 3840 FRL mode measured
  534.7 MHz; mode should get the nearest rate within HDMI tolerance (594 MHz) or be rejected.
  (b) rk3588_calc_cru_cfg() leaves *dclk_out_div uninitialised for HDMI/eDP and ilog2()s it.
  (c) dw-hdmi-qp fallback_tmds leaves OPMODE_FRL_4LANES set and FLT_CONFIG1=0x0f in TMDS mode (BSP clears).
  (d) rk3588_get_hdmi_pol() is fed POLFLAG bits but decodes DRM mode flags (BSP passes mode flags);
  DSP_IF_POL hdmi_dclk_pol (BSP sets 1) never set. No visible effect found, worth a look.
  (e) harness: fbdev's restore probe prunes modes wider than its fb from the cached mode list; kmsctl now
  honours KMSCTL_PROBE=1 (testmatrix/lib/kmsctl.py).
- **Safety notes:** a /dev/mem read sweep over dw-hdmi-qp 0x44-0xafc hung the board once; only the fixed
  register list in repro/hdmiregs.py is known safe (read only while HDMI0 is enabled).

## Log (chronological, as written during the investigation)

## Repro tooling
- `repro/wedge.py` - replays KMS heads on HDMI-A-1 via testmatrix `kmsctl.py`; after each step: webcam verdict
  (testmatrix `camcheck.py`, calibrated at 1080p), SCDC (`scdc_status`), atomic state, vop2 summary, clk subset.
  `POSTCAP=1` also captures what the fbdev restore shows after the client exits. It re-probes the connector
  before every step (see harness note below).
- `repro/seq.sh` - timing / property shortcuts; `repro/run.sh` - one batch with drm.debug=0x6 + dyndbg log.
- Captures: `cap/r1` (first replay), `cap/r2`, `cap/r3` ... each step dir has cam.jpg, scdc.txt, state.txt,
  vop2.txt, clk.txt, step.json.

## Harness note (not a kernel bug)
`kmsctl.py show` uses the cached connector mode list. The fbdev client's restore probe
(`drm_client_modeset_probe()` with the fbdev fb size, 3840x2160) prunes every mode wider than 3840 from
that cache, so 4096x2160 "disappears" until the next full probe. wedge.py probes before every step.

## Findings so far
1. Replay of run-2 cases 105-111 (r1, seq2): 105-108 (4096x2160@60/593407 TMDS, RGB/444/422/420) GOOD;
   109 (4096x2160@60/593407 10 bpc AUTO -> RGB, FRL 10Gx4, Cluster0 XR30 AFBC) "No Signal" on the TV
   although FRL link training passed (SCDC 0x40=0x5e: ch0-3 locked, FLT ready); 110 (1080p TMDS) and
   111 (4096 TMDS) also "No Signal" (SCDC TMDS clock+ch0-2 locked) -> reproduced the wedge on the first try.
   A following 3840x2160@60/594000 10 bpc FRL step was GOOD and cleared it (1080p GOOD afterwards).
2. In every 4096x2160@60/593407 10 bpc FRL step, clk_summary shows **dclk_vop0 = 500 MHz** (dclk_vop0_src
   from CPLL 1500/3) instead of 593.407 MHz: in FRL the VOP DCLK must come from the CRU (the HDMI PHY PLL
   is the FRL link PLL), and dclk_vop0_src can only divide GPLL 1188 / CPLL 1500 / V0PLL (unused, 24 MHz) /
   AUPLL. 3840x2160@60/594000 gets exactly 594 MHz (GPLL/2) and is reliable. The VOP silently runs 16 %
   slow; the mode is not rejected and nothing is logged.
3. The failure is intermittent: 1080p -> 4096 FRL was GOOD (r2 a1); 4096 YUV420 TMDS -> 4096 FRL was
   No Signal in 2 of 3 tries (r2 b1, c4; c1 GOOD). Atomic state, vop2 summary, clocks and SCDC are identical
   between the GOOD and the No Signal 4096 FRL steps.
4. Every connector probe while FRL is active logs "Resetting CRTC to restore SCDC status" and retrains FRL
   (drm_connector_hdmi_sync_scdc), i.e. each probe (GNOME does them on hotplug/resume) is a full modeset.
5. (diagnostic accident) Writing GLOBAL_SWRESET_REQUEST=AVP_DATAPATH_SWINIT_P (0x40=0x40) by /dev/mem while
   the 1080p TMDS head was live rebooted the board (16:47). Before that, clearing LINK_CONFIG0.OPMODE_FRL_4LANES
   (left set in TMDS mode: LINK_CONFIG0=0x100) and FLT_CONFIG1 (left at 0x0f in TMDS mode) on the wedged
   output did not bring the picture back by itself, but the next full modeset (1080p) was GOOD.
6. (diagnostic accident 2) A /dev/mem read sweep over dw-hdmi-qp 0x44-0x5c, 0x160-0x16c, 0x800-0x8a0,
   0x960-0x9fc, 0xa00-0xafc hung the board (watchdog reboot 16:50, nothing logged). Only the fixed list in
   repro/hdmiregs.py (read many times without problems) is used from now on. The 0x40 write in (5) may in
   fact have been harmless; the reboot there came right after it.
7. **Signature found** (repro/hdmiregs.py, safe status registers only): in every working mode
   dw-hdmi-qp VIDEO_INTERFACE_STATUS0 bit 18 (0x40000) is set and VIDEO_MONITOR_STATUS0..5 hold the input
   timing (e.g. 1080p: STATUS2=0x08980780 = htotal 2200 / hactive 1920, STATUS5=0x04650438 = 1125/1080;
   4096 FRL: 0x11301000 = 4400/4096; 4096 YUV420 TMDS: 0x08980800 = 2200/2048). In every "No Signal" case
   - the failing 4096 FRL step itself (r5 h8, at the exact 594 MHz DCLK too) and the persistent wedge
   afterwards (r3 e1/e2/e3, 1080p and 3840 FRL) - bit 18 is clear and the monitor reads garbage
   (STATUS2=0x00020002 "htotal 2 / hactive 2", STATUS0 hsync width = htotal - hsync_len). So the
   controller's video input interface (VOP -> dw-hdmi-qp) has lost lock while the VOP itself runs the mode
   (vop2 summary ACTIVE, vblanks complete) and the TMDS/FRL link to the TV is fine (SCDC locked, CED 0).
   The 500 MHz DCLK (finding 2) is a separate bug: r5 h8 failed with the exact 594 MHz DCLK as well.
8. Trigger statistics (FRL 4096x2160@60 10 bpc right after 4096 YUV420 TMDS + fbdev restore of 3840 YUV420):
   "No Signal" in 5 of 10 tries (r1 c109, r2 b1/c4, r3 d5, r5 h8); after an RGB TMDS mode 0 of 1 (r2 a1).
   A failed FRL step is followed by a persistent wedge in some cases (r1 c110/c111, r3 d6/e1-e3) and not in others.
9. The mainline driver never resets the controller's AVP datapath on a modeset: dw_hdmi_qp_bridge_atomic_disable()
   only sets AVP_DATAPATH_VIDEO_SWDISABLE; AVP_DATAPATH_SWINIT_P is only written in .hdmi_frl_tx_stop (retrain).
   The BSP resets the AVP datapath (with video disabled) at the start of every FRL link training (LTS1) and
   clears both OPMODE_FRL and OPMODE_FRL_4LANES for TMDS; mainline's fallback_tmds leaves OPMODE_FRL_4LANES
   set (LINK_CONFIG0=0x100 in TMDS) and FLT_CONFIG1=0x0f. Also the DT "ref"/"hdp" resets are never used.
10. r6 (diag module, reset off; 5 rounds YUV420 TMDS -> 4096 10 bpc FRL -> 1080p): FRL "No Signal" 3/4
    (f1, f2, f4; f0 was a harness miss), 1080p wedged after 2/5 (t0, t4). **t0 wedged although its FRL step
    never committed** (harness miss): y0 (4096 YUV420) -> fbdev restore (3840 YUV420) -> 1080p RGB = No Signal.
    So the trigger is leaving YUV 4:2:0, not FRL. In YUV420 VIDEO_INTERFACE_STATUS0 = 0x43003, RGB 0x40000,
    lost lock = 0x00000/0x00560 with VIDEO_MONITOR_STATUS2 = 0x00020002.
11. r7 = r6 with the diagnostic dw-hdmi-qp.ko (updates/opi5-hdmi-wedge, param diag_dp_reset=1) resetting the
    AVP datapath (VIDEO_SWDISABLE + AVP_DATAPATH_SWINIT_P) in every atomic_enable after PHY power-on: no
    change (FRL No Signal 3/4, 1080p wedged 2/5, same VIDEO_INTERFACE_STATUS0/monitor signature). The
    controller's AVP datapath is therefore not what is stuck; the video *input* is broken (VOP output or
    the VOP->HDMI interface clocking). Next: diff VOP2 active_regs good vs wedged (r8).
12. r8 (VOP2 debugfs active_regs per step): VOP2 configuration registers are identical between GOOD and
    "No Signal" 4096 FRL steps (only status/counter words differ) -> not a VOP register-state difference.
    Comparing with the BSP: on RK3588 the BSP sets DSP_IF_POL.hdmi_dclk_pol (bit 7) = 1 and HDMI pin_pol for
    HDMI0/1; mainline rk3588_set_intf_mux() never touches DSP_IF_POL for HDMI (bit 7 = 0, DSP_IF_POL read
    0x10000300). Also mainline passes POLFLAG bits to rk3588_get_hdmi_pol(), which decodes them as DRM mode
    flags (BSP passes adjusted_mode->flags) -> GRF VO1_CON0 HDMI0 pol = 1 (hsync "negative") for +h+v modes.
    Next: diagnostic rockchipdrm.ko with runtime params diag_hdmi_dclk_pol / diag_hdmi_grf_pol (r9...).
13. r10 (diag rockchipdrm, DSP_IF_POL bit 7 = 1, GRF pol unchanged): FRL No Signal 1/4, 1080p No Signal 1/5
    (t0). Better than r6-r8 (3/4) but not fixed. t0 failed in r6, r7 and r10: in all three the f0 FRL commit
    never happened (harness mode-cache miss), i.e. the sequence was 4096 YUV420 TMDS -> fbdev restore
    (3840x2160 YUV420 297 MHz) -> 1080p RGB. -> minimal repro repro/hunt2.sh (YUV420 <-> 1080p RGB rounds).
14. r11 (minimal repro, baseline): 1080p No Signal after YUV420 in 1/6 rounds. The failing and the good
    transitions log the identical driver sequence (same PHY config, same VOP dividers) -> timing/phase.
15. Mechanism candidate (VOP2): mainline 0300-116 pulses the VP DCLK reset right after vop2_cfg_done() in
    vop2_crtc_atomic_enable(), i.e. before the shadowed VP registers (RK3588_VP_CLK_CTRL dclk_core_div etc.)
    are taken at the first frame start. YUV420 uses dclk_core_div=1, RGB/FRL 2, so leaving YUV420 changes
    the core divider *after* the reset -> arbitrary phase between dclk_core and the HDMI if_dclk/if_pixclk
    dividers. The BSP resets the VP DCLK only in crtc_output_post_enable(), called by the HDMI driver at
    the end of its enable (for DP after explicitly waiting for the frame-start done bit). Test:
    diag_dclk_rst_mode=1 (wait for the VP cfg_done bit to clear, then reset).
16. In-place recovery tests on a held "No Signal" 4096 FRL state (repro/recover-test.sh, diag modules):
    VP0 DCLK domain reset, VP0 standby+DCLK reset, HDMI0 interface enable toggle in DSP_IF_EN, and the
    dw-hdmi-qp AVP datapath reset (VIDEO_SWDISABLE + SWINIT) all leave VIDEO_INTERFACE_STATUS0 at 0x560
    (no lock) and the TV at No Signal. r12 (VP DCLK reset only after the new VP config was taken): FRL
    No Signal 3/5 -> not the mechanism either. Side finding: rk3588_calc_cru_cfg() never sets *dclk_out_div
    for HDMI and then does ilog2() on the uninitialised value (VP_CLK_CTRL dclk_out_div reads 3); the BSP
    sets dclk_out = dclk_core for HDMI. Constant in all captures, so not the trigger, but a real bug.
17. CMU_IPI_CLK_FREQ (0xb4, kHz, IPI clock = pixel/4): 1080p 37125, 4096 YUV420 74175, 4096 FRL 125000
    (= the 500 MHz DCLK / 4) - identical in GOOD and No Signal FRL steps (r13). So the input clock is
    present and at the same rate; the IPI just does not lock. (gdm's 3840x2160 FRL showed 133673 kHz =
    534.7 MHz DCLK, again a CRU approximation of a 59.94 Hz pixel clock.)
18. In-place GRF tests on a held No Signal FRL state: toggling VO1_CON4 HDMI21 and VO1_CON3 colour format
    (RGB -> YUV420 -> RGB) do not restore the IPI lock either. Remaining in-place candidates: the VOP HDMI0
    interface dividers (DSP_IF_CTRL if_pixclk/if_dclk) - their relative phase is never reset by the VP DCLK
    reset; tests rec3: restart both dividers together (action 6), only if_dclk (7), VP dclk_core_div (8).
19. repro/seqrun.py runs a whole sequence from ONE DRM master (no fbdev restore, no probes between steps).
    s1: [4096 YUV420 TMDS -> 4096 10 bpc FRL] x5: FRL No Signal 2/5 (f0, f1). s2: [1080p RGB -> same FRL] x6:
    6/6 GOOD. -> clean confirmation: the FRL failure needs the preceding YUV 4:2:0 output.
20. s3 (one master): [420 -> 1080p RGB -> FRL] x4: round 2 1080p No Signal and the FRL step after it too
    (sticky across a full TMDS->FRL modeset); [YUV444 -> FRL] x3 and [YUV422 -> FRL] x3: 6/6 GOOD.
    Only *leaving* 4:2:0 triggers it.
21. Hypothesis: mainline writes the HDMI input colour format (GRF VO1_CON3, enc_init) in the encoder's
    .atomic_enable, i.e. after vop2_crtc_atomic_enable() has already started the VOP output (and its DCLK
    reset) in the new format. For a moment the controller's IPI receives the new (RGB) stream while the GRF
    still says YUV 4:2:0, and its 4:2:0 input logic can get stuck (persists over later modesets, no reset
    clears it). Test: diag_grf_early=1 programs the GRF in .atomic_mode_set (runs after the CRTC disable,
    before the CRTC enable), so the format is right before the VOP output starts.
22. s4 (diag_grf_early=1, GRF format written in .atomic_mode_set before the VOP starts): FRL No Signal 3/5,
    1080p 1/4 -> rejected. Next idea: the IPI 4:2:0 logic is left stuck when its clock stops while it is in
    4:2:0 mode (VOP disabled while GRF still says 4:2:0). Test diag_grf_disable=N: encoder .atomic_disable
    (runs before the CRTC disable, clock still running) switches the GRF format to RGB and waits N ms.
23. s5 (diag_grf_disable=40: GRF format -> RGB in encoder .atomic_disable while the VOP still runs, 40 ms):
    FRL No Signal 3/8 -> rejected.
24. In-place VP0 DCLK gate off/on (clk_disable/clk_enable): no cure. After rec4 the board ended in a HARD
    wedge (the user's scenario): s6 = 20 consecutive modesets (3840x2160@30 RGB 297 MHz TMDS, 4096@24 RGB
    TMDS, 4096 FRL) all No Signal, VIF_STATUS0 0x0 / 0x560. Using this state to test cures.
25. **Cure found**: s7 - the hard wedge (20 modesets No Signal) was cleared by turning everything off for
    10 s and then setting 1080p (GOOD, VIF lock 0x40000). s8 - after each failing 420->FRL step, an
    all-off commit, 200 ms, then the same FRL mode: GOOD 3/3. A direct modeset (disable+enable in one
    commit) does not reliably clear it (s3, s6). So the controller needs its input (IPI) clock to be stopped
    for some time between the old and the new mode; a back-to-back modeset never gives it that time.
    Next: measure it - dw-hdmi-qp .atomic_post_disable (runs after the CRTC disable, i.e. VOP DCLK off)
    polls CMU_STATUS.IPI_CLK_OFF.
26. s9 (diag: dw-hdmi-qp .atomic_post_disable waits for CMU_STATUS.IPI_CLK_OFF, timeout 500 ms): the bit
    never sets (CMU_STATUS stays 0x255 with the VOP off), so every modeset had a 500 ms gap with the VOP
    and its DCLK off - and FRL still failed 5/8. -> Not the off-time. The cure in s7/s8 comes from doing
    the disable and the enable in *separate commits*. Next: OFF1 (separate commit, 1 ms gap).
27. **s10: [4096 YUV420 -> all-off commit -> (1 ms) -> 4096 10 bpc FRL] x8: 8/8 GOOD.** The same
    transition as a single modeset fails 40-60 % (s1, s4, s5, s9). So it is not timing and not the
    hardware sequence as such (s9 already had a 500 ms gap with everything off inside the modeset) but
    something that differs in software between an active->active modeset and an off->on enable.
28. s12 (diag_phy_cfg_late=1: phy_set_mode_ext/phy_configure moved from the encoder atomic_check into
    .atomic_mode_set, i.e. not while the old mode runs): FRL No Signal 3/10 -> the check-time PHY
    reconfiguration is not it. Next: s13 = [420 -> commit ACTIVE=0 only (routing/mode kept) -> FRL].
29. **s13: [420 -> commit ACTIVE=0 only -> FRL] x8: 8/8 GOOD.** Correction to 26: in 7.3 disable_outputs()
    runs bridge .atomic_post_disable *before* the CRTC disable, so the s9 500 ms gap was taken while the
    VOP was still running - it did not test the off-time. Next: delay in encoder .atomic_mode_set (runs
    after the CRTC disable, before the CRTC enable) = an active->active modeset with the VOP off for N ms.
30. **s14: active->active modeset with a 200 ms pause after the CRTC disable (encoder .atomic_mode_set,
    diag_modeset_delay_ms=200): [420 -> FRL] x10 = 10/10 GOOD** (baseline 40-60 % No Signal). The VOP->HDMI
    input must stay stopped for a while between the old and the new mode. Next: does the controller
    report this (CMU_STATUS.IPI_CLK_OFF) and how long does it take?
31. **s15: the controller does report it.** Polling CMU_STATUS from the encoder .atomic_mode_set (after
    the CRTC disable): 0x255 (IPI/VIDQP/LINKQP clocks "locked") -> 0x25a (IPI_CLK_OFF | VIDQPCLK_OFF)
    after 1.8-2.3 ms (0x26a when the PHY link clock is off too). In a back-to-back modeset the VOP
    restarts DCLK well within 2 ms, so the clock monitor never sees the IPI clock stop and the IPI is not
    reinitialised; after YUV 4:2:0 input its 4:2:0 state survives and it never locks on the new stream.
    (Consistent with all earlier data: 20 us DCLK gate = no cure; separate disable/enable commits, DPMS
    off/on and a 200 ms pause = always fine; 4:4:4/4:2:2/RGB leave nothing behind.)
    Fix candidate: wait for CMU_STATUS.IPI_CLK_OFF between the CRTC disable and the CRTC enable
    (Rockchip encoder .atomic_mode_set -> new dw-hdmi-qp helper). s16 verifies with the diag build.
32. **s16 (diag build, wait for IPI_CLK_OFF in encoder .atomic_mode_set, no extra delay): [420 -> FRL] x10
    = 10/10 GOOD, [420 -> 1080p] x5 = 5/5 GOOD**; every wait completed (CMU_STATUS 0x255 -> 0x25a/0x26a).
    -> Final patches written (patches/ in this directory), clean drop-in modules built (build/final).
33. Deployed the clean modules (patches 0001-0003 only, no diag code) as /lib/modules/7.3.0-opi5/updates/
    opi5-hdmi-wedge/{drm_display_helper,dw-hdmi-qp,rockchipdrm}.ko + depmod + update-initramfs, rebooted
    (20:00). Diag modules backed up on the board in /var/tmp/wedge/diag-backup.
34. **Verification v1 (fixed modules, one master, camera + input lock): [420 -> 4096 10 bpc FRL] 10/10 GOOD,
    [420 -> 1080p RGB] 5/5 GOOD; regressions GOOD: 3840x2160@60 10 bpc RGB FRL, 3840x2160@120 8 bpc FRL,
    1080p60 RGB, 4096x2160@60 YUV420, 3840x2160@60 8 bpc RGB TMDS (scrambled).**
35. **Verification v2 (fixed modules, original harness path: wedge.py with fbdev restore + connector probe
    before every step, the run-2 order 105-111 and repeats): 13/13 GOOD** (4096 RGB/444/422/420 TMDS, 4096 10 bpc
    FRL after 420 twice, 1080p after FRL, 3840 10 bpc FRL after 420), input lock set in every step.
    Patch 0001: 0 "Resetting CRTC to restore SCDC status" in 13 probes, 8 FRL trainings for 5 FRL steps + fbdev
    restores (before the fix every probe while in FRL caused 1-3 extra retrains). gdm restarted afterwards:
    HDMI-A-1 3840x2160 10 bpc FRL, input locked, picture on the TV (cap/gdm-after.jpg).

## Verification counts (fixed modules)
| test | result |
|---|---|
| [4096 YUV420 TMDS -> 4096 10 bpc RGB FRL AFBC XR30], one master (trigger) | 10/10 GOOD (unfixed: 40-60 % No Signal) |
| [4096 YUV420 -> 1080p RGB TMDS] | 5/5 GOOD |
| original run-2 order via fbdev/probe harness (105-111 + repeats) | 13/13 GOOD |
| regressions: 3840x2160@60 10 bpc FRL, 3840x2160@120 8 bpc FRL, 1080p, 4096 YUV420, 3840 8 bpc TMDS | all GOOD |
| connector probes while in FRL (patch 0001) | 0 CRTC resets (before: every probe) |

## Files
- patches/0001-0003 (format-patch, author Arun Iyengar, Assisted-by trailer only; apply on the 7.3.0-7 stack)
- modules/ (deployed .ko), build/final/ (sources + build.sh), git/ (scratch repo the patches come from)
- repro/: minimal-repro.sh (trigger, one DRM master, judged by the controller lock bit and the camera),
  seqrun.py (sequence runner), wedge.py/run.sh (fbdev-path replay with per-step probes), hunt*.sh,
  hdmiregs.py (safe dw-hdmi-qp status registers via /dev/mem), recover-test.sh / hdmipoke.py (diagnostic only)
- build/synopsys, build/rockchip: diagnostic module builds (diag_* params) used for the experiments
- cap/: all captures (per step cam.jpg, scdc, state, vop2(regs), clk, hdmiregs, logs)
- testmatrix/lib/kmsctl.py: KMSCTL_PROBE=1 makes `show` re-probe (harness fix, item "Harness note")
