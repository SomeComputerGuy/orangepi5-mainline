# Status (generated 2026-10-30 by tools/export-from-workspace.sh)

Every kernel topic, the branch it lives on, how far it got, and the next upstream step.
`Ours/Carried/Local` count the patches in each category (see the topic README).
Nothing here has been sent upstream yet.

## Kernel topics (Linux v7.3 unless noted)

| Topic | What | Sits on | Ours / Carried / Local | Tested on hardware (Orange Pi 5) | Next step |
|---|---|---|---|---|---|
| [multicore](topics/multicore/README.md) | RGA3 and rkvdec (VDPU381) multi-core scheduling on v7.3 | `v7.3` | 0 / 21 / 1 | yes: 2x 4K HEVC throughput, bit-exact vs FFmpeg, RGA3 jobs on both cores | track the posted series (RGA multi-core v2, rkvdec multi-core v2); offer Tested-by on the 7.4-rc rebase |
| [board-sata](topics/board-sata/README.md) | Orange Pi 5 M.2 SATA device-tree variant | `multicore` | 1 / 0 / 0 | yes: the test board runs its root file system from an M.2 SATA SSD | send to linux-rockchip (arm64 dts) |
| [suspend](topics/suspend/README.md) | System suspend analysis (TF-A PHP CRU gate fix) | `board-sata` | 0 / 0 / 0 | not run (analysis only; TF-A patch in patches/tf-a) | test deep suspend on the board; send the TF-A fix to TF-A Gerrit |
| [shutdown-hang](topics/shutdown-hang/README.md) | arm-smmu-v3: PCIe SMMU power domain and clock (SATA-root reboot hang) | `board-sata` | 5 / 0 / 0 | yes: reboot hang fixed, reboots take <1 s; in the image kernel (patches/linux/0130-0134) | send bindings + driver + dts as one series (iommu, devicetree, linux-rockchip) |
| [board-hygiene](topics/board-hygiene/README.md) | Board fixes: dwmac-rk delay parsing, i2s-tdm regmap default, rgmii-id, SPI NOR supply, RK806 reset mode | `board-sata` | 5 / 0 / 0 | partly: driver fixes in the image kernel; rgmii-id DT change still needs a board test | test rgmii-id on the board, then send driver fixes (netdev, ASoC) and DT patches separately |
| [gpu-npu](topics/gpu-npu/README.md) | panthor bus clock / suspend clock fix, rocket NPU DVFS + cooling, devfreq resume | `board-sata` | 2 / 12 / 0 | partly: GPU/NPU baseline measured; fixes waiting for a full kernel install | re-test with the full image kernel; send panthor, rocket and devfreq patches to their lists |
| [rkvdec-vp9](topics/rkvdec-vp9/README.md) | VP9 decode on rkvdec VDPU381 (carried series + multi-core port + smaller-frame fix) | `multicore` | 2 / 4 / 0 | yes: fluster VP9 224/305 baseline, matches the series author | offer review/Tested-by on the VP9 series; send the smaller-frame fix after it lands |
| [vp9-conf](topics/vp9-conf/README.md) | VDPU381 VP9 conformance fixes (register reset per frame, segmentation map) | `rkvdec-vp9` | 2 / 0 / 0 | yes: fixed vectors verified on the board | send as fixes on top of the VP9 series |
| [vp9-perf](topics/vp9-perf/README.md) | VDPU381 VP9 performance (count table caching) | `vp9-conf` | 1 / 0 / 0 | yes: measured on the board (see RESULTS.md) | send with vp9-conf once the VP9 series is merged |
| [hantro-validate](topics/hantro-validate/README.md) | Hantro JPEG encoder input validation | `multicore` | 4 / 0 / 0 | see TESTING.md | send to linux-media |
| [hantro-robust](topics/hantro-robust/README.md) | Hantro error recovery (runtime PM, IOMMU re-init after timeout, encoder core reset, resets in DT) | `hantro-validate` | 7 / 0 / 0 | see TESTING.md | send to linux-media + linux-rockchip |
| [hantro-multicore](topics/hantro-multicore/README.md) | Hantro multi-core: the four RK3588 VEPU121 JPEG encoder cores behind one device | `multicore` | 4 / 0 / 0 | yes: drop-in modules on the board, throughput scales across cores | send as RFC to linux-media |
| [hantro-robust-mc](topics/hantro-robust-mc/README.md) | hantro-robust rebased on hantro-multicore | `hantro-multicore` | 6 / 0 / 0 | see hantro-robust/TESTING.md | as hantro-robust |
| [hantro-integrated](topics/hantro-integrated/README.md) | hantro-validate on top of hantro-robust-mc (integration branch) | `hantro-robust-mc` | 4 / 0 / 0 | integration of the above | none (integration only) |
| [vepu121-h264enc](topics/vepu121-h264enc/README.md) | H.264 stateless encode on the RK3588 VPU121 VEPU2 (hantro) on Paul Kocialkowski's H.264 encode uAPI RFC | `hantro-robust-mc` | 5 / 10 / 1 | yes: encodes on the board, decodes cleanly in FFmpeg | depends on the H.264 stateless encode uAPI landing; send as RFC follow-up |
| [rkvenc](topics/rkvenc/README.md) | VEPU580 (rkvenc) V4L2 stateless H.264 encoder driver | `board-sata` | 5 / 7 / 1 | yes: working on the board, both cores in parallel, 0 decode errors | RFC to linux-media after the H.264 encode uAPI; cover letter draft included |
| [rkvenc-hevc](topics/rkvenc-hevc/README.md) | HEVC encoding for the VEPU580 driver (uses hevc-enc-uapi) | `rkvenc` | 9 / 0 / 1 | not yet: compile- and KUnit-tested only | board test, then RFC together with hevc-enc-uapi |
| [hevc-enc-uapi](topics/hevc-enc-uapi/README.md) | Proposed V4L2 HEVC stateless encode uAPI + helpers + KUnit tests | `board-sata` | 9 / 10 / 0 | not applicable (uAPI); KUnit passes | RFC to linux-media; cover letter draft included |
| [jpeg-dec](topics/jpeg-dec/README.md) | New driver: RK3588 VDPU720 JPEG decoder (rkjpegd) | `board-sata` | 3 / 0 / 0 | yes: decodes on the board, PSNR 66-80 dB vs FFmpeg | send v1 to linux-media + devicetree |
| [iep2](topics/iep2/README.md) | New driver: RK3588 IEP2 deinterlacer | `board-sata` | 4 / 0 / 0 | yes: board run 3 passes (runs 1-2 found and fixed an IOMMU fault storm) | send v1 as RFC (new uAPI controls) to linux-media |
| [camera](topics/camera/README.md) | MIPI-CSI camera: rkisp2 v3 series + fixups + Orange Pi 5 CAM1 sensor overlays | `board-sata` | 4 / 5 / 0 | partly: no camera module attached; detection only | test with an IMX219/OV13850 module; report the fixups on the rkisp2 v3 thread |
| [dsi](topics/dsi/README.md) | MIPI DSI LCD: ili9881c Innolux AFJ101-BA2131 panel, dsi2 sentinel fix, LCD overlays | `board-sata` | 4 / 0 / 0 | not yet: no panel attached | the dsi2 sentinel fix can go now; panel + overlays after a panel test |
| [hdmi-frl](topics/hdmi-frl/README.md) | HDMI 2.0 scrambling + HDMI 2.1 FRL on HDMI0 (carried Collabora work) | `board-sata` | 0 / 122 / 0 | see RESULTS.md / TESTING.md | track the Collabora series; report test results on the list |
| [dp-altmode](topics/dp-altmode/README.md) | USB-C DisplayPort alt-mode (USBDP PHY, dwc3 glue, dw-dp series) + Orange Pi 5 DT | `board-sata` | 2 / 65 / 0 | not yet | test on the board; send the Orange Pi 5 DT patch after the dw-dp series lands |
| [board-dt](topics/board-dt/README.md) | Combined board DT used on the test board (DT commits from the topics above) | `board-sata` | 16 / 6 / 0 | yes: the test board boots this DTB | none (integration only) |
| [v7.4-multicore](topics/v7.4-multicore/README.md) | 7.4 base: RGA3 + rkvdec multi-core series as posted (no backport commit) | `c339f4010` | 0 / 21 / 0 | via multicore (v7.3) | rebase onto 7.4-rc1 |
| [v7.4-rkvdec-vp9](topics/v7.4-rkvdec-vp9/README.md) | 7.4 base: VDPU381 VP9 series as posted | `c339f4010` | 0 / 4 / 0 | via rkvdec-vp9 (v7.3) | rebase onto 7.4-rc1 |
| [v7.4-dp-altmode](topics/v7.4-dp-altmode/README.md) | 7.4 base: dw-dp / dwc3 glue series | `c339f4010` | 0 / 28 / 0 | via dp-altmode (v7.3) | rebase onto 7.4-rc1 |
| [v7.4-rkisp2](topics/v7.4-rkisp2/README.md) | 7.4 base: rkisp2 series | `c339f4010` | 2 / 5 / 0 | via camera (v7.3) | rebase onto 7.4-rc1 |
| [v7.4-hdmi-frl](topics/v7.4-hdmi-frl/README.md) | 7.4 base: first HDMI FRL commit | `c339f4010` | 0 / 1 / 0 | via hdmi-frl (v7.3) | rebase onto 7.4-rc1 |
| [integration](topics/integration/README.md) | Integration branch on v7.3: the image-kernel stack before the 2026-10-29 evening fixes (all topics above, rebased; patches/linux is this plus the topics below) | `v7.3` | 58 / 233 / 1 | yes: kernel #3 on the board | none (integration only); provenance in docs/image-kernel/MANIFEST.md |
| [image-k6](topics/image-k6/README.md) | The image-kernel stack: v7.3 + patches/linux (314 patches, after 1501-1504 were dropped), the base for kernel build 6 | `v7.3` | 80 / 233 / 1 | yes: = kernel build 5 on the board minus 1501-1504 | none (integration only); provenance in docs/image-kernel/MANIFEST.md |
| [codec-quality](topics/codec-quality/README.md) | Codec-quality fixes from the codec sweep (VDPU2 VP8 size limit, rkvdec colmv compression + HEVC SPS default, Hantro MPEG-2 field/hold fixes, rkjpegd error frames) | `integration` | 8 / 0 / 0 | yes: decoders bit-exact in the sweep after the fixes; in patches/linux (1401-1408) | send per driver to linux-media |
| [vop2-underflow-int](topics/vop2-underflow-int/README.md) | VOP2: balance window fetches across both AXI ports on RK3588, rate-limit POST_BUF_EMPTY | `integration` | 2 / 0 / 0 | yes: 4K120 + overlay and dual display with 0 underflows; in patches/linux (1301-1302) | send to dri-devel + linux-rockchip |
| [dp-smooth](topics/dp-smooth/README.md) | USB-C DP alt-mode re-train fixes (typec DP HPD notify, dw-dp OOB HPD as IRQ_HPD, usbdp lane re-enable) | `integration` | 3 / 0 / 0 | yes: pin-assignment retrain fixed on the board; in patches/linux | send per subsystem (usb, dri-devel, phy) |
| [usbdp-keep-usb3](topics/usbdp-keep-usb3/README.md) | USBDP PHY: keep USB3 running when DP AltMode (pin D) is entered or left | `dp-smooth` | 1 / 0 / 0 | yes: 0 USB3 disconnects over 6 DP exit/entry transitions with read traffic on the dock, 2 runs; in patches/linux (0270) | send to linux-phy with the Collabora usbdp series (it fixes "Add USB-C state without DP enabled", not in mainline yet) |
| [audio](topics/audio/README.md) | Audio: dw-hdmi-qp N/CTS after a link rate change, DP0 audio for RK3588 / Orange Pi 5 | `integration` | 2 / 0 / 0 | partly: HDMI audible through FRL/TMDS mode changes; DP audio signal-level only; headphone jack not checked by ear | listen test on DP and the jack, then send (dri-devel, linux-rockchip) |
| [suspend-k3](topics/suspend-k3/README.md) | Suspend fixes on the integration stack: cpufreq unlisted-frequency check deferred on resume, dw_dp system sleep ops | `integration` | 2 / 0 / 0 | partly: in patches/linux (1101-1102); s2idle resume hang with a fast console still open (see topics/suspend) | bisect the s2idle hang, then send |
| [rkvdec-hevc-rps](topics/rkvdec-hevc-rps/README.md) | rkvdec HEVC short-term RPS control handling fixes (allocation failure, rebuild, request controls, bounds) | `integration` | 6 / 0 / 0 | see notes/TESTING.md | send to linux-media |
| [rkvdec-ccu-base](topics/rkvdec-ccu-base/README.md) | Base for rkvdec-ccu: the three codec-quality rkvdec commits | `integration` | 3 / 0 / 0 | via codec-quality | none (base only) |
| [rkvdec-ccu](topics/rkvdec-ccu/README.md) | IN PROGRESS, NOT IN THE IMAGE: rkvdec decodes one stream on both RK3588 cores through the CCU, including VP9 (hardware probability adaptation) and field/MBAFF H.264 (field pairs on both cores); on the image-k6 stack, planned as patches/linux 1601-1614 | `image-k6` | 14 / 0 / 0 | in progress: earlier build HEVC 4K 130->228 fps and H.264 4K 67.6->121.4 fps bit-exact; this series (reset-all-cores-once-idle, VP9/field on the CCU) awaits board validation (ccu-repro, fluster, ccu-verify) | finish the board tests and fluster, then RFC to linux-media |
| [tcpm](topics/tcpm/README.md) | USB Type-C tcpm: DP alt-mode discovery fixes (right SVID when resuming Discover Modes, Not_Supported only as a reply to an outstanding VDM, retry discovery after a VDM response timeout, don't NAK unexpected responses) | `integration` | 7 / 0 / 0 | yes: 100/100 dock attach cycles reach DP configured on kernel 5, 0 VDM timeouts; injected late-response stock-vs-fixed comparison in progress; in patches/linux (0271-0274) | send to linux-usb |
| [dw-dp-redetect](topics/dw-dp-redetect/README.md) | PARKED, NOT IN THE IMAGE: dw-dp re-detect after a missed HPD (patch 0275) | `dp-smooth` | 1 / 0 / 0 | not needed: the USBDP re-init (0270 v2) fixed the boot-time AUX -110 it targeted | none (parked) |
| [usb3-port](topics/usb3-port/README.md) | DROPPED, NOT IN THE IMAGE: pair the Type-A USB3 port's EHCI and xHCI ports through a usb-a-connector node and retry SuperSpeed for a device stuck at 480M (was patches/linux 1501-1504) | `image-k6` | 4 / 0 / 0 | does not help: the SanDisk Ultra Fit only tries SuperSpeed when VBUS rises, and this port's VBUS is always on; a SanDisk Extreme comes up at 5000M at boot on the same port, so it is device-specific | none (dropped; kept for reference in patches/linux-dropped) |

## Image kernel

`patches/linux/` is what `scripts/build-kernel.sh` applies on v7.3 for the image (recreated as fork branch `opi5/image-7.3`). It is a snapshot of the topics that were ready for the image; the topic directories are the reference for upstreaming. Range-by-range provenance and test state: [docs/image-kernel/MANIFEST.md](docs/image-kernel/MANIFEST.md).

Patches in patches/linux: 314; other patch directories: ffmpeg, gst-plugins-good, gstreamer, linux-dropped, linux-extra, linux-hold, mpv, tf-a, u-boot, upstream, weston.

## U-Boot and TF-A

| Patch | Where | Tested | Next step |
|---|---|---|---|
| ata: dwc_ahci: Look up the PHY on sata-port subnodes too | patches/upstream/u-boot | yes (boots from M.2 SATA) | send (scripts/send-uboot-patches.sh) |
| RFC rockchip: rk3588: Raise the Cortex-A76 cluster clocks to 1.2 GHz | patches/upstream/u-boot | yes (boot time 100 s -> normal) | send as RFC |
| Board -u-boot.dtsi fragments (SATA, M.2 auto-detect, big-core clocks) | patches/u-boot | yes (in the image) | the cpuclk part is covered by the RFC above |
| fix(rk3588): save and restore the PHP CRU clock gate state | patches/tf-a | not yet (suspend untested) | test suspend, then TF-A Gerrit |

## Not published

- `opi5/vepu580` (and `_out/vepu580*`): port of an out-of-tree, vendor-derived encoder driver by other authors, marked NOT FOR UPSTREAM; superseded by the `rkvenc` topic.
- `opi5/*-debug` branches: fault-injection debugging only.
- `opi5/shutdown-hang-7.3-clk`: same commits as `shutdown-hang`.
- Built modules, DTBs, images, logs larger than 300 KiB, vendor sources and downloads (see docs/SOURCES.md).
