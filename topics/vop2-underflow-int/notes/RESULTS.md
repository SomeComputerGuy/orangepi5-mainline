# VOP2 POST_BUF_EMPTY at 3840x2160@120 (HDMI 2.1 FRL) with an overlay: root cause and fix

Status: **root cause found, fix written (2 commits), installed on the board (updates/opi5-vop2, srcversion AC143CB5D4949A543E71230, which also
contains the suspend agent's 1101 dw_dp sleep patch). Verification is below.**
The first agent's interim notes are in `RESULTS-interim-1.md`.

## Root cause
The RK3588 VOP2 fetches through **two AXI read ports**, and **one port can't sustain two full-screen
4K@120 layers**. Each window has a fixed default port in `rk3588_vop_win_data`: Cluster0/1 and
Esmart0/1 use AXI0, and Cluster2/3 and Esmart2/3 use AXI1. Mainline writes that fixed value on every
plane update (`VOP2_WIN_AXI_BUS_ID`). The usual configuration (console on Cluster0 = plane 35, which is VP0's primary;
video on Esmart0 = plane 59, which is VP0's overlay; and on a dual display, Cluster1 for DP on VP2) puts
**every active layer on AXI0** while AXI1 sits idle. The port is chosen by a per-window register
(CLUSTER_CTRL[13], ESMART_AXI_CTRL[1]), so the driver can choose it.

## Evidence (build 3, board kernel #3, planetest atomic tests, VOP IRQ rate from /proc/interrupts)
- **Live register write, nothing else changed**: Cluster0 + Esmart0 XR24 at 4K120, static buffers, ~120k POST_BUF_EMPTY/s.
  Writing Esmart0 AXI_CTRL (0xfdd91808) = 0x2 (AXI1) plus cfg_done brings it to **0** (only 30/s of vblank IRQs remain).
  Writing 0x0 back brings it back to ~117k/s. (`tools/devmem.c`)
- **DDR read bandwidth** (rockchip_ddr PMU, `tools/ddrbw.c`). While failing, the VOP read rate *collapses*:
  C0+E0 NV12 = 3.2 GB/s, which is less than C0 alone at 4.9 GB/s. The good pair C0+E2 NV12 reads 6.3 GB/s,
  C0+E2 XR24 reads 9.2 GB/s, and C0+C2 XR24 reads 8.6 GB/s, all clean. So this is not DDR or NoC starvation:
  one port saturates, and its fetch collapses.
- Pair matrix, repeated (it is deterministic, not placement-dependent). Same-port pairs fail: C0+E0, C2+E2, C2+E3,
  E0+E1 XR24, E2+E3 XR24 (70k-120k/s). Cross-port pairs are clean: C0+E2, C0+E3, C0+C2, and C2+E0 / E0+E2 once DP's
  Cluster1 (also AXI0) is disabled. The mild cases (~1-3k/s: E0 XR24 alone, C2+E0, E0+E2) all have Esmart0
  plus DP Cluster1 4K30 on AXI0, and are clean with `-x 41`.
- Geometry. With C0 full-screen 4K120 XR24, a 1920x2160 NV12 overlay on E0 still fails, a 640x2160 one is clean,
  and 3840x64 fails on only a few lines. With E0 full-screen NV12, C0 at 2560 wide is clean and C0 at 3200 wide fails.
  This is a per-port bandwidth threshold of about 4.5-5 GB/s.
- **Ruled out**: ACLK_VOP (750 -> 850 MHz from npll at runtime, `tools/clkpoke`: no change); NoC QoS
  (priority 0x202 -> 0x303, mode regulator -> none, ext-control: no change); buffer placement and IOMMU TLB
  (both planes scanning the *same* buffer fail the same way); DDR rate (fixed 2112 MHz); overlay/dly/pre-scan
  (registers are identical between failing and passing pairs apart from layer_sel/port_sel).
- Vendor BSP (`_downloads/hdmi-frl/bsp`): it uses the same fixed per-window axi_id table
  (`rk3588_vop2_win_cfg_axi`), so it has the same exposure. The Orange Pi BSP DT runs ACLK at 800 MHz,
  but we showed that ACLK doesn't matter.

## Fix (branch `opi5/vop2-underflow-int-7.3`, patches in `patches/`)
1. `drm/rockchip: vop2: Balance window fetches across both AXI ports on RK3588`. When a window starts fetching,
   the driver picks its port by estimated load (src w*h*bpp*refresh), takes the port that leaves the busier port least loaded
   (default port on a tie), and never uses a port where another active window has one of the same AXI read IDs.
   The table IDs are mirrored between ports, so a free port always exists. A window keeps its port while it is enabled.
   The feature flag `VOP2_FEATURE_AXI_BALANCE` enables it on RK3588 only. Typical result: DP Cluster1 on AXI0,
   console Cluster0 on AXI1, video Esmart0 on AXI0.
2. `drm/rockchip: vop2: Report POST_BUF_EMPTY at most once per frame`. This is the IRQ-storm fix: mask the
   interrupt when it fires, and re-arm it at the next frame start (FS is enabled for that frame even with vblank off).
Both pass `checkpatch --strict` and W=1, and carry `Assisted-by: Claude:claude-opus-5-5`.

## 4K60 "looks good then warps for a bit"
The same mechanism applies: at 4K60 the console, overlay and DP layers all sit on AXI0, so DDR contention
from other masters (which raises read latency) pushes that one port over its limit. The bursts the DP agent
saw at 127-140 s of the 22:13 boot were my 4K120 planetest runs. A CPU memcpy load (8 threads) caused no
4K60 underflow with C0+E0 on the unfixed kernel. Real-decode tests: see Verification.

## Tools (`tools/`)
planetest.c (now with `@X,Y,W,H` destination rects and `SHARE=1`), rt.sh/rtb.sh/rtl.sh (on the board in `~/vop2uf`),
irqrate.sh, devmem.c (/dev/mem MMIO r/w; IO_STRICT_DEVMEM is off), ddrbw.c (DDR PMU), clkpoke (debug module that sets a VOP clock rate),
regpeek3 (regpeek rebuilt for build 3), memhog.c.

## Side note: the 22:13 board panic
It was not caused by this work: the DP agent read `/sys/kernel/debug/regmap/fed80000.phy/registers` (USBDP PHY) while that PHY was powered off.

## Verification (fixed module, boots of 22:33 and 22:45)
Note: with patch 2 an underflowing port raises at most one IRQ per frame, so irq/s no longer shows
underflow. Count dmesg POST_BUF_EMPTY lines plus "callbacks suppressed" instead (`rc.sh`, `vm.sh`); one count is one bad frame.

planetest, 4K120, 6 s (720 frames). Counts are bad frames; AXI ports are read back from the window registers:
| case | before (IRQ/s) | after (bad frames / 720) | ports |
|---|---|---|---|
| C0 XR24 + E0 NV12 (the kmssink case), DP C1 on | ~90k/s | **0** | C0:0, E0:1, C1:1 |
| C0 + E2 NV12 | 0 | 0 | |
| C0 XR24 + E0 XR24, DP off | ~120k/s | **0** | |
| C2 + E3 XR24, DP off | ~100k/s | **0** | |
| E0 + E1 XR24, DP off | ~90k/s | **0** | |
| C0 XR24 + E0 XR24 + DP C1 XR24 4K30 | ~120k/s | 279 | 4.0 \| 5.1+1.0 GB/s |
| C2+E2 / C2+E3 / E0+E1 XR24 + DP C1 | | 108-253 | |

The last two rows are over the hardware limit: two full-screen *RGB* 4K120 layers plus a 4K30 RGB
second display need 9-10 GB/s, so one port always gets more than 5 GB/s. (Esmart XR24 actually reads
about 5.1 GB/s at 4K120 per the DDR PMU, more than a Cluster's 4.0.) Video overlays are NV12, so the
real-world cases stay well inside the limit.

kmssink, final matrix (boot of 23:17). `vm.sh`: modetest -d holds the mode with a pattern on the primary plane (stands in
for the console, without fbcon cursor commits). Reference clips ~/codecsweep/work/ref_h265_3840x2160_{60,30}.mkv,
v4l2slh265dec, `skip-vsync=true`. "load" = a concurrent 4K120 HEVC decode looping to fakesink.
| case | load | bad frames | rendered/dropped (9 s window) | port loads, AXI0 / AXI1 GB/s |
|---|---|---|---|---|
| (a) HDMI 4K120 + NV12 overlay | idle | **0** | 208 / 0 | 3.98 (C0) / 2.49 (E0 1.49 + DP C1 1.0) |
| (a) | decode | **0** | 202 / 2 | same |
| HDMI 4K60 + overlay | idle | **0** | 196 / 2 | 1.99 / 1.74 |
| HDMI 4K60 + overlay | decode | **0** | 189 / 5 | same |
| (b) HDMI 4K120 + DP 4K30, overlay on DP | idle/decode | **0** | DP 189 / 1 | 3.98 / 1.37 |
| (b) HDMI 4K120 + DP 4K30, overlay on HDMI | decode | **0** | 209 / 1 | 3.98 / 2.49 |
| (c) dual-display weston demo (HDMI 4K60 + DP 4K30, two BBB players), 10+ min | real | **0** | (coordinator) | E3 on AXI1, E2 moved to AXI0 |
| BBB 4K60 H.264 demo on HDMI over the console, ~4 min | real | **0** | | 1.99 / 1.74 |
| 60 s yacht HEVC loop at 4K120 + overlay | idle | **0** | | |

The few drops come at pipeline start. Two kmssink processes can't both be DRM master, so (b) with overlays on both
displays at once wasn't run with kmssink. Its worst case is 3.98 / 2.86 GB/s, under the ~5 GB/s per-port limit,
and the weston demo covered the dual-overlay case at 4K60 + 4K30.

## Open points
- Three RGB layers (two full-screen XR24 4K120 + DP XR24 4K30) exceed what the two ports can carry (see above). A window
  keeps its port while enabled, so the split also depends on enable order. That is acceptable for real use
  (video is NV12). A smarter policy could move a window between ports at a frame boundary if ever needed.
- Pacing: kmssink at 4K120 renders ~60-63 fps of 120 fps content even though decode-only reaches 125 fps. This is the
  blocking legacy SetPlane path in kmssink (see dp-smooth RESULTS), not vop2: planetest atomic flips run 120/120.
  4K60 content plays at 60.
