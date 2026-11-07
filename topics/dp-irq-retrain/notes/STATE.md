# dp-silent-black: state (task: DISPLAY-OPEN item 4 class / vop2-splice STATE.md open item B)

Updated 2026-11-06 evening (code agent #2; k16-dpblack built as 16dpb1; JOB dp-black-2 queued as
RUNNER-QUEUE/048-dp-black-2.job; no board result yet).

## NOW (read first)
- dp-black-1 (RUNNER-SUMMARY.md): k15-dpirq does NOT change the rate (stock 1/180, fix 1/180, p=0.75). Both
  blacks (B1 it 27, F2 it 53): DPCD 0x202-0x204 = 77 77 81/01 (4 lanes CR/EQ/symbol lock, aligned), 0x205 = 03
  (RECEIVE_PORT_0_STATUS = sink in sync with the stream), 0x600 = 01 (D0), 0 kernel errors, 0 POST_BUF_EMPTY,
  dyndbg kmsg identical to the good iteration before it (same Attention -> train -> "new mode: 4" timing).
  Camera (run-B1/out/it/27/cam1.jpg): DP monitor black with its own small "DisplayPort" source OSD label visible
  (= the monitor has a signal and is showing it; gone at cam2 4 s later, still black). => link and stream timing
  arrive; the PIXELS are black/missing -> problem is between VOP2 VP2 output and the DP controller's video input.
- Vendor comparison (Orange Pi 6.1 dw-dp.c:4416-4475, rockchip_drm_vop2.c:1218-1254, 9582-9591):
  1) vendor VOP2 crtc enable programs dp0_mux/pin_pol but NOT dp0_en; the DP bridge enables dp0_en
     (rockchip_drm_crtc_output_post_enable -> vop2_crtc_output_post_enable: dp0_en=1, cfg_done, wait frame start)
     only AFTER link training + dw_dp_video_enable (VIDEO_STREAM_ENABLE), and clears it BEFORE video disable.
     Mainline sets RK3588_SYS_DSP_INFACE_EN_DP0 in rk3588_set_intf_mux() from vop2_crtc_atomic_enable(), i.e.
     before the bridge trains the link and configures/enables the stream (the DP controller gets the VP output
     during training, and VIDEO_STREAM_ENABLE is set at a random point of the incoming frame), and never clears
     it. => candidate 1 (prime), fixed in b95a72baf990.
  2) vendor enables + reports VIDEO_FIFO_OVERFLOW_STREAM0..3 interrupts (dw_dp_init, irq handler
     dev_err_ratelimited "video fifo overflow"); mainline never enables them -> a stream whose input does not
     fit is silent. => diagnostic/upstreamable 28bda10b7ba8 ("video FIFO overflow" once per stream).
  3) mainline dw_dp_bridge_atomic_disable soft-resets the controller (dw_dp_reset) while VP2 still feeds it
     (crtc disable comes after); vendor does no reset there. Not changed (with 1) the interface is off from the
     CRTC disable on; the enable side is what the fix orders).
- Not candidates by data: in-place retrain / IRQ_HPD (dp-black-1), POST_BUF_EMPTY/ACLK (0 vp2 errors at the
  blacks), link loss (DPCD OK), sink power state (D0).

## Branch k16-dpblack (src/linux, worktree ~/orangepi5/build/wt-k16dpb), on k16-rc2 c8672baa79b5
- b95a72baf990 drm/rockchip: vop2: Enable the RK3588 DP interface after the encoder
  (rk3588_set_intf_mux: DP0/DP1 mux+pol only, bit recorded in vp->if_en_deferred; vop2_crtc_atomic_flush on a
  modeset sets it under vop2_lock before cfg_done (commit_tail_rpm runs flush after the encoder/bridge enables),
  vp->if_en_on cleared in vop2_crtc_atomic_disable (after vblank_off, before standby) and on the enable error path.
  drm_dbg_kms "vpN: interface enable 0x.. after the encoders".)
- 28bda10b7ba8 drm/bridge: synopsys: dw-dp: Report video FIFO overflows (enable in video_enable after
  VIDEO_STREAM_ENABLE, status cleared first; irq: first overflow per stream -> dev_err "video FIFO overflow" and
  masks itself; video_disable masks it).
- f1ae6e775d2f TEST: rockchipdrm.dp_if_gate module param (0 = old order, runtime, next modeset). Drop at export.
- checkpatch --strict clean (both real commits). Build: OPI5_REF=k16-dpblack OPI5_PKGREV=16dpb1
  OPI5_OUT=$HOME/orangepi5/out/test/dpblack, log logs/build-16dpb1.log: rc=0, no compiler warnings; uname -v "#16dpb1".

## JOB dp-black-2 (b2/HANDOFF.md, TEST ~7 h, queued RUNNER-QUEUE/048-dp-black-2.job)
- b2/tools: run-dpb2.sh (blocks D1..D7 x 200, one kernel), run.sh (board dir /var/tmp/dpblack2, unit
  dpblack2-run), dpblack-board.sh (per iteration: dp_if_gate = 0 on odd, 1 on even n; iter.tsv columns gate=,
  ovf= (FIFO overflow lines between start and verdict markers = the client's modeset), ovfall=), check-dpb2.sh
  (self-tested on synthetic data from run-B*).
- PASS = gate1 0 overflows, 0 warnings, gate1 black rate < reference (gate0 + dp-black-1 2/360), Fisher p<0.05.
  Power is limited (~0.55% event): gate1 0 black with p>=0.05 -> INCONCLUSIVE.

## Reading the dp-black-2 result (next agent)
- gate0 blacks WITH ovf>0 and gate1 0 overflows/0 black -> mechanism confirmed (stream start on a live input);
  export b95a72baf990 + 28bda10b7ba8 (proposal in patches/, coordinator decides), drop the TEST commit.
- gate0 overflows at many good iterations too -> the overflow is a start transient; still evidence for the order.
- gate0 blacks WITHOUT any overflow and gate1 also black -> not the enable order: next candidates
  (a) VOP2 side: VP2 scans but the window/plane is not shown on VP2 (layer mixer / port_sel; vop2-splice item A
      shares the intermittent vp2 symptom) -> diagnostic: read-only vop2 debugfs summary + DRM state at a black
      frame (camcal CAL_DIAG pattern in k15/vop2-splice/tools/camcal.sh) and compare to the good iteration;
  (b) dw-dp reset while the VP feeds (item 3 above) -> move dw_dp_reset after... / drop it, A/B;
  (c) monitor-internal (sink in sync, D0): document as monitor behaviour if (a) shows identical state.
- gate1 black rate much higher than gate0 (order breaks something) -> FAIL, revert b95a72baf990.

## Older (dp-black-1, code agent #1)
## Problem
After a dual-head modeset the DP monitor (Samsung LU28R55, USB-C->DP cable, DP Alt Mode via FUSB302/tcpm, pin C
4 lanes) is black (no signal glow) while the kernel logs nothing and drm.debug/vop2/clk/DRM state equal a good run.
~1 in 20-40 dual modesets: run-sp14 calrep run 12 (vs good run 11), run-sp6 cal-1, run-sp3 r-4k60-limited, stock k14
dualmatrix CAM_DP_BLACK. Only visible difference (run 12 vs 11, kmsg-all.txt 939.1 vs 1021.4): the DP-1 OOB hotplug
event (= a DP Alt Mode Attention; typec displayport calls drm_connector_oob_hotplug_event on EVERY Attention) at
+177 ms after the atomic_check (~75 ms after the DP stream was enabled: HDMI "Disabling scrambling" at +102 ms marks
the end of the DP enable, DP-1 is enabled first) instead of +102 ms (= right at the end of DP link training).

## Code findings (k15-v4, drivers/gpu/drm/bridge/synopsys/dw-dp.c)
- Every Attention with HPD still high -> dw_dp_bridge_oob_notify -> hpd_work as a short pulse. (The PHY mux_set
  of the same Attention is a no-op for an unchanged pin assignment; the GRF HPD force rewrite writes the same value.)
- Short pulse (k15-v4): lock-free dw_dp_needs_link_retrain() (link->enabled && !channel_eq_ok on 0x202-0x207);
  if lost, dw_dp_link_retrain() = connection_mutex + dw_dp_link_train() IN PLACE: dw_dp_link_configure() moves
  the PHY to P3 and reprograms its rate (phy_configure set_rate) and runs TPS1/TPS2-4 while VIDEO_STREAM_ENABLE
  stays on and the VOP2 keeps feeding. No message on success (dev_dbg only) -> a silent black candidate.
  An Attention arriving while a commit is training the link (link->enabled still false) is dropped without any
  later check.
- Vendor BSP 6.1 (drivers/gpu/drm/rockchip/dw-dp.c dw_dp_hpd_work/dw_dp_link_retrain:4733): same in-place
  retrain under the running stream (vendor typec mux path: IRQ_HPD -> short, HPD -> long pulse). Vendor also
  services 0x201 (automated test) - not relevant here.
- i915: retrains SST links through a modeset commit (since 6.12); amdgpu: dpms off -> train -> dpms on. Both stop
  the stream around a retrain.
- D3: link_disable writes DP_SET_POWER D3 before the controller reset, enable writes D0 (drm_dp_link_power_up, 1 ms)
  then trains - same as i915/amdgpu/vendor; not changed.
- Not proven on the board which branch the bad run took (dw-dp dev_dbg was off). JOB dp-black-1 captures it.

## Fix: branch k15-dpirq (src/linux, worktree ~/orangepi5/build/wt-k15dpirq), on k15-v4 (bb1a61971a26)
- 22d65302970c "drm/bridge: synopsys: dw-dp: Retrain a lost link with a pipeline reset": short pulse -> CEC irq /
  downstream check as before, then dw_dp_link_check() with modeset locks (connection_mutex + CRTC mutex, waits for
  a blocking commit in flight, skips if the CRTC's commit has not reached hw_done like vc4), link status checked
  under link_lock; a lost link -> drm_atomic_helper_reset_crtc() (stream off, link off/D3, D0, train, stream on).
  Max 3 resets in a row (10 s window), then dev_warn "giving up". dev_dbg: "OOB HPD event", "link status: <6 bytes>",
  "link lost, resetting the pipeline (n)". checkpatch --strict clean.
- Does not overlap k15-dpycc (that touches bus format/color format paths only): based on k15-v4 as briefed.
- Build: OPI5_REF=k15-dpirq OPI5_PKGREV=15dpirq1 OPI5_OUT=$HOME/orangepi5/out/test/dpirq; log logs/build-15dpirq1.log.

## Board package (JOB dp-black-1, HANDOFF.md, TEST ~3 h)
- tools/ = copies of k15/vop2-splice/tools (kmsctl.py, camverdict.py, camcal.sh unchanged; run.sh adapted: TEST-only
  locking, unit dpblack-run, resume of iter.tsv) + dpblack-board.sh (calibration, N iterations of one dual-head
  1080p60 bars client each, camera verdict DP/HDMI, DPCD 0x200-0x207/0x600/0x2002-0x2005 via /dev/drm_dp_aux*,
  dyndbg dw_dp + dw_dp-rockchip.c + phy-rockchip-usbdp.c, kmsg markers "=== dpblack <n> start/end"),
  run-dpblack.sh (blocks B1 F1 B2 F2 B3 F3 x 60, stock 15 vs 15dpirq1, pause/resume), check-dpblack.sh.
- Submitted to the runner as "JOB dp-black-1 ~/orangepi5/work/_out/k15/dp-silent-black/HANDOFF.md".

## Reading the result (next agent)
- Per black iteration: run-<blk>/out/it/<n>/kmsg.txt (dyndbg) + iter.tsv dpcd column:
  a) baseline black with "Retraining link" (stock dev_dbg) in kmsg.txt -> in-place retrain was the trigger; fix
     should show "link lost, resetting the pipeline" and GOOD instead.
  b) black with lane status not OK (dpcd bytes 2-3 != 0x77 0x77 for 4 lanes, byte 4 bit0 align) and no retrain ->
     a lost link never checked (Attention during training) -> fix covers it.
  c) black with link OK (0x202/0x203 = 77 77, 0x204 bit0 = 1) but 0x205 bit0 (RECEIVE_PORT_0_STATUS, sink in sync)
     = 0 -> stream-side (MSA/TU/video FIFO) problem: next step = check stream status on the sink side, consider a
     reset on "not in sync" (not in the fix yet: i915/amdgpu do not use 0x205).
  d) link OK and in sync, pwr=01 (D0) -> sink-internal; nothing for the kernel (document as monitor behaviour).
- If PASS: export 22d65302970c to patches/ (proposal in this dir; coordinator decides), keep the dev_dbg lines.

## Open items
- Wait for JOB dp-black-2 -> b2/RUNNER-SUMMARY.md (+ b2/check.txt).
- k15-dpirq (22d65302970c): no effect on this bug; keep off the export unless another bug needs it.
- If the result is PASS/mechanism confirmed: commit message of b95a72baf990 is written as the fix; if not, reword.
