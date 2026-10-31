# integration: Integration branch on v7.3: the image-kernel stack before the 2026-10-29 evening fixes (all topics above, rebased; patches/linux is this plus the topics below)

- Workspace branch: `opi5/integration-7.3` (exported 2026-10-31)
- Kernel fork branch: `opi5/integration` (see PUBLISH.md)
- Sits on: `v7.3` (base commit `c03c1a14507d`)
- Hardware test: yes: kernel #3 on the board
- Next upstream step: none (integration only); provenance in docs/image-kernel/MANIFEST.md
- Patches: 292 = 58 ours, 233 carried from others, 1 local-only

Apply with `git am` in the order listed in [`series`](series), on top of the parent topic (or check out the fork branch). Patch numbers are the position in that order.

## (a) Ours, intended for upstream (`ours/`)

| # | Subject | Author | Link |
|---|---|---|---|
| 0001 | arm64: dts: rockchip: add Orange Pi 5 M.2 SATA variant | Arun Iyengar |  |
| 0024 | dt-bindings: iommu: arm,smmu-v3: allow a power domain | Arun Iyengar |  |
| 0025 | arm64: dts: rockchip: add the PCIe power domain to the RK3588 PCIe SMMU | Arun Iyengar |  |
| 0026 | dt-bindings: iommu: arm,smmu-v3: allow clocks | Arun Iyengar |  |
| 0027 | iommu/arm-smmu-v3: enable optional clocks | Arun Iyengar |  |
| 0028 | arm64: dts: rockchip: add the clock of the RK3588 PCIe SMMU | Arun Iyengar |  |
| 0215 | net: stmmac: dwmac-rk: only read the delays the MAC applies | Arun Iyengar |  |
| 0216 | ASoC: rockchip: i2s-tdm: add the reset value of XFER to the regmap defaults | Arun Iyengar |  |
| 0228 | drm/panthor: Do not change the GPU clock rate while suspended | Arun Iyengar | [link](https://github.com/armbian/linux-rockchip/pull/380) |
| 0230 | PM / devfreq: Resume at the frequency from before suspend | Arun Iyengar |  |
| 0235 | media: rkvdec: vdpu381-vp9: adapt to the multi-core core/master split | Arun Iyengar |  |
| 0236 | media: rkvdec: vdpu381-vp9: allow frames smaller than the CAPTURE format | Arun Iyengar |  |
| 0237 | media: rkvdec: vdpu381-vp9: reset the register set for every frame | Arun Iyengar |  |
| 0238 | media: rkvdec: vdpu381-vp9: fix segmentation map handling | Arun Iyengar |  |
| 0239 | media: rkvdec: vdpu381-vp9: keep the count table cacheable | Arun Iyengar |  |
| 0240 | media: verisilicon: Split probe into hardware init and device registration | Arun Iyengar |  |
| 0241 | media: verisilicon: Pick the hardware core for each job | Arun Iyengar |  |
| 0242 | media: verisilicon: Add multi-core support | Arun Iyengar |  |
| 0243 | media: verisilicon: Don't hold a VPU behind an IOMMU in reset after remove | Arun Iyengar |  |
| 0244 | media: verisilicon: Drop the runtime PM reference when clocks fail to enable | Arun Iyengar |  |
| 0245 | media: verisilicon: Make the codec run error handling consistent | Arun Iyengar |  |
| 0246 | media: verisilicon: Reset the Rockchip encoder cores on timeout | Arun Iyengar |  |
| 0247 | media: verisilicon: Reinitialize the IOMMU after a timeout | Arun Iyengar |  |
| 0248 | dt-bindings: media: rockchip,rk3568-vepu: Add the reset lines | Arun Iyengar |  |
| 0249 | arm64: dts: rockchip: Add the reset lines of the RK3588 VEPU121 cores | Arun Iyengar |  |
| 0250 | media: verisilicon: Enforce a minimum CAPTURE sizeimage for the encoder | Arun Iyengar |  |
| 0251 | media: verisilicon: Keep the encoder coded size in sync with OUTPUT | Arun Iyengar |  |
| 0252 | media: verisilicon: Refuse JPEG encode jobs with inconsistent geometry | Arun Iyengar |  |
| 0253 | media: verisilicon: Report fixed JPEG colorimetry on the encoder | Arun Iyengar |  |
| 0261 | media: h264: Only write the SPS and PPS of a stateless encode when they change | Arun Iyengar |  |
| 0262 | media: h264: Support picture order count type 2 in stateless encode | Arun Iyengar |  |
| 0263 | media: hevc: Add H.265 syntax definitions | Arun Iyengar |  |
| 0264 | media: uapi: Add HEVC stateless encode support | Arun Iyengar |  |
| 0265 | media: hevc: Add stateless encode RBSP writer | Arun Iyengar |  |
| 0266 | media: hevc: Add KUnit tests for the stateless encode RBSP writer | Arun Iyengar |  |
| 0267 | media: hevc: Add stateless encode core | Arun Iyengar |  |
| 0268 | media: hevc: Add KUnit tests for the stateless encode core | Arun Iyengar |  |
| 0269 | media: docs: Document the HEVC stateless encode uAPI | Arun Iyengar |  |
| 0273 | media: verisilicon: Share the H.264 CABAC context initialization table | Arun Iyengar |  |
| 0274 | media: verisilicon: Add H.264 encoding to the Rockchip VEPU2 of the RK3588 | Arun Iyengar |  |
| 0275 | arm64: dts: rockchip: Add the encoder interrupt of the RK3588 VPU121 | Arun Iyengar |  |
| 0276 | dt-bindings: media: Add the Rockchip VEPU580 video encoder | Arun Iyengar |  |
| 0277 | media: rockchip: Add a VEPU580 stateless video encoder driver | Arun Iyengar |  |
| 0278 | arm64: dts: rockchip: Add the VEPU580 encoder cores to the RK3588 | Arun Iyengar |  |
| 0279 | media: rockchip: rkvenc: Prepare the VEPU580 helpers for a second codec | Arun Iyengar |  |
| 0280 | media: rockchip: rkvenc: Add HEVC encoding | Arun Iyengar |  |
| 0281 | dt-bindings: media: Add Rockchip VDPU720 JPEG decoder | Arun Iyengar |  |
| 0282 | media: rockchip: Add VDPU720 JPEG decoder driver | Arun Iyengar |  |
| 0283 | arm64: dts: rockchip: Add the JPEG decoder to rk3588-base | Arun Iyengar |  |
| 0284 | media: uapi: add Rockchip IEP deinterlacer controls | Arun Iyengar |  |
| 0285 | dt-bindings: media: add Rockchip IEP2 deinterlacer | Arun Iyengar |  |
| 0286 | media: rockchip: add IEP2 deinterlacer driver | Arun Iyengar |  |
| 0287 | arm64: dts: rockchip: add IEP2 deinterlacer to RK3588 | Arun Iyengar |  |
| 0288 | arm64: dts: rockchip: use rgmii-id for the Orange Pi 5/5B ethernet PHY | Arun Iyengar |  |
| 0289 | arm64: dts: rockchip: add the SPI NOR flash supply on Orange Pi 5 | Arun Iyengar |  |
| 0290 | arm64: dts: rockchip: set the RK806 reset mode on Orange Pi 5 boards | Arun Iyengar |  |
| 0291 | arm64: dts: rockchip: build the Orange Pi 5 and 5B DTBs with symbols | Arun Iyengar |  |
| 0292 | arm64: dts: rockchip: Add USB-C DP AltMode for Orange Pi 5/5B | Arun Iyengar | [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/7983809d4d2c5a6c39d936ed3140e378a3257ebd) [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/c2d2e2b10a55c4d740a2faf1526a70c4f19da047) |

## (b) Carried from others, authorship kept (`carried/`)

| # | Subject | Author | Link |
|---|---|---|---|
| 0003 | media: rockchip: rga: zero cmdbuf in shared code | Sven Püschel |  |
| 0004 | media: rockchip: rga: add comment about pixel alignment for YUV formats | Sven Püschel |  |
| 0005 | media: rockchip: rga: move early return into if condition in vidioc_enum_fmt | Sven Püschel |  |
| 0006 | media: rockchip: rga: removed unused regmap member | Sven Püschel |  |
| 0007 | media: rockchip: rga: use devres version of pm_runtime_enable | Sven Püschel |  |
| 0008 | media: v4l2-mem2mem: drop curr_ctx member from v4l2_m2m_dev struct | Sven Püschel |  |
| 0009 | media: v4l2-mem2mem: support running multiple jobs in parallel | Sven Püschel |  |
| 0010 | media: rockchip: rga: move power handling to device_run | Sven Püschel |  |
| 0011 | media: rockchip: rga: adjust get_version to return the version | Sven Püschel |  |
| 0012 | media: rockchip: rga: add rga_core structure | Sven Püschel |  |
| 0013 | media: rockchip: rga: use components to manage multiple cores | Sven Püschel |  |
| 0014 | media: rockchip: rga: move rockchip_rga allocation to master probe | Sven Püschel |  |
| 0015 | media: rockchip: rga: move core initialization from bind to probe | Sven Püschel |  |
| 0016 | media: rockchip: rga: move video device to the master | Sven Püschel |  |
| 0017 | media: rockchip: rga: bind all cores to the master | Sven Püschel |  |
| 0018 | media: rockchip: rga: put all cores into first core iommu domain | Sven Püschel |  |
| 0019 | media: rockchip: rga: schedule jobs to multiple cores | Sven Püschel |  |
| 0020 | media: rkvdec: Keep RCB to the correct size | Detlev Casanova |  |
| 0021 | media: rkvdec: Remove unused need_reset | Detlev Casanova |  |
| 0022 | media: rkvdec: Split into core and master platform drivers | Detlev Casanova |  |
| 0023 | media: rkvdec: Add multicore support | Detlev Casanova |  |
| 0029 | dt-bindings: phy: rockchip-usbdp: add improved ports scheme | Sebastian Reichel | [link](https://patch.msgid.link/20260915-rockchip-usbdp-cleanup-v15-1-80e2c11d1ce8@collabora.com) |
| 0030 | phy: rockchip: usbdp: Update mode_change after error handling | Sebastian Reichel | [link](https://lore.kernel.org/linux-phy/20260612163835.8D5471F000E9@smtp.kernel.org/) [link](https://patch.msgid.link/20260915-rockchip-usbdp-cleanup-v15-2-80e2c11d1ce8@collabora.com) |
| 0031 | phy: rockchip: usbdp: Do not lose USB3 PHY status | Sebastian Reichel | [link](https://patch.msgid.link/20260915-rockchip-usbdp-cleanup-v15-3-80e2c11d1ce8@collabora.com) |
| 0032 | phy: rockchip: usbdp: Fix devm_clk_bulk_get_all check | Sebastian Reichel | [link](https://lore.kernel.org/linux-phy/20260612164107.C7DB21F000E9@smtp.kernel.org/) [link](https://patch.msgid.link/20260915-rockchip-usbdp-cleanup-v15-4-80e2c11d1ce8@collabora.com) |
| 0033 | phy: rockchip: usbdp: Handle missing clock-names DT property gracefully | Sebastian Reichel | [link](https://patch.msgid.link/20260915-rockchip-usbdp-cleanup-v15-5-80e2c11d1ce8@collabora.com) |
| 0034 | phy: rockchip: usbdp: Drop seamless DP takeover | Sebastian Reichel | [link](https://patch.msgid.link/20260915-rockchip-usbdp-cleanup-v15-6-80e2c11d1ce8@collabora.com) |
| 0035 | phy: rockchip: usbdp: Keep clocks running on PHY re-init | Sebastian Reichel | [link](https://patch.msgid.link/20260915-rockchip-usbdp-cleanup-v15-7-80e2c11d1ce8@collabora.com) |
| 0036 | phy: rockchip: usbdp: Amend SSC modulation deviation | Frank Wang | [link](https://patch.msgid.link/20260915-rockchip-usbdp-cleanup-v15-8-80e2c11d1ce8@collabora.com) |
| 0037 | phy: rockchip: usbdp: Fix LFPS detect threshold control | William Wu | [link](https://patch.msgid.link/20260915-rockchip-usbdp-cleanup-v15-9-80e2c11d1ce8@collabora.com) |
| 0038 | phy: rockchip: usbdp: Add missing mode_change update | Sebastian Reichel | [link](https://patch.msgid.link/20260915-rockchip-usbdp-cleanup-v15-10-80e2c11d1ce8@collabora.com) |
| 0039 | phy: rockchip: usbdp: Support single-lane DP | Zhang Yubing | [link](https://patch.msgid.link/20260915-rockchip-usbdp-cleanup-v15-11-80e2c11d1ce8@collabora.com) |
| 0040 | phy: rockchip: usbdp: Limit DP lane count to muxed lanes | Sebastian Reichel | [link](https://lore.kernel.org/linux-phy/20260612165546.98E1F1F000E9@smtp.kernel.org/) [link](https://patch.msgid.link/20260915-rockchip-usbdp-cleanup-v15-12-80e2c11d1ce8@collabora.com) |
| 0041 | phy: rockchip: usbdp: Rename DP lane functions | Sebastian Reichel | [link](https://patch.msgid.link/20260915-rockchip-usbdp-cleanup-v15-13-80e2c11d1ce8@collabora.com) |
| 0042 | phy: rockchip: usbdp: Use FIELD_PREP_WM16_CONST | Sebastian Reichel | [link](https://patch.msgid.link/20260915-rockchip-usbdp-cleanup-v15-14-80e2c11d1ce8@collabora.com) |
| 0043 | phy: rockchip: usbdp: Cleanup DP lane selection function | Sebastian Reichel | [link](https://patch.msgid.link/20260915-rockchip-usbdp-cleanup-v15-15-80e2c11d1ce8@collabora.com) |
| 0044 | phy: rockchip: usbdp: Register DP aux bridge | Sebastian Reichel | [link](https://patch.msgid.link/20260915-rockchip-usbdp-cleanup-v15-16-80e2c11d1ce8@collabora.com) |
| 0045 | phy: rockchip: usbdp: Drop DP HPD handling | Sebastian Reichel | [link](https://patch.msgid.link/20260915-rockchip-usbdp-cleanup-part2-v15-1-8d507cb1174f@collabora.com) |
| 0046 | phy: rockchip: usbdp: Rename mode_change to phy_needs_reinit | Sebastian Reichel | [link](https://patch.msgid.link/20260915-rockchip-usbdp-cleanup-part2-v15-2-8d507cb1174f@collabora.com) |
| 0047 | phy: rockchip: usbdp: Re-init the PHY on orientation change | Sebastian Reichel | [link](https://patch.msgid.link/20260915-rockchip-usbdp-cleanup-part2-v15-3-8d507cb1174f@collabora.com) |
| 0048 | phy: rockchip: usbdp: Factor out lane_mux_sel setup | Sebastian Reichel | [link](https://patch.msgid.link/20260915-rockchip-usbdp-cleanup-part2-v15-4-8d507cb1174f@collabora.com) |
| 0049 | phy: rockchip: usbdp: Properly handle TYPEC_STATE_SAFE and TYPEC_STATE_USB | Sebastian Reichel | [link](https://patch.msgid.link/20260915-rockchip-usbdp-cleanup-part2-v15-5-8d507cb1174f@collabora.com) |
| 0050 | phy: rockchip: usbdp: Use guard functions for mutex | Sebastian Reichel | [link](https://patch.msgid.link/20260915-rockchip-usbdp-cleanup-part2-v15-6-8d507cb1174f@collabora.com) |
| 0051 | phy: rockchip: usbdp: Hold mutex in DP PHY configure | Sebastian Reichel | [link](https://patch.msgid.link/20260915-rockchip-usbdp-cleanup-part2-v15-7-8d507cb1174f@collabora.com) |
| 0052 | phy: rockchip: usbdp: Add some extra debug messages | Sebastian Reichel | [link](https://patch.msgid.link/20260915-rockchip-usbdp-cleanup-part2-v15-8-8d507cb1174f@collabora.com) |
| 0053 | phy: rockchip: usbdp: Avoid xHCI SErrors | Sebastian Reichel | [link](https://patch.msgid.link/20260915-rockchip-usbdp-cleanup-part2-v15-9-8d507cb1174f@collabora.com) |
| 0054 | phy: rockchip: usbdp: Handle rk_udphy_reset_deassert errors | Sebastian Reichel | [link](https://patch.msgid.link/20260915-rockchip-usbdp-cleanup-part2-v15-10-8d507cb1174f@collabora.com) |
| 0055 | phy: rockchip: usbdp: Only enable USB3 when not in high-speed mode | Sebastian Reichel | [link](https://patch.msgid.link/20260915-rockchip-usbdp-cleanup-part2-v15-11-8d507cb1174f@collabora.com) |
| 0056 | phy: rockchip: usbdp: Track PHY power state | Sebastian Reichel | [link](https://patch.msgid.link/20261021-b4-rockchip-dwc3-rockchip-glue-v18-1-60000d03fca2@collabora.com) |
| 0057 | phy: rockchip: usbdp: Add reset hook support for dwc3 | Sebastian Reichel | [link](https://patch.msgid.link/20261021-b4-rockchip-dwc3-rockchip-glue-v18-2-60000d03fca2@collabora.com) |
| 0058 | usb: dwc3: rockchip: introduce glue driver | Sebastian Reichel | [link](https://patch.msgid.link/20261021-b4-rockchip-dwc3-rockchip-glue-v18-3-60000d03fca2@collabora.com) |
| 0059 | usb: dwc3: core: add post PHY registration hook for platform glue | Sebastian Reichel | [link](https://patch.msgid.link/20261021-b4-rockchip-dwc3-rockchip-glue-v18-4-60000d03fca2@collabora.com) |
| 0060 | usb: dwc3: rockchip: add USBDP PHY reset quirk | Sebastian Reichel | [link](https://patch.msgid.link/20261021-b4-rockchip-dwc3-rockchip-glue-v18-5-60000d03fca2@collabora.com) |
| 0061 | usb: gadget: define stub for usb_udc_vbus_handler | Sebastian Reichel | [link](https://patch.msgid.link/20261021-b4-rockchip-dwc3-rockchip-glue-v18-6-60000d03fca2@collabora.com) |
| 0062 | usb: dwc3: rockchip: fix USB-C reconnect in gadget mode | Sebastian Reichel | [link](https://patch.msgid.link/20261021-b4-rockchip-dwc3-rockchip-glue-v18-7-60000d03fca2@collabora.com) |
| 0063 | phy: rockchip: usbdp: Disable USB3 port during normal power-on | Sebastian Reichel | [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/52eef750d7c5ce13ea1d66b1be2d039c6250cb4c) |
| 0064 | phy: rockchip: usbdp: Drop -EPROBE_DEFER hack | Sebastian Reichel | [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/c03e9dd764007ac7a510e1c05a00ac08e07d8b03) |
| 0065 | phy: rockchip: usbdp: Rename mode to hw_mode | Sebastian Reichel | [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/9b2366277462f629452654e1b1d05e17c6a378e8) |
| 0066 | phy: rockchip: usbdp: Fix power state handling | Sebastian Reichel | [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/713114cb94f79a06377636747095ca823b093e62) |
| 0067 | phy: rockchip: usbdp: Re-init PHY on mux change | Sebastian Reichel | [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/2391da40eb39e26b31972ef4a6d7a3d997a1c209) |
| 0068 | phy: rockchip: usbdp: Add USB-C state without DP enabled | Sebastian Reichel | [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/b6c756709db3ae6f85ef8133de754a8e7b7ec894) |
| 0069 | drm/bridge: synopsys: dw-dp: Register DP AUX on bridge attach | Sebastian Reichel | [link](https://patch.msgid.link/20260806-synopsys-dw-dp-improvements-v11-1-0d508505f383@collabora.com) |
| 0070 | drm/bridge: synopsys: dw-dp: Fix incorrect resource lifetimes in bind callback | Sebastian Reichel | [link](https://patch.msgid.link/20260806-synopsys-dw-dp-improvements-v11-2-0d508505f383@collabora.com) |
| 0071 | drm/bridge: synopsys: dw-dp: Fix error handling for DP link enablement | Sebastian Reichel | [link](https://patch.msgid.link/20260806-synopsys-dw-dp-improvements-v11-3-0d508505f383@collabora.com) |
| 0072 | drm/bridge: synopsys: dw-dp: Document missing reset line deassert | Sebastian Reichel | [link](https://patch.msgid.link/20260806-synopsys-dw-dp-improvements-v11-4-0d508505f383@collabora.com) |
| 0073 | drm/bridge: synopsys: dw-dp: Add missing mutex cleanups on module removal | Sebastian Reichel | [link](https://patch.msgid.link/20260806-synopsys-dw-dp-improvements-v11-5-0d508505f383@collabora.com) |
| 0074 | drm/bridge: synopsys: dw-dp: Fix AUX transfer timeout race condition | Sebastian Reichel | [link](https://patch.msgid.link/20260806-synopsys-dw-dp-improvements-v11-6-0d508505f383@collabora.com) |
| 0075 | drm/bridge: synopsys: dw-dp: Fix support for short I2C reads | Sebastian Reichel | [link](https://patch.msgid.link/20260806-synopsys-dw-dp-improvements-v11-7-0d508505f383@collabora.com) |
| 0076 | drm/bridge: synopsys: dw-dp: Free output_fmts when none are valid | Sebastian Reichel | [link](https://patch.msgid.link/20260806-synopsys-dw-dp-improvements-v11-8-0d508505f383@collabora.com) |
| 0077 | drm/bridge: synopsys: dw-dp: Support MEDIA_BUS_FMT_FIXED | Sebastian Reichel | [link](https://patch.msgid.link/20260806-synopsys-dw-dp-improvements-v11-9-0d508505f383@collabora.com) |
| 0078 | drm/bridge: synopsys: dw-dp: Add follow-up bridge support | Sebastian Reichel | [link](https://patch.msgid.link/20260806-synopsys-dw-dp-improvements-v11-10-0d508505f383@collabora.com) |
| 0079 | drm/bridge: Add out-of-band HPD notify handler | Sebastian Reichel | [link](https://patch.msgid.link/20260806-synopsys-dw-dp-improvements-v11-11-0d508505f383@collabora.com) |
| 0080 | drm/bridge: synopsys: dw-dp: Support software triggered OOB HPD | Sebastian Reichel | [link](https://patch.msgid.link/20260806-synopsys-dw-dp-improvements-v11-12-0d508505f383@collabora.com) |
| 0081 | drm/rockchip: dw_dp: Implement out-of-band HPD handling | Sebastian Reichel | [link](https://patch.msgid.link/20260806-synopsys-dw-dp-improvements-v11-13-0d508505f383@collabora.com) |
| 0082 | drm/bridge: synopsys: dw-dp: Add Runtime PM support | Sebastian Reichel | [link](https://patch.msgid.link/20260806-synopsys-dw-dp-improvements-v11-14-0d508505f383@collabora.com) |
| 0083 | drm/rockchip: dw_dp: Add runtime PM support | Sebastian Reichel | [link](https://patch.msgid.link/20260806-synopsys-dw-dp-improvements-v11-15-0d508505f383@collabora.com) |
| 0084 | drm/bridge: synopsys: dw-dp: Protect sdp_reg_bank from concurrent access | Sebastian Reichel | [link](https://patch.msgid.link/20260806-synopsys-dw-dp-improvements-v11-16-0d508505f383@collabora.com) |
| 0085 | drm/bridge: synopsys: dw-dp: Drop useless reservation of first slot | Sebastian Reichel | [link](https://patch.msgid.link/20260806-synopsys-dw-dp-improvements-v11-17-0d508505f383@collabora.com) |
| 0086 | drm/bridge: synopsys: dw-dp: Clear only enabled SDPs on atomic disable | Sebastian Reichel | [link](https://patch.msgid.link/20260806-synopsys-dw-dp-improvements-v11-18-0d508505f383@collabora.com) |
| 0087 | drm/bridge: synopsys: dw-dp: Use regmap_set_bits in dw_dp_send_sdp | Sebastian Reichel | [link](https://patch.msgid.link/20260806-synopsys-dw-dp-improvements-v11-19-0d508505f383@collabora.com) |
| 0088 | dt-bindings: display: rockchip: dw-dp: Fix sound DAI cells | Sebastian Reichel | [link](https://patch.msgid.link/20260806-synopsys-dw-dp-improvements-v11-20-0d508505f383@collabora.com) |
| 0089 | drm/bridge: synopsys: dw-dp: Add audio support | Sebastian Reichel | [link](https://patch.msgid.link/20260806-synopsys-dw-dp-improvements-v11-21-0d508505f383@collabora.com) |
| 0090 | usb: typec: mux: initialize orientation switch array | Haobo Cheng | [link](https://patch.msgid.link/20260804083434.20885-1-i@4t.pw) |
| 0091 | usb: typec: mux: initialize mux switch array | Sebastian Reichel | [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/9e1bfcaf758d271d7aa57a056351e065dc5d9a8c) |
| 0092 | drm/connector: Cache out-of-band hotplug events | Sebastian Reichel | [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/9b8b3adadabe758cf1848df72dce497d2a37d99f) |
| 0093 | arm64: dts: rockchip: Fix DP sound-dai-cells on RK3588 | Sebastian Reichel | [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/d2872441c3d55c2cbb9c0449a6c90e22babadb8d) |
| 0094 | phy: hdmi: Add optional FRL TxFFE config options | Cristian Ciocaltea | [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/06663d430f3bf6a94d14c2c0bc79de54ed093bb3) |
| 0095 | phy: rockchip: samsung-hdptx: Add support for FRL TxFFE level control | Cristian Ciocaltea | [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/27850b668fc578f619a397dcf9e9331a170ea5c0) |
| 0096 | phy: rockchip: samsung-hdptx: Handle PHY config after module reload | Cristian Ciocaltea | [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/91f7054a1778679b2ba9558615f4d36ddee3f06f) |
| 0097 | drm/scdc-helper: Don't use ssize_t return type for scdc_read/write | Nicolas Frattaroli | [link](https://patch.msgid.link/20260724-scdc-link-health-v9-1-bdda406d016d@collabora.com) [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/a727af96f7a5bfacc60aadee0083bb4960b2cbf7) |
| 0098 | drm/scdc-helper: Add scdc_status debugfs entry | Nicolas Frattaroli | [link](https://patch.msgid.link/20260724-scdc-link-health-v9-2-bdda406d016d@collabora.com) [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/625d28e0157101259049675b895531dac0c498fc) |
| 0099 | drm/scdc-helper: Implement parsing and printing HDMI 2.1 fields | Nicolas Frattaroli | [link](https://patch.msgid.link/20260724-scdc-link-health-v9-3-bdda406d016d@collabora.com) [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/265394e3a77127c5dc5615fc819dc24ce2a0b653) |
| 0100 | drm/debugfs: Move HDMI debugfs registration to state helper | Nicolas Frattaroli | [link](https://patch.msgid.link/20260724-scdc-link-health-v9-4-bdda406d016d@collabora.com) [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/a7edb7db6ba9440b635b207362fe11baaeb46980) |
| 0101 | drm/display: hdmi-state-helper: Init SCDC debugfs for HDMI | Nicolas Frattaroli | [link](https://patch.msgid.link/20260724-scdc-link-health-v9-5-bdda406d016d@collabora.com) [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/8b993feebf391df1da16b7d32e03dc0fa8094ee3) |
| 0102 | drm/bridge: dw-hdmi-qp: use drm_hdmi_acr_get_n_cts() helper for audio N/CTS | Simon Wright | [link](https://patch.msgid.link/86fcf349-0a7a-4618-9001-612371b0f71b@symple.nz) [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/4c1f89e7a6937bdd7c7014161fa17dfcd8c3a411) |
| 0103 | video/hdmi: Introduce HDMI version enum | Cristian Ciocaltea | [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/b22e0b759f50b8926c4a3243a4355fe7a6d0ad0d) |
| 0104 | drm/connector: hdmi: Handle reset() state allocation failure | Cristian Ciocaltea | [link](https://lore.kernel.org/all/20260723015306.C94241F000E9@smtp.kernel.org/) [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/91ba741e979a32a9288a732f8e3c3a4695247088) |
| 0105 | drm/display: hdmi: Rename drmm_connector_hdmi_init() to *_ini2() | Cristian Ciocaltea | [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/df62d2c64f00d48036c2fc545814f343ccd5a0cd) |
| 0106 | drm/connector: Add drmm_connector_hdmi_init() with new signature | Cristian Ciocaltea | [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/7f4afba529acbb28edf809c8ff8738fab46366f7) |
| 0107 | drm/display: bridge_connector: Convert to drmm_connector_hdmi_init() | Cristian Ciocaltea | [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/9bfcdac421ca94c9a29dc4b8d79f3578a9aae0a9) |
| 0108 | drm/probe-helper: Introduce .force_ctx() connector callback | Cristian Ciocaltea | [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/d5c04506a354dac99d01af3d35c1509fd2a62de1) |
| 0109 | drm/connector: Add HDMI 2.0 scrambler infrastructure | Cristian Ciocaltea | [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/e40a1569539f72b0028e1eb0d95f65bc516bf59e) |
| 0110 | drm/display: scdc-helper: Add macro for connector-prefixed debug messages | Cristian Ciocaltea | [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/bb5233641529898b91377e9311fa746cd19ffa5a) |
| 0111 | drm/display: scdc-helper: Add helper to set SCDC version information | Cristian Ciocaltea | [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/360e7be51d95ad6f963552788f24538377483941) |
| 0112 | drm/display: hdmi: Add HDMI 2.0 scrambling management helpers | Cristian Ciocaltea | [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/79da1468061f1e5dd88782ea2e78d7681223cd48) |
| 0113 | drm/display: hdmi: Advertise SCDC source version when scrambling | Cristian Ciocaltea | [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/c1c7f240a55b657c5dfb9c6402641b1a478a52ea) |
| 0114 | drm/bridge: Fix NULL deref in drm_bridge_add() for legacy bridges | Cristian Ciocaltea | [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/22b9dcba830a9421b4e70325ef1f0c44a6f438e0) |
| 0115 | drm/bridge: Remove redundant error check in drm_bridge_helper_reset_crtc() | Cristian Ciocaltea | [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/0c900905e777d7d777af11c6ab9cb3125205eb56) |
| 0116 | drm/bridge: Add bridge ops for source-side HDMI 2.0 scrambling | Cristian Ciocaltea | [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/3b56158b0513d4bb68d54383cff8ae88d36f404c) |
| 0117 | drm/display: bridge_connector: Use cached connector status in .get_modes() | Cristian Ciocaltea | [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/803a5e5e8ed3fe5084cf72cefd46aa23ba281e3c) |
| 0118 | drm/display: bridge_connector: Switch to .detect_ctx() connector helper | Cristian Ciocaltea | [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/5e7302a0de5f247ec4fd24bcd28081223ae7a986) |
| 0119 | drm/display: bridge_connector: Wire up HDMI 2.0 scrambler callbacks | Cristian Ciocaltea | [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/7ba1d27b84866bd2b698a5d2bbeed90c66c07b7b) |
| 0120 | drm/display: hdmi-state-helper: Add source TMDS rate validation | Cristian Ciocaltea | [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/fb92aeaa9964d1ba67fb746a52e4f00e59b6ae02) |
| 0121 | drm/display: hdmi-state-helper: Pass acquire ctx to hotplug helpers | Cristian Ciocaltea | [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/45aaa809b1086cee60cafad31e964096ac6e6cba) |
| 0122 | drm/display: hdmi-state-helper: Add drm_atomic_helper_connector_hdmi_force_ctx() | Cristian Ciocaltea | [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/42547e9ad941535b8e4ed5e18946ac7e909bded8) |
| 0123 | drm/display: hdmi-state-helper: Sync SCDC state on hotplug | Cristian Ciocaltea | [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/444e653a7ec9e255477fc6a531245ae3f1a61479) |
| 0124 | drm/display: hdmi-state-helper: Set HDMI scrambling requirement | Cristian Ciocaltea | [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/1bb7d4d2918b7154a3fe55c81f73199895e95e3a) |
| 0125 | drm/display: bridge_connector: Switch to .force_ctx() connector helper | Cristian Ciocaltea | [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/3f744776da637de87cfeff563e980baef7265b2d) |
| 0126 | drm/bridge: dw-hdmi-qp: Rate limit i2c read error messages | Cristian Ciocaltea | [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/84b45a5712b5d49b301518f77f133571004dc348) |
| 0127 | drm/bridge: dw-hdmi-qp: Provide .{enable,disable}_hpd() PHY ops | Cristian Ciocaltea | [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/043a32bd6e65b096fa40bad6a157661cbd4b2d33) |
| 0128 | drm/bridge: dw-hdmi-qp: Remove unused workqueue include and define | Cristian Ciocaltea | [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/e94b288566a4ee5ed9a43f05291c11c372737c84) |
| 0129 | drm/bridge: dw-hdmi-qp: Add HDMI 2.0 scrambling support | Cristian Ciocaltea | [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/1d486f3f0e4d52bd3247f11b7246729fef5852c1) |
| 0130 | drm/bridge: dw-hdmi-qp: Provide dw_hdmi_qp_hpd_notify() helper | Cristian Ciocaltea | [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/bcfadf6bc367db93a59d414d52b453a848fdf2a9) |
| 0131 | drm/rockchip: dw_hdmi_qp: Fix invalid drvdata access in PM ops | Cristian Ciocaltea | [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/d06954089ab56febd72452325944938c7739052a) |
| 0132 | drm/rockchip: dw_hdmi_qp: Cancel pending HPD work on suspend | Cristian Ciocaltea | [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/828b40601500c1da781bc676fa48786d99ea75ce) |
| 0133 | drm/rockchip: dw_hdmi_qp: Add missing newlines in dev_err_probe() messages | Cristian Ciocaltea | [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/bfbc1d5671da2f326dab58c082d4101beae1af92) |
| 0134 | drm/rockchip: dw_hdmi_qp: Use local dev variable consistently in bind() | Cristian Ciocaltea | [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/e10b95cb027c516fc3f85d344459949337a09fa2) |
| 0135 | drm/rockchip: dw_hdmi_qp: Avoid spurious HPD IRQ thread wakeups | Cristian Ciocaltea | [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/76f27a4af786e2503cee1b404b3a098e2b20786e) |
| 0136 | drm/rockchip: dw_hdmi_qp: Mask RK3576 HPD IRQ in io_init | Cristian Ciocaltea | [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/45dc010e98b099070029030f96dd37bcb1a772b3) |
| 0137 | drm/rockchip: dw_hdmi_qp: Implement .{enable,disable}_hpd() PHY ops | Cristian Ciocaltea | [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/d8c195eb7b4ab2e44e298a7584ac5f48f45382e6) |
| 0138 | drm/rockchip: dw_hdmi_qp: Factor out HPD interrupt (un)mask helpers | Cristian Ciocaltea | [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/6bcce525308f1c6515a9532d64f4cde0bcb51ef3) |
| 0139 | drm/rockchip: dw_hdmi_qp: Control the HPD IRQ line via the bridge HPD ops | Cristian Ciocaltea | [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/c07d2503090bdd141b3a62a2889b58791e541169) |
| 0140 | drm/rockchip: dw_hdmi_qp: Use dw_hdmi_qp_hpd_notify() for HPD reports | Cristian Ciocaltea | [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/7ebb0ef866dc2ef9d8ab3d3a0dd1a742509b375b) |
| 0141 | drm/bridge: dw-hdmi-qp: Drop unused .setup_hpd() phy op | Cristian Ciocaltea | [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/ed28670e0caa819c41bdb0ac522573bae9e069e1) |
| 0142 | drm/vc4: hdmi: Use common TMDS char rate constants | Cristian Ciocaltea | [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/cfd43d41a002ae1bf19cf402b130b6219b5db2ef) |
| 0143 | drm/vc4: hdmi: Switch to drm_hdmi_mode_needs_scrambling() | Cristian Ciocaltea | [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/67328729efc4f090a24258eed558073a0574a9c2) |
| 0144 | drm/vc4: hdmi: Switch to .force_ctx() connector helper | Cristian Ciocaltea | [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/6b6ee9c206b4f1dbb782fddff08cf0db90761c58) |
| 0145 | drm/vc4: hdmi: Propagate -EDEADLK to the top level | Cristian Ciocaltea | [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/2fc74ba693b13b3ae00ffed5b31d33a757295596) |
| 0146 | drm/vc4: hdmi: Convert to drmm_connector_hdmi_init() | Cristian Ciocaltea | [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/8ac2dbc8332610fc02801214b45a77610ea13b29) |
| 0147 | drm/vc4: hdmi: Convert to common HDMI 2.0 scrambling infrastructure | Cristian Ciocaltea | [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/90acd0784d40b6c1e2b603d26d0e7a63a6655241) |
| 0148 | drm/vc4: hdmi: Defer pixel clock validation to HDMI helpers | Cristian Ciocaltea | [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/0d58d1a04e0e89c50f6efc63aa9f44e59d01db8b) |
| 0149 | drm/display: hdmi-state-helper: Drop drm_atomic_helper_connector_hdmi_force() | Cristian Ciocaltea | [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/f87b6507e1d9fd4a6264059a09592efe0e837e5a) |
| 0150 | drm/bridge: adv7511: Advertise HDMI 1.2 capabilities | Cristian Ciocaltea | [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/5be390c1d60a85b5ae0581fba8f5b12614325540) |
| 0151 | drm/bridge: inno-hdmi: Advertise HDMI 1.2 capabilities | Cristian Ciocaltea | [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/159d1c85989de1ec19fbb67d51b4592a849107fa) |
| 0152 | drm/bridge: ite-it6263: Drop redundant .mode_valid hook | Cristian Ciocaltea | [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/4dde4a64618c01c065ebbf73448b7cb47b9e6c57) |
| 0153 | drm/bridge: ite-it6263: Advertise HDMI 1.3 capabilities | Cristian Ciocaltea | [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/d97d274f557605520e04eebed18b2019a9b19961) |
| 0154 | drm/bridge: ite-it66121: Advertise HDMI 1.2 capabilities | Cristian Ciocaltea | [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/736478109af1cba7590789c3d3cbc0faa52180cd) |
| 0155 | drm/bridge: lontium-lt9611: Advertise HDMI 1.4 capabilities | Cristian Ciocaltea | [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/f25d223f99fb729bc3a1ff3410a3837f1cb384f3) |
| 0156 | drm/rockchip: rk3066_hdmi: Advertise HDMI 1.4 capabilities | Cristian Ciocaltea | [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/de5c3452f9c29e5ee51130f46a0eb90bebae5f48) |
| 0157 | drm/sun4i: hdmi: Convert to drmm_connector_hdmi_init() | Cristian Ciocaltea | [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/d06e091f93b79e9d52c50e1fa3abb952bfe53c44) |
| 0158 | drm/tests: edid: Add 4K@60Hz EDID with 600MHz TMDS | Cristian Ciocaltea | [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/bb0c4262b34ff3b14d32c83e27c0a43a6fff1cbe) |
| 0159 | drm/tests: edid: Fix conformity for 1080p+4K YUV420 200MHz EDID | Cristian Ciocaltea | [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/73b4b6faa9d5a86072810666ae2d0d4beb981c81) |
| 0160 | drm/tests: edid: Fix conformity for 4K RGB/YUV 340MHz EDID | Cristian Ciocaltea | [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/d2e29a5cab4c2b9d569483303855cab7ae3976e5) |
| 0161 | drm/tests: bridge: Set supported HDMI version | Cristian Ciocaltea | [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/f8f9038f2977bc03a4e7f4a4e0ab7059e105e3a6) |
| 0162 | drm/tests: connector: Convert to drmm_connector_hdmi_init() | Cristian Ciocaltea | [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/d9c320afc7327a43bcbeaa63fd15976e91d259a0) |
| 0163 | drm/tests: connector: Add HDMI max_tmds_char_rate init coverage | Cristian Ciocaltea | [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/7d1ef5e9c8182bac916b78451898cfc72da4ad90) |
| 0164 | drm/tests: connector: Add HDMI source-side scrambler coverage | Cristian Ciocaltea | [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/78b88915d47d5cacb1ed5dd43eaf80d6901dba24) |
| 0165 | drm/tests: hdmi_state_helper: Convert to drmm_connector_hdmi_init() | Cristian Ciocaltea | [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/ab5baf66c5d328d4a72f65d6736b75a118534272) |
| 0166 | drm/tests: hdmi_state_helper: Add connector-provided max_tmds_char_rate coverage | Cristian Ciocaltea | [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/4ce9f198e401dd298b1de97bb4f3fd5684af4dd7) |
| 0167 | drm/tests: hdmi_state_helper: Cover source-side scrambling decision | Cristian Ciocaltea | [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/1530b4f968d68b6afaa53a3ef587137a486cbcb0) |
| 0168 | drm/connector: Remove drmm_connector_hdmi_ini2() | Cristian Ciocaltea | [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/07725f9b1d7f907afa77b772ae735b0f1c053aba) |
| 0169 | drm/connector: Drop redundant hdmi vendor/product fields | Cristian Ciocaltea | [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/337260189c5b114ffe80d49305d0f64e7e7ebd7e) |
| 0170 | drm/connector: Drop redundant hdmi supported_formats field | Cristian Ciocaltea | [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/c75687841c670eab304aba0e2aea8d82a0e09ac6) |
| 0171 | drm/connector: Drop redundant max_bpc field | Cristian Ciocaltea | [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/5469116bb85c1463d3c70c5aeb1840ccf4cb39b6) |
| 0172 | video/hdmi: Define SPD InfoFrame field lengths and use strtomem_pad() | Cristian Ciocaltea | [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/3ff0fab2d3fcd6bafc7fa895183baa8fb037971f) |
| 0173 | drm/connector: Use the SPD InfoFrame field length defines | Cristian Ciocaltea | [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/75207b498d475d8201184ad3ae0d41e05e400acc) |
| 0174 | drm/tests: hdmi: Add SPD InfoFrame vendor/product coverage | Cristian Ciocaltea | [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/3688d3a4555e947a8aa04f500098c37330082c31) |
| 0175 | video/hdmi: Add HDMI 2.1+ FRL constants and helpers | Cristian Ciocaltea | [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/73d4f48e0fffddc75083d923c72152587c76f1d3) |
| 0176 | drm/connector: Add HDMI 2.1 FRL infrastructure | Cristian Ciocaltea | [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/a8e27db3d332671aca0b087a7633b37d365abd7b) |
| 0177 | drm/display: scdc: Convert bit-field macros to use BIT() | Cristian Ciocaltea | [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/653fff1080da5eebfddf1b36f2cda6e4d8b4b653) |
| 0178 | drm/display: scdc: Add missing HDMI 2.1 FRL register definitions | Cristian Ciocaltea | [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/01e574defbe52efb1ba1c3d666080655f9864bc0) |
| 0179 | drm/display: scdc-helper: Add FRL link training control functions | Cristian Ciocaltea | [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/daefcfe602cec46a1f0ad2d3df71c5123a00804c) |
| 0180 | drm/display: hdmi-state-helper: Support HDMI 2.1 FRL mode validation | Cristian Ciocaltea | [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/2b4eeab19d23fa094e2859c5b4051fbfac3e0e60) |
| 0181 | drm/display: hdmi: Provide hook for extending FRL mode validation | Cristian Ciocaltea | [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/b7b24d5b1840f1a80694c0c6e590119982315211) |
| 0182 | drm/display: hdmi: Add FRL link training helpers | Cristian Ciocaltea | [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/63e9859fe3622490e445b86dfbf0a130e86b91c7) |
| 0183 | drm/display: hdmi: Add helper for ACR params in FRL mode | Cristian Ciocaltea | [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/e454f9a27f2bc5ca6101c0eb59f9c1b6037f7911) |
| 0184 | drm/bridge: Add bridge ops for source-side HDMI 2.1 FRL | Cristian Ciocaltea | [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/15065fc8aa19cbe1c16d2c2688c6f2e66c657e9a) |
| 0185 | drm/display: bridge-connector: Wire up HDMI 2.1 FRL bridge ops | Cristian Ciocaltea | [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/6f3bf6e8504a5403ce23e4063ff8a2c604a2eeab) |
| 0186 | drm/display: bridge-connector: Wire up rate validation for HDMI 2.1 bridges | Cristian Ciocaltea | [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/839a9b4de20f1e77784c6a681fcb5239840a0e71) |
| 0187 | drm/bridge: dw-hdmi-qp: Log resolution and refresh rate in atomic_enable() | Cristian Ciocaltea | [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/395989608fcf9e73c1d4f061dc19a594900ff5ad) |
| 0188 | drm/bridge: dw-hdmi-qp: Add HDMI 2.1 FRL support | Cristian Ciocaltea | [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/4ec5a0f99f1088358f9f6e86efdb107ffc75d1d1) |
| 0189 | drm/rockchip: vop2: Scale ACLK rate up for RK3588 FRL display modes | Cristian Ciocaltea | [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/331a638a33ae3f0515669ff9bdad26f7c382aa76) |
| 0190 | drm/rockchip: dw_hdmi_qp: Switch to .atomic_enable() encoder hook | Cristian Ciocaltea | [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/c00775441c909fb4e5e01ca3162735df443b165d) |
| 0191 | drm/rockchip: dw_hdmi_qp: Wire up FRL operating mode | Cristian Ciocaltea | [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/99e720c2e726ff652b523572c386575ccbb0cf44) |
| 0192 | drm/bridge: dw-hdmi-qp: Advertise HDMI 2.1 support | Cristian Ciocaltea | [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/c196a9a0160cdd6315949104cb5da3bd4c5c61a0) |
| 0193 | drm/display: bridge-connector: Add optional TxFFE level control | Cristian Ciocaltea | [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/ff419783e924db1fcf2c2ea1413bcba165585bf5) |
| 0194 | drm/display: hdmi: Add TxFFE level control to FRL helper | Cristian Ciocaltea | [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/470f7cbec257b9bd37741bf5b381b33bb5875f3a) |
| 0195 | drm/bridge: dw-hdmi-qp: Add TxFFE level control support | Cristian Ciocaltea | [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/d11de34fd3693c12bfa7e792b8530f3487a511c6) |
| 0196 | drm/rockchip: dw_hdmi_qp: Wire up TxFFE level control | Cristian Ciocaltea | [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/9628921a85e814c93988407a4a88aafe99ecd0ad) |
| 0197 | drm/tests: edid: Add 4K@60Hz EDID with 48Gbps FRL | Cristian Ciocaltea | [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/ff0ba24973490af8290b7348172054b38bfeee9e) |
| 0198 | drm/tests: connector: Add HDMI 2.1 FRL init coverage | Cristian Ciocaltea | [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/24338e89ddbb991b343b333ed8e84f531bd14cd8) |
| 0199 | drm/tests: hdmi_frl: Add coverage for the HDMI 2.1 FRL helpers | Cristian Ciocaltea | [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/bddbbec77e7083bd2e32200d7f56a5504ca4ee47) |
| 0200 | drm/tests: hdmi_state_helper: Add HDMI 2.1 FRL mode validation coverage | Cristian Ciocaltea | [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/c1c6b535125c401967bb5bdf3b7dff516cb2f47b) |
| 0201 | drm/tests: hdmi_state_helper: Cover HDMI 2.1 FRL rate negotiation | Cristian Ciocaltea | [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/a57803ba40734a14b5b64ad938a967fe86269ebe) |
| 0202 | drm/bridge: dw-hdmi-qp: Guard clear_audio_infoframe when PHY is down | Frank Zhang | [link](https://patch.msgid.link/20260512103153.8861-1-rmxpzlb@gmail.com) [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/66689431479746ecda2eb2247e7ab22a75c50d52) |
| 0203 | dt-bindings: display: vop2: Add missing reset properties | Cristian Ciocaltea | [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/12027d821fb039e6ddf46068c26926622391203f) |
| 0204 | drm/rockchip: vop2: Fix resource leak on vop2_enable() error path | Cristian Ciocaltea | [link](https://lore.kernel.org/all/20260623202043.8BFE21F000E9@smtp.kernel.org/) [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/61246543b89cb4510c3638714a0c3f2c1a73fbd4) |
| 0205 | drm/rockchip: vop2: Balance state on atomic_enable() error paths | Cristian Ciocaltea | [link](https://lore.kernel.org/all/20260623202043.8BFE21F000E9@smtp.kernel.org/) [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/c9898184c8ec344937020b009c38567c67818dc8) |
| 0206 | drm/rockchip: vop2: Send pending event when atomic_enable() fails | Cristian Ciocaltea | [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/218e192c815fab4e93bbefb9db27760d3fa3d80b) |
| 0207 | drm/rockchip: vop2: Avoid division by zero when computing max_dclk | Cristian Ciocaltea | [link](https://lore.kernel.org/all/20260623203310.9F8C81F000E9@smtp.kernel.org/) [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/0cbec9810225c4f64fcdd529efe76446657e48e0) |
| 0208 | drm/rockchip: vop2: Fix VOP2_MAX_DCLK_RATE overflow on 32-bit | Cristian Ciocaltea | [link](https://lore.kernel.org/all/20260623203310.9F8C81F000E9@smtp.kernel.org/) [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/bb3614162a8dfffef0de357222400cac9ad31003) |
| 0209 | drm/rockchip: vop2: Reset AXI and DCLK to improve robustness | Cristian Ciocaltea | [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/5c9f91ba9445eaf165c7557e87a4a8f4ba416bec) |
| 0210 | drm/rockchip: vop2: Avoid DCLK source switch for 10-bit YUV422 output | Cristian Ciocaltea | [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/13a21849eec5c53cfc30704c373eeb30dfb85b19) |
| 0211 | drm/rockchip: vop2: Consolidate HDMI PHY PLL clock parent switch | Cristian Ciocaltea | [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/ae425e223ce8387cda56fc3b8b89259cc9eab89f) |
| 0212 | drm/rockchip: vop2: Switch to enum vop_csc_format | Cristian Ciocaltea | [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/0f5699ca09d0e717291210b04671c8e16d24b520) |
| 0213 | drm/rockchip: dw_hdmi_qp: Support 10-bit YUV422 output format | Cristian Ciocaltea | [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/58f04670b29d7cc4d5368f2ee6d8e05500133589) |
| 0214 | drm/rockchip: dw_hdmi_qp: Enable YUV420 output format | Cristian Ciocaltea | [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/08750040e2a2cb90d4bb162d60f699ac9b4f4280) |
| 0217 | accel/rocket: number the cores by devicetree position, not bind order | Igor Paunovic |  |
| 0218 | accel/rocket: keep core slots stable across unbind and rebind | Igor Paunovic |  |
| 0219 | accel/rocket: request the core clocks by name | Igor Paunovic |  |
| 0220 | dt-bindings: npu: rockchip: allow DVFS and thermal properties | Igor Paunovic |  |
| 0221 | arm64: dts: rockchip: rk3588: add an OPP table for the NPU | Igor Paunovic | [link](https://gitlab.collabora.com/nicolas/linux/-/commits/rock5b-npu-poc-4) |
| 0222 | accel/rocket: restore the NPU clock boot rate before powering the cores down | Igor Paunovic |  |
| 0223 | accel/rocket: add devfreq support | Igor Paunovic |  |
| 0224 | accel/rocket: register a devfreq cooling device | Igor Paunovic |  |
| 0225 | arm64: dts: rockchip: rk3588: add passive cooling to the NPU thermal zone | Igor Paunovic |  |
| 0226 | dt-bindings: gpu: mali-valhall-csf: Add bus clock for RK3588 | Jonas Karlman | [link](https://github.com/armbian/linux-rockchip/pull/380) |
| 0227 | drm/panthor: Add support for a bus clk | Jonas Karlman | [link](https://github.com/armbian/linux-rockchip/pull/380) |
| 0229 | arm64: dts: rockchip: rk3588: Use SCMI GPU clock as the GPU core clock | Jonas Karlman | [link](https://github.com/armbian/linux-rockchip/pull/380) |
| 0231 | media: rkvdec: vp9: Changing get_ref_buf function name to get_ref_buf_vp9 | Venkata Atchuta Bheemeswara Sarma Darbha |  |
| 0232 | media: rkvdec: Move vp9 functions to common file | Venkata Atchuta Bheemeswara Sarma Darbha |  |
| 0233 | media: rkvdec: Add VP9 support for VDPU381 variant | Venkata Atchuta Bheemeswara Sarma Darbha |  |
| 0234 | media: rkvdec: align bytesperline to 64 bytes in rkvdec_fill_decoded_pixfmt() | Igor Paunovic |  |
| 0254 | media: h264: Add a more generic reflist builder init | Paul Kocialkowski | [link](https://patch.msgid.link/20260522101653.2565125-2-paulk@sys-base.io) |
| 0255 | media: uapi: Add H.264 stateless encode support | Paul Kocialkowski | [link](https://patch.msgid.link/20260522101653.2565125-3-paulk@sys-base.io) |
| 0256 | media: h264: Add SPS video definitions | Paul Kocialkowski | [link](https://patch.msgid.link/20260522101653.2565125-4-paulk@sys-base.io) |
| 0257 | media: h264: Add stateless encode core | Paul Kocialkowski | [link](https://patch.msgid.link/20260522101653.2565125-5-paulk@sys-base.io) |
| 0258 | media: h264: Add stateless encode rbsp | Paul Kocialkowski | [link](https://patch.msgid.link/20260522101653.2565125-6-paulk@sys-base.io) |
| 0259 | media: h264: Add stateless encode reference management | Paul Kocialkowski | [link](https://patch.msgid.link/20260522101653.2565125-7-paulk@sys-base.io) |
| 0260 | media: h264: Add stateless encode rate control | Paul Kocialkowski | [link](https://patch.msgid.link/20260522101653.2565125-8-paulk@sys-base.io) |
| 0270 | media: verisilicon: Report default pixel coding for non-JPEG and fix JPEG case | Paul Kocialkowski | [link](https://patch.msgid.link/20260522101653.2565125-9-paulk@sys-base.io) |
| 0271 | media: hantro: use hantro_decoded_buffer only for dst_vq | Marco Felsch | [link](https://patch.msgid.link/20260522101653.2565125-11-paulk@sys-base.io) |
| 0272 | media: verisilicon: Add common encoder parm and frameintervals ioctls | Paul Kocialkowski | [link](https://patch.msgid.link/20260522101653.2565125-12-paulk@sys-base.io) |

## (c) Local only / DO NOT UPSTREAM (`local/`)

| # | Subject | Author | Link |
|---|---|---|---|
| 0002 | media: rockchip: rga, rkvdec: sync with v7.4 merge window (c339f4010) | Arun Iyengar |  |
