# dp-silent-black: state (task: DISPLAY-OPEN item 4 class / vop2-splice STATE.md open item B)

Updated 2026-11-06 (code agent; 15dpirq1 built rc=0, no compiler warnings; JOB dp-black-1 submitted, no board result yet).

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
- Waiting for JOB dp-black-1 (runner) -> RUNNER-SUMMARY.md here.
- Patch export: patches/0001-drm-bridge-synopsys-dw-dp-Retrain-a-lost-link-with-a.patch
