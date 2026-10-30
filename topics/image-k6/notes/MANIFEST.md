# Orange Pi 5 kernel patch stack (v7.3): manifest

`scripts/build-kernel.sh` resets `src/linux` to v7.3 and applies `patches/linux/*.patch` in name
order. With `OPI5_EXTRA=1` it then also applies `patches/linux-extra/*.patch` and merges
`scripts/opi5-extra.config`. The stack was exported from these branches in the shared kernel repo:

- `opi5/integration-7.3`: v7.3 + `patches/linux` (291 commits; worktree `work/integration-7.3`)
- `opi5/integration-extra-7.3`: `opi5/integration-7.3` + `patches/linux-extra` (14 commits)

They were exported with `work/_out/integration/tools/export-stack.sh`. Applying the patch files
with `git apply --index` on a clean v7.3, as build-kernel.sh does, gives exactly the trees of the
two branches (tree `f099e1f92` for main, `b95e48395` for main+extra). The previous
`patches/linux` (230 patches) is kept in `patches/linux.bak-20261029`.

"Board" means it ran on the Orange Pi 5 test board on 2026-10-29: either in the 7.3.0-opi5 kernel
built from `patches/linux` (16:45/17:44 builds), or as drop-in modules and the combined DTB built
from the listed branch. Evidence paths are relative to `work/_out/`. Nothing has been sent
upstream from this project.

## Main stack: `patches/linux/` (291 patches, applied by default)

| Range | # | What | Source | Tested on hardware | Evidence | Upstream status |
|---|---|---|---|---|---|---|
| 0001 | 1 | Orange Pi 5 M.2 SATA DTB variant | ours (`5e33b74b0`) | Board: boots from SATA | memory `opi5-image-build` | local, not posted |
| 0101 | 1 | rga/rkvdec "sync with the 7.4 merge window" backport | ours (`opi5/multicore-7.3`) | Board (drop-in modules, now in-kernel) | `multicore/NOTES.md` | backport of what is in 7.4 |
| 0102-0118 | 17 | RGA3 multi-core, v4l2-mem2mem parallel jobs (Sven Püschel) | `opi5/multicore-7.3` | Board | `multicore/NOTES.md` | on the list (not in 7.4) |
| 0119-0122 | 4 | rkvdec multi-core (Detlev Casanova) | `opi5/multicore-7.3` | Board | `multicore/NOTES.md`, `vp9-perf/RESULTS.md` | on the list |
| 0130-0134 | 5 | arm-smmu-v3: PCIe SMMU power domain and clock (SATA-root reboot hang) | ours (`opi5/shutdown-hang-7.3`) | Board: reboot < 1 s | `shutdown-hang/RESULTS.md` | not posted |
| 0201-0261, 0263-0265 | 64 | USBDP PHY, RK3588 dwc3 glue, dw-dp improvements and audio, OOB HPD, typec mux fixes (Sebastian Reichel and others) | `opi5/dp-altmode-7.3` | In the board kernel; USB works. DP alt mode itself is untested (needs the extra DT) | `dp-altmode/RESULTS.md` | on the list (v11 dw-dp, usbdp series); some Collabora gitlab only |
| ~~0262~~ | - | "drm/bridge: Keep oob_notify at the end of drm_bridge_funcs" | - | - | - | **dropped**: local struct-layout hack that was only needed for module-only deployment; upstream position restored |
| 0266 | 1 | arm64: dts: rockchip: Fix DP sound-dai-cells on RK3588 (Sebastian Reichel) | `_out/dp-altmode/dt/0001` | DT only, dp0 is disabled on the OPi5 without the extra DT | CHECK_DTBS (below) | Collabora gitlab; the follow-up promised by 0260 |
| 0300-001..121 | 121 | HDMI 2.1 FRL, SCDC, HDMI connector rework (Cristian Ciocaltea, Nicolas Frattaroli) | `opi5/hdmi-frl-7.3` | In the board kernel; FRL itself untested (no HDMI 2.1 sink attached) | `hdmi-frl/RESULTS.md` | SCDC parts in 7.4; FRL series not posted |
| 0400-0401 | 2 | dwmac-rk delay fix, i2s-tdm XFER reset value | ours (`opi5/board-hygiene-7.3`) | Board (Ethernet with rgmii-id) | `board-hygiene/RESULTS.md` | not posted |
| 0501-0514 | 14 | rocket NPU core numbering/devfreq/cooling, GPU bus clock + SCMI GPU clock, panthor/devfreq suspend fixes (Igor Paunovic, Jonas Karlman, ours) | `opi5/gpu-npu-7.3` | Board | `gpu-npu/RESULTS.md`, `gpu-npu/TESTING.md` | NPU DVFS on the list; GPU parts armbian PR 380 / not posted |
| 0601-0603 | 3 | rkvdec VDPU381 VP9 (Venkata Atchuta Bheemeswara Sarma Darbha, v1 2026-07-26) | `opi5/vp9-perf-7.3` | Board | `rkvdec-vp9/NOTES.md` | on the list, not in linux-next |
| 0604 | 1 | rkvdec: align bytesperline to 64 (Igor Paunovic) | `opi5/vp9-perf-7.3` | Board | `rkvdec-vp9/NOTES.md` | on the list |
| 0605-0609 | 5 | VP9 multi-core port, smaller frames, register reset, segmentation map, cached count table | ours (`opi5/vp9-perf-7.3`) | Board: fluster 230/305, 4K 156 fps | `vp9-conf/RESULTS.md`, `vp9-perf/RESULTS.md` | not posted |
| 0701-0708 | 8 | Hantro multi-core (4x VEPU121 JPEG), reboot-panic fix, error path, encoder reset, IOMMU re-init after timeout | ours (`opi5/hantro-robust-mc`) | Board | `hantro-multicore/RESULTS.md`, `hantro-robust/TESTING.md` | not posted |
| 0709-0710 | 2 | VEPU121 reset lines (binding + DT) | ours (`opi5/hantro-robust-mc`) | Board (combined DTB) | `hantro-robust/TESTING.md` | not posted |
| 0711-0714 | 4 | Hantro encoder format validation: min sizeimage, coded size follows OUTPUT, JPEG geometry check, fixed JPEG colorimetry | ours (`opi5/hantro-validate`, via `opi5/hantro-integrated`); 0714 amended, see below | **No**: built W=1 only; the board runs hantro without them | `hantro-validate/TESTING.md` | not posted |
| 0801-0807 | 7 | V4L2 H.264 stateless encode uAPI and core, [PATCH 1-7/14] v1 (Paul Kocialkowski) | lore `20260522101653.2565125-1-paulk@sys-base.io` | Board (as the v4l2-core modules under the H.264 encoders) | `vepu121-h264enc/RESULTS.md`, `rkvenc/RESULTS.md` | RFC/v1 on the list, not merged |
| 0808-0809 | 2 | H.264 encode core fixes: write SPS/PPS only on change, POC type 2 | ours | Board | same | not posted |
| 0811-0817 | 7 | V4L2 HEVC stateless encode uAPI, RBSP writer, core, KUnit tests, docs | ours (`opi5/hevc-enc-uapi`, as on `opi5/rkvenc-hevc-7.3`) | Board (via the VEPU580 HEVC tests) | `rkvenc-hevc/RESULTS.md`, `hevc-enc-uapi/DESIGN.md` | not posted (draft `hevc-enc-uapi/COVER-LETTER.txt`) |
| 0821-0823 | 3 | Hantro encoder prerequisites from Paul's series 8, 10 (Marco Felsch), 11 | lore, same series | Board | `vepu121-h264enc/RESULTS.md` | on the list |
| 0824-0826 | 3 | Hantro VEPU2 (RK3588 VPU121) H.264 encoder + DT encoder IRQ | ours (`opi5/vepu121-h264enc`) | Board | `vepu121-h264enc/RESULTS.md` | not posted |
| 0831-0833 | 3 | VEPU580 binding, H.264 stateless encoder driver, DT nodes | ours (`opi5/rkvenc-7.3`) | Board | `rkvenc/RESULTS.md` | not posted |
| 0834-0835 | 2 | VEPU580 HEVC encoding | ours (`opi5/rkvenc-hevc-7.3` @ `71d50a1e6`) | Board (18:31-18:40) | `rkvenc-hevc/RESULTS.md`, `rkvenc-hevc/board-run2.txt` | not posted |
| 0901-0903 | 3 | VDPU720 JPEG decoder: binding, driver, DT | ours (`opi5/rkjpegd-7.3`) | Board | `jpeg-dec/RESULTS.md` | not posted |
| 0911-0914 | 4 | IEP2 deinterlacer: uAPI controls, binding, driver, DT | ours (`opi5/iep2-7.3`) | Board (v4l2-compliance 57/57) | `iep2/RESULTS.md` | not posted |
| 1001-1003 | 3 | OPi5 board DT hygiene: rgmii-id, SPI NOR vcc-supply, RK806 reset mode | ours (`opi5/board-dt`) | Board (combined DTB) | `board-hygiene/RESULTS.md` | not posted |
| 1004 | 1 | Build the OPi5/5-SATA/5B DTBs with `-@` (DTC_FLAGS_<board>) | ours (new) | The board DTB was built with `DTC_FLAGS=-@`; identical output | DTB comparison below | local |

Not carried over from the source branches:
- `DO NOT UPSTREAM: media: v4l2-ctrls: Keep the v4l2-core symbol versions` (H.264, on
  `opi5/vepu121-h264enc` and `opi5/rkvenc-7.3`) and its HEVC twin (`opi5/rkvenc-hevc-7.3`):
  dropped, see "Decisions".
- Duplicates on `opi5/board-dt` (IEP2, JPEG decoder, VEPU121 resets, SMMU, VPU121 IRQ, VEPU580,
  NPU and GPU DT): identical patch-ids to the commits above, taken once.
- The rkvenc copy of "Support picture order count type 2": the `opi5/vepu121-h264enc` version
  (0809) is a superset (it also lets the SPS writer accept type 2), so it is used.

## Optional stack: `patches/linux-extra/` (14 patches, only with `OPI5_EXTRA=1`)

None of this has run on hardware.

| Range | # | What | Source | Evidence | Upstream |
|---|---|---|---|---|---|
| 0001 | 1 | USB-C DP alt mode DT for Orange Pi 5/5B | `_out/dp-altmode/dt/0002` | `dp-altmode/RESULTS.md` | based on Collabora ROCK 5B DT |
| 0101-0104 | 4 | ILI9881C Innolux AFJ101-BA2131 panel + binding, dsi2 chip-data sentinel fix, LCD1/LCD2 overlays | `opi5/dsi-7.3` | `dsi/RESULTS.md` | not posted |
| 0201-0205 | 5 | rkisp2 driver, params/stats nodes, binding, ISP DT nodes (Xu Hongfei, Paul Elder) | `opi5/camera-7.3` | `camera/RESULTS.md` | v3 on the list (`20260827-rkisp2-v3-0-e91ff0a604d6@ideasonboard.com`) |
| 0206-0209 | 4 | rkisp2 stats fix, drop third ISP0 IRQ, IMX219 and OV13850/OV13855 CAM1 overlays | ours (`opi5/camera-7.3`) | `camera/RESULTS.md` | not posted; OV138xx overlays not for upstream |

`scripts/opi5-extra.config` adds `CONFIG_VIDEO_ROCKCHIP_ISP2=m` (the other options it lists are
already modules in Ubuntu's config). The suspend TF-A patch is in `patches/tf-a`, unchanged.

## Decisions

**DO NOT UPSTREAM symbol-version commits: dropped.** They only existed so that new videodev.ko and
hantro/rkvenc modules could be dropped onto the running 7.3.0-opi5 kernel without changing the
gendwarfksyms CRCs of the other v4l2-core exports. They remove the `p_h264_encode_params` (and
HEVC `p_hevc_encode_*`) members from the in-kernel `union v4l2_ctrl_ptr` and turn
`V4L2_CTRL_TYPE_H264_ENCODE_PARAMS`, `V4L2_CTRL_TYPE_HEVC_ENCODE_PARAMS` and
`V4L2_CTRL_TYPE_HEVC_ENCODE_FEEDBACK` from `enum v4l2_ctrl_type` enumerators into `#define`s. In a
full kernel build every module is rebuilt, so they're unnecessary. Dropping them doesn't change the
uAPI ABI: the control type values (0x0206 and the HEVC ones) and structures are the same, and
userspace sees the same names. The only source-level difference for userspace is that the names
are enumerators again (as in Paul's series) instead of macros, so `#ifdef
V4L2_CTRL_TYPE_H264_ENCODE_PARAMS` no longer works; nothing in our tools relies on it. In the
kernel, the H.264 and HEVC cores use the union members again, and `v4l2_ctrl_type_op_log()`
switches on the enum without the `(u32)` cast. No behaviour change.

**0262 (oob_notify at the end of drm_bridge_funcs): dropped** for the same reason. Every
`drm_bridge_funcs` user uses designated initializers, so it only changes the structure layout.

**0714 amended: the fixed JPEG colorimetry only applies to the JPEG coded format.** The validate
commit forced sRGB/BT.601/full range on every encoder context because JPEG was then the only coded
format. With the VEPU2 H.264 encoder (0825), the H.264 core writes the VUI colour description from
the CAPTURE format, so it would always have signalled full-range sRGB and ignored the
application's colorimetry. The check is now `ctx->is_encoder && vpu_fmt->codec_mode ==
HANTRO_MODE_JPEG_ENC`. H.264 keeps the propagation it was tested with.

**0266 (DP #sound-dai-cells = <1>) is in the main stack.** 0260 changes the binding to require 1
cell, and its commit message defers the DTS fix to this patch. Without it, CHECK_DTBS warns on
dp0. It is a disabled node on the OPi5.

**1004 (`-@`) is a kernel Makefile change, not a build-kernel.sh flag.** `make DTC_FLAGS=-@` on
the command line overrides every `DTC_FLAGS +=` in scripts/Makefile.dtbs (the `-Wno-...` flags and
per-board flags), and it would add symbols to every DTB. `DTC_FLAGS_<board> := -@` is the per-board
mechanism the Allwinner and MediaTek Makefiles already use. The deb's `dtbs_install` ships these
DTBs, so the image gets overlay-capable DTBs without a script change. With `OPI5_EXTRA=1`, the
in-tree overlay application tests also add `-@`.

## Verification (2026-10-29)

Details in `checks.txt`. Summary:
- Both stacks apply on clean v7.3 with build-kernel.sh's loop and give the branch trees.
- A full `Image modules dtbs` build exits 0. The only warnings are pre-existing frame-size ones in untouched code.
  W=1 on the media drivers: 0 warnings (`w1-media.txt`, `w1-other.txt`, `w1-extra.txt`).
- CHECK_DTBS is clean on rk3588s-orangepi-5/-5-sata/-5b. In the extra stack, the only warnings are
  the expected ov13850/ov13855 ones (`checkdtbs-extra.txt`). dt_binding_check is clean on the 12
  changed bindings.
- `checkpatch.txt`: 0 errors and 0 checks on our 67 commits.
- `dtb-diff.txt`: compared with the live board DTB, the only change is dp0 `#sound-dai-cells` 0 -> 1.

Note: `opi5/board-dt` gained 429051f75 and 974695ecb at 18:58, which have the same patch-ids as
main 0266 and extra 0001. If the DP alt-mode DT passes on the board, move
`linux-extra/0001` into the main stack (e.g. as 1005).

Update 2026-10-29 20:17: the DP alt-mode DT passed on the board (USB-C DP dongle, Dell P2415Q and a TCL TV
at 3840x2160@30 over 2-lane pin assignment D; the user saw the picture), so it moved into the main stack as
`1005-arm64-dts-rockchip-Add-USB-C-DP-AltMode-for-Orange-P.patch` (commit 1afa8d268 on
`opi5/integration-7.3`). `linux-extra/` no longer has 0001 (old copy in `patches/linux-extra.bak-20261029/`).
Kernel build 3 (pkg 7.3.0-3) predates this move; its DTB lacks DP, so build 3 is installed with the
1005 DTB built from `opi5/integration-7.3` in build/wt-integration-7.3 until the next build-kernel.sh run.

## 1101-1102: suspend fixes (added 2026-10-29 by the suspend agent)
Range `1101-1102`. Source: branch `opi5/suspend-test-7.3-k3` in `~/orangepi5/work/suspend-test-7.3`, based on
`opi5/integration-7.3` @ 1afa8d268 (= patches/linux 0001-1005), commits d9fc41cb1 and 741e2e2df. Exported with
`git format-patch --zero-commit`.
- `1101-drm-rockchip-dw_dp-Add-system-sleep-PM-ops.patch` (sha256 23dc434e97bf…). Late system-sleep ops
  (pm_runtime_force_suspend/resume) so dw-dp is re-initialised after genpd powers PD_VO0 off in suspend_noirq. It fixes
  "dw-dp: timeout waiting for AUX reply / failed to enable link: -110" after every resume. Follow-up to the
  Collabora dw-dp v11 runtime-PM patch (0255). **Status: untested on hardware with the fix** (bug reproduced in
  S3/S4/S5; DPMS-cycle recovery confirms the cause). Built as a signed rockchipdrm.ko against build 3.
- `1102-cpufreq-Defer-the-unlisted-frequency-check-on-CPU-on.patch` (sha256 43b81035711d…). Skips the "unlisted initial
  frequency" fix-up in cpufreq_online() while cpufreq_suspended and runs it from cpufreq_resume(). It fixes
  "kernel BUG at drivers/cpufreq/cpufreq.c:1527" when a big core is re-onlined during resume (rk8602 on I2C still
  suspended). **Status: build-tested only** (cpufreq.o; vmlinux change, needs a full package).
- Checks: the whole patches/linux stack (294 patches) applies on clean v7.3 with build-kernel.sh's
  `git apply --index` loop. The resulting tree is identical to opi5/suspend-test-7.3-k3 (tree 6e12a1778).
  patches/linux-extra (13) still applies on top. build-kernel.sh not run. checkpatch --strict: only "missing SoB"
  (by design), plus the kept pre-existing BUG_ON warning and long log quotes in 1102's message.
- Details: `~/orangepi5/work/_out/suspend/RESULTS.md`.

Update 2026-10-29 22:30: 0267-0269 added (branch `opi5/dp-smooth-7.3`, `work/_out/dp-smooth/`): USBDP PHY re-enables
the DP lanes after a re-init, dw-dp treats OOB HPD events with the link up as IRQ_HPD and retrains (with retry),
typec displayport notifies HPD after reconfiguration. Hardware-tested: D→C→D pin-assignment switch retrains in
~0.36 s with no black screen (TESTING.md). Overlay: `usr/local/bin/opi5-play` (kmssink skip-vsync=true, hides the
console cursor; see GSTREAMER-FOLLOWUPS for the kmssink double-vblank-wait bug).

Update 2026-10-29 23:30: 1301-1302 added (branch `opi5/vop2-underflow-int-7.3`, `work/_out/vop2-underflow/`):
VOP2 balances window fetches across both AXI read ports on RK3588 (mainline wired all windows to AXI0, ~5 GB/s,
which underflowed at 4K120 + overlay and at 4K60 under DDR load), and reports POST_BUF_EMPTY at most once per
frame (IRQ storm). Hardware-tested: 4K120 + NV12 overlay 0 underflows idle and under 4K decode load; weston
dual-display 10+ min 0; BBB 4K60 0. The board's interim module also contained 1101 (dw_dp sleep).

Update 2026-10-29 23:32: 1201-1202 added (branch `opi5/audio-7.3`, `work/_out/audio/`): DP0 audio card (SPDIF_TX2
→ dw-dp) for RK3588 + Orange Pi 5/5B, and dw-hdmi-qp reprograms audio N/CTS after a link/mode change.
Hardware-tested: HDMI audio audible through 4K60(FRL)→4K120(FRL)→4K60→1080p(TMDS)→4K60 mode changes (user
listened); DP audio verified at signal level only (the Dell has no speakers). Overlay: ALSA UCM profiles
(es8388 headphone defaults, HDMI/DP names), cloud-init default user groups audio/video/render; desktop
WirePlumber priorities in overlay-desktop/. Packages: alsa-utils alsa-ucm-conf gstreamer1.0-alsa.

Update 2026-10-30 05:25: 0270 (phy-rockchip-usbdp keep USB3 on DP entry) moved to patches/linux-hold/ — it fixes the USB3
drop but breaks DP AUX at boot (AUX -110 timeouts, DP-1 down on every boot since it was installed). 0271-0274 (tcpm VDM
discovery fixes) added, not yet board-tested.

## 1501-1504 (USB3 Type-A boot race) — DROPPED 2026-10-30, moved to patches/linux-dropped/
Tested on build 5: the port pairing works and the SuperSpeed retry fires, but the SanDisk stays at 480M after every software reset (usbreset, USB2 suspend/resume, EHCI and dwc3 rebind). The device only tries SuperSpeed when VBUS rises; the board's Type-A VBUS is always on (no GPIO), so it rises before combphy2/xHCI exist. Hot-plug gives 5000M every time. No kernel or DT fix; it would need a switchable VBUS. Details: work/_out/usb3-port/RESULTS.md.
