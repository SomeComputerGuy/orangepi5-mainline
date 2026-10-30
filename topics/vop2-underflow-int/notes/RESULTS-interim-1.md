# VOP2 POST_BUF_EMPTY at 3840x2160@120 (HDMI 2.1 FRL): interim results

Status: **investigation stopped early (wrap-up requested). Root cause not yet confirmed, no fix yet.**
Nothing is installed on the board. No kernel patch has been committed.

## Setup
- Board kernel: 7.3.0-opi5 #2 (17:38 build, FRL stack 0300-*). VP0 runs HDMI 4K120 FRL 4x10G.
  dclk_vop0 = 1188 MHz, aclk_vop = 750 MHz (the FRL boost works), hclk_vop = 198 MHz.
- DDR: LPDDR4X, 4x16-bit channels. The DDR blob trains F1/F2/F3 and then sets **F0 = 2112 MHz**
  (serial log: `change to F0: 2112MHz`). No dmc devfreq exists in mainline, so DDR stays at the top rate.
  **Low DDR rate is ruled out.**
- Kernel lockdown is `none`.
- VOP NoC QoS (qos_vop_m0 @0xfdf82000, m1 @0xfdf82200), read with the debug module `tools/regpeek`:
  PRIORITY=0x80000202, MODE=3 (regulator), BANDWIDTH=0x140, SATURATION=0x40, identical on m0 and m1.
- Worktrees:
  - `~/orangepi5/work/vop2-underflow-7.3` (branch `opi5/vop2-underflow-7.3`, from hdmi-frl-7.3)
  - `~/orangepi5/work/vop2-underflow-int-7.3` (branch `opi5/vop2-underflow-int-7.3`, from
    `opi5/integration-7.3`; **use this one**, because build 3 = integration).
  - Build dir: `~/orangepi5/build/wt-vop2-underflow` (modules_prepare done).
  - Neither branch has any commits yet.
- Plane IDs on the board:
  - 35 = Cluster0, 41 = Cluster1, 47 = Cluster2, 53 = Cluster3 (all AFBC/RGB)
  - 59 = Esmart0, 65 = Esmart1, 71 = Esmart2, 77 = Esmart3
  - AXI bus per window (rk3588_vop_win_data): Cluster0/1 and Esmart0/1 on AXI0; Cluster2/3 and Esmart2/3 on AXI1.

## Tools (in `tools/`; copy to `~/vop2uf/` on the board)
- `planetest.c`: raw-ioctl atomic KMS test, built on the board with `gcc -O2`. It puts N full-screen planes on CRTC 83
  (XR24 or NV12, NV12 with a 2176-line buffer like rkvdec), flips two buffers every vblank, and `-x` disables other planes.
  The process must be the DRM master. Closing it restores fbcon.
- `runtest.sh <label> <planetest args>`: runs one test. It counts the printed POST_BUF_EMPTY lines plus
  the `vop2_isr: N callbacks suppressed` count, so the second number is the real IRQ count.
- `qos.sh <val|show>`: writes or shows the VOP QoS PRIORITY register through `regpeek.ko`. The module is debug-only:
  it is signed with the build key, and its init fails on purpose so it unloads itself.

## Reproduction matrix (4K120 unless noted, 5-8 s each, POST_BUF_EMPTY IRQs counted)
| test | planes | AXI bus | result |
|---|---|---|---|
| T1 | Cluster0 XR24 alone | 0 | 0 |
| T2 | Esmart0 NV12 alone | 0 | 0 |
| T3 | Cluster0 XR24 + Esmart0 NV12 (= the GStreamer case) | 0+0 | **~370k-460k** (reproduced 4 times) |
| T3-noDP | same, with the DP/vp2 planes 41/65 disabled | 0+0 | **229k** (DP load is not the cause) |
| T3-qos303 | same, with VOP QoS priority 0x202 raised to 0x303 (m0+m1) | 0+0 | **still failing** (serial log) |
| T10 | T3 without flipping (static buffers) | 0+0 | **538k** (not tied to commits or flips) |
| T9 | Cluster0 XR24 + Esmart0 **XR24** | 0+0 | **726k** |
| T5 | Cluster0 + Esmart0 NV12 @ **4K60** | 0+0 | 0 |
| T19 | Cluster0 + Esmart0 NV12 1920x1080 source upscaled to 4K | 0+0 | 0 |
| T4 | Cluster0 + Esmart2 NV12 | 0+1 | 0 |
| T17 | Cluster0 + Esmart3 NV12 | 0+1 | 0 |
| T16 | Cluster2 + Esmart0 NV12 | 1+0 | 0 |
| T7 | Cluster0 + Cluster2 XR24 | 0+1 | 0 |
| T8 | Esmart0 + Esmart2 NV12 | 0+1 | 0 |
| T14 | Esmart0 + Esmart1 NV12 | 0+0 | 0 |
| T11 | Cluster2 + Esmart2 NV12 | 1+1 | 0 |
| T12 | Cluster2 + Esmart2 **XR24** | 1+1 | 0 |
| T18 | Cluster2 + Esmart3 **XR24** | 1+1 | **517k** |

Planes 35 and 41 cannot both go on VP0: mainline restricts possible_crtcs (Cluster1 is on vp2/DP).
The planned repeat run of the full Cluster x Esmart XR24 matrix (2 iterations, to check that the pairs
are deterministic) was interrupted and has no results.

## What the evidence says so far
1. **Not DDR rate** (2112 MHz), **not ACLK** (750 MHz is applied), **not the decoder**, and
   **not commit or flip timing** (fails when static).
2. **Not raw per-AXI-bus bandwidth.** Cluster2+Esmart2 XR24 (~8 GB/s on AXI1) is clean, while
   Cluster0+Esmart0 NV12 (~5.5 GB/s on AXI0) fails. Raising the NoC QoS priority does not help either.
3. The failure needs **4K120 x 2 full-size layers** (60 Hz or a downscaled source is fine), and it shows up only for
   **particular Cluster+Esmart pairs**: (Cluster0, Esmart0) and (Cluster2, Esmart3) fail; (C0,E2), (C0,E3), (C2,E0) and
   (C2,E2) pass. Two Esmarts, or two Clusters, on the same VP pass.
4. The IRQ rate is ~50-90k/s, about 1/3 of all lines (270k lines/s), and the hardware keeps raising it.
   Mainline only rate-limits the message, so this is effectively an **IRQ storm**. A soft lockup
   (`rcu_exp_gp_kthr`, CPU#7) was seen right after a suspend/resume that happened during such a run.
   It may be connected, but this is unconfirmed.

## Hypotheses to test next, in order
- **A. Placement-dependent (DDR bank/row or IOMMU TLB conflicts between the two scanout buffers).**
  This would explain "pair-specific" results that are really just random. Check first by repeating each pair 3 times
  and swapping the allocation order. If the results are random, test with buffers far apart or physically
  contiguous (CMA), and dump the VOP MMU (fdd97e00/fdd97f00) status and fault registers during a run.
- **B. Mixer/overlay throughput at 1 pixel/clk with dclk 1188 MHz.** Check whether VP0 should run its
  core at dclk/2 (2 pixels per clock) in FRL 4K120. Compare `rk3588_calc_cru_cfg()` / the dclk_core_div and
  dclk_out_div settings with the BSP `vop2_calc_cru_cfg` for HDMI FRL. Pair dependence could come from
  layer_sel/zpos ordering: swap the zpos of the failing pairs.
- **C. Overlay delay (dly / bg_dly / pre_scan) values wrong for some window combinations at 4K120.**
  Compare the CLUSTER_DLY_NUM / SMART_DLY_NUM / BG_MIX_CTRL / PRE_SCAN_HTIMING written by mainline
  (`rk3568_vop2_setup_dly_for_windows`, `setup_bg_dly`) with the BSP (its dly tables have 7 entries vs 3 in mainline).
  Dump them with `/sys/kernel/debug/dri/0/vop2/` during a failing and a passing pair.
- Separately (a real bug either way): mainline should not leave POST_BUF_EMPTY unmasked at line rate.
  The BSP sets `post_buf_empty_dsp_vcnt_en` and rate-limits or disables the handling. This is worth a patch,
  but it only hides the symptom, so it is not the fix.

## Next steps (when resumed)
1. Board on build 3 (integration). Copy `tools/` to `~/vop2uf/` and rebuild planetest (gcc on the board).
   regpeek must be rebuilt against `build/linux` once build 3 is final; it uses the same signing key.
2. Repeat the pair matrix (the `for c in ...` loop in this session) with 3 iterations, both zpos orders and
   both allocation orders. This settles hypothesis A against B/C.
3. Dump the VOP2 debugfs regs for failing and passing pairs and diff the DLY/PRE_SCAN/OVL/clock-divider fields
   against the BSP.
4. Fix in `opi5/vop2-underflow-int-7.3`. Build `drivers/gpu/drm/rockchip/` in `build/wt-vop2-underflow`
   (copy Module.symvers from the build-3 tree), sign it, install it to `updates/opi5-vop2/`, then ask for a reboot.
