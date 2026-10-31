# dp-altmode: USB-C DisplayPort alt-mode (USBDP PHY, dwc3 glue, dw-dp series) + Orange Pi 5 DT

- Workspace branch: `opi5/dp-altmode-7.3` (exported 2026-10-31)
- Kernel fork branch: `opi5/dp-altmode` (see PUBLISH.md)
- Sits on: `board-sata` (base commit `5e33b74b04cf`)
- Hardware test: not yet
- Next upstream step: test on the board; send the Orange Pi 5 DT patch after the dw-dp series lands
- Patches: 67 = 2 ours, 65 carried from others, 0 local-only

Apply with `git am` in the order listed in [`series`](series), on top of the parent topic (or check out the fork branch). Patch numbers are the position in that order.

## (a) Ours, intended for upstream (`ours/`)

| # | Subject | Author | Link |
|---|---|---|---|
| 0062 | drm/bridge: Keep oob_notify at the end of drm_bridge_funcs | Arun Iyengar |  |
| 0067 | arm64: dts: rockchip: Add USB-C DP AltMode for Orange Pi 5/5B | Arun Iyengar | [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/7983809d4d2c5a6c39d936ed3140e378a3257ebd) [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/c2d2e2b10a55c4d740a2faf1526a70c4f19da047) |

## (b) Carried from others, authorship kept (`carried/`)

| # | Subject | Author | Link |
|---|---|---|---|
| 0001 | dt-bindings: phy: rockchip-usbdp: add improved ports scheme | Sebastian Reichel | [link](https://patch.msgid.link/20260915-rockchip-usbdp-cleanup-v15-1-80e2c11d1ce8@collabora.com) |
| 0002 | phy: rockchip: usbdp: Update mode_change after error handling | Sebastian Reichel | [link](https://lore.kernel.org/linux-phy/20260612163835.8D5471F000E9@smtp.kernel.org/) [link](https://patch.msgid.link/20260915-rockchip-usbdp-cleanup-v15-2-80e2c11d1ce8@collabora.com) |
| 0003 | phy: rockchip: usbdp: Do not lose USB3 PHY status | Sebastian Reichel | [link](https://patch.msgid.link/20260915-rockchip-usbdp-cleanup-v15-3-80e2c11d1ce8@collabora.com) |
| 0004 | phy: rockchip: usbdp: Fix devm_clk_bulk_get_all check | Sebastian Reichel | [link](https://lore.kernel.org/linux-phy/20260612164107.C7DB21F000E9@smtp.kernel.org/) [link](https://patch.msgid.link/20260915-rockchip-usbdp-cleanup-v15-4-80e2c11d1ce8@collabora.com) |
| 0005 | phy: rockchip: usbdp: Handle missing clock-names DT property gracefully | Sebastian Reichel | [link](https://patch.msgid.link/20260915-rockchip-usbdp-cleanup-v15-5-80e2c11d1ce8@collabora.com) |
| 0006 | phy: rockchip: usbdp: Drop seamless DP takeover | Sebastian Reichel | [link](https://patch.msgid.link/20260915-rockchip-usbdp-cleanup-v15-6-80e2c11d1ce8@collabora.com) |
| 0007 | phy: rockchip: usbdp: Keep clocks running on PHY re-init | Sebastian Reichel | [link](https://patch.msgid.link/20260915-rockchip-usbdp-cleanup-v15-7-80e2c11d1ce8@collabora.com) |
| 0008 | phy: rockchip: usbdp: Amend SSC modulation deviation | Frank Wang | [link](https://patch.msgid.link/20260915-rockchip-usbdp-cleanup-v15-8-80e2c11d1ce8@collabora.com) |
| 0009 | phy: rockchip: usbdp: Fix LFPS detect threshold control | William Wu | [link](https://patch.msgid.link/20260915-rockchip-usbdp-cleanup-v15-9-80e2c11d1ce8@collabora.com) |
| 0010 | phy: rockchip: usbdp: Add missing mode_change update | Sebastian Reichel | [link](https://patch.msgid.link/20260915-rockchip-usbdp-cleanup-v15-10-80e2c11d1ce8@collabora.com) |
| 0011 | phy: rockchip: usbdp: Support single-lane DP | Zhang Yubing | [link](https://patch.msgid.link/20260915-rockchip-usbdp-cleanup-v15-11-80e2c11d1ce8@collabora.com) |
| 0012 | phy: rockchip: usbdp: Limit DP lane count to muxed lanes | Sebastian Reichel | [link](https://lore.kernel.org/linux-phy/20260612165546.98E1F1F000E9@smtp.kernel.org/) [link](https://patch.msgid.link/20260915-rockchip-usbdp-cleanup-v15-12-80e2c11d1ce8@collabora.com) |
| 0013 | phy: rockchip: usbdp: Rename DP lane functions | Sebastian Reichel | [link](https://patch.msgid.link/20260915-rockchip-usbdp-cleanup-v15-13-80e2c11d1ce8@collabora.com) |
| 0014 | phy: rockchip: usbdp: Use FIELD_PREP_WM16_CONST | Sebastian Reichel | [link](https://patch.msgid.link/20260915-rockchip-usbdp-cleanup-v15-14-80e2c11d1ce8@collabora.com) |
| 0015 | phy: rockchip: usbdp: Cleanup DP lane selection function | Sebastian Reichel | [link](https://patch.msgid.link/20260915-rockchip-usbdp-cleanup-v15-15-80e2c11d1ce8@collabora.com) |
| 0016 | phy: rockchip: usbdp: Register DP aux bridge | Sebastian Reichel | [link](https://patch.msgid.link/20260915-rockchip-usbdp-cleanup-v15-16-80e2c11d1ce8@collabora.com) |
| 0017 | phy: rockchip: usbdp: Drop DP HPD handling | Sebastian Reichel | [link](https://patch.msgid.link/20260915-rockchip-usbdp-cleanup-part2-v15-1-8d507cb1174f@collabora.com) |
| 0018 | phy: rockchip: usbdp: Rename mode_change to phy_needs_reinit | Sebastian Reichel | [link](https://patch.msgid.link/20260915-rockchip-usbdp-cleanup-part2-v15-2-8d507cb1174f@collabora.com) |
| 0019 | phy: rockchip: usbdp: Re-init the PHY on orientation change | Sebastian Reichel | [link](https://patch.msgid.link/20260915-rockchip-usbdp-cleanup-part2-v15-3-8d507cb1174f@collabora.com) |
| 0020 | phy: rockchip: usbdp: Factor out lane_mux_sel setup | Sebastian Reichel | [link](https://patch.msgid.link/20260915-rockchip-usbdp-cleanup-part2-v15-4-8d507cb1174f@collabora.com) |
| 0021 | phy: rockchip: usbdp: Properly handle TYPEC_STATE_SAFE and TYPEC_STATE_USB | Sebastian Reichel | [link](https://patch.msgid.link/20260915-rockchip-usbdp-cleanup-part2-v15-5-8d507cb1174f@collabora.com) |
| 0022 | phy: rockchip: usbdp: Use guard functions for mutex | Sebastian Reichel | [link](https://patch.msgid.link/20260915-rockchip-usbdp-cleanup-part2-v15-6-8d507cb1174f@collabora.com) |
| 0023 | phy: rockchip: usbdp: Hold mutex in DP PHY configure | Sebastian Reichel | [link](https://patch.msgid.link/20260915-rockchip-usbdp-cleanup-part2-v15-7-8d507cb1174f@collabora.com) |
| 0024 | phy: rockchip: usbdp: Add some extra debug messages | Sebastian Reichel | [link](https://patch.msgid.link/20260915-rockchip-usbdp-cleanup-part2-v15-8-8d507cb1174f@collabora.com) |
| 0025 | phy: rockchip: usbdp: Avoid xHCI SErrors | Sebastian Reichel | [link](https://patch.msgid.link/20260915-rockchip-usbdp-cleanup-part2-v15-9-8d507cb1174f@collabora.com) |
| 0026 | phy: rockchip: usbdp: Handle rk_udphy_reset_deassert errors | Sebastian Reichel | [link](https://patch.msgid.link/20260915-rockchip-usbdp-cleanup-part2-v15-10-8d507cb1174f@collabora.com) |
| 0027 | phy: rockchip: usbdp: Only enable USB3 when not in high-speed mode | Sebastian Reichel | [link](https://patch.msgid.link/20260915-rockchip-usbdp-cleanup-part2-v15-11-8d507cb1174f@collabora.com) |
| 0028 | phy: rockchip: usbdp: Track PHY power state | Sebastian Reichel | [link](https://patch.msgid.link/20261021-b4-rockchip-dwc3-rockchip-glue-v18-1-60000d03fca2@collabora.com) |
| 0029 | phy: rockchip: usbdp: Add reset hook support for dwc3 | Sebastian Reichel | [link](https://patch.msgid.link/20261021-b4-rockchip-dwc3-rockchip-glue-v18-2-60000d03fca2@collabora.com) |
| 0030 | usb: dwc3: rockchip: introduce glue driver | Sebastian Reichel | [link](https://patch.msgid.link/20261021-b4-rockchip-dwc3-rockchip-glue-v18-3-60000d03fca2@collabora.com) |
| 0031 | usb: dwc3: core: add post PHY registration hook for platform glue | Sebastian Reichel | [link](https://patch.msgid.link/20261021-b4-rockchip-dwc3-rockchip-glue-v18-4-60000d03fca2@collabora.com) |
| 0032 | usb: dwc3: rockchip: add USBDP PHY reset quirk | Sebastian Reichel | [link](https://patch.msgid.link/20261021-b4-rockchip-dwc3-rockchip-glue-v18-5-60000d03fca2@collabora.com) |
| 0033 | usb: gadget: define stub for usb_udc_vbus_handler | Sebastian Reichel | [link](https://patch.msgid.link/20261021-b4-rockchip-dwc3-rockchip-glue-v18-6-60000d03fca2@collabora.com) |
| 0034 | usb: dwc3: rockchip: fix USB-C reconnect in gadget mode | Sebastian Reichel | [link](https://patch.msgid.link/20261021-b4-rockchip-dwc3-rockchip-glue-v18-7-60000d03fca2@collabora.com) |
| 0035 | phy: rockchip: usbdp: Disable USB3 port during normal power-on | Sebastian Reichel | [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/52eef750d7c5ce13ea1d66b1be2d039c6250cb4c) |
| 0036 | phy: rockchip: usbdp: Drop -EPROBE_DEFER hack | Sebastian Reichel | [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/c03e9dd764007ac7a510e1c05a00ac08e07d8b03) |
| 0037 | phy: rockchip: usbdp: Rename mode to hw_mode | Sebastian Reichel | [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/9b2366277462f629452654e1b1d05e17c6a378e8) |
| 0038 | phy: rockchip: usbdp: Fix power state handling | Sebastian Reichel | [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/713114cb94f79a06377636747095ca823b093e62) |
| 0039 | phy: rockchip: usbdp: Re-init PHY on mux change | Sebastian Reichel | [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/2391da40eb39e26b31972ef4a6d7a3d997a1c209) |
| 0040 | phy: rockchip: usbdp: Add USB-C state without DP enabled | Sebastian Reichel | [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/b6c756709db3ae6f85ef8133de754a8e7b7ec894) |
| 0041 | drm/bridge: synopsys: dw-dp: Register DP AUX on bridge attach | Sebastian Reichel | [link](https://patch.msgid.link/20260806-synopsys-dw-dp-improvements-v11-1-0d508505f383@collabora.com) |
| 0042 | drm/bridge: synopsys: dw-dp: Fix incorrect resource lifetimes in bind callback | Sebastian Reichel | [link](https://patch.msgid.link/20260806-synopsys-dw-dp-improvements-v11-2-0d508505f383@collabora.com) |
| 0043 | drm/bridge: synopsys: dw-dp: Fix error handling for DP link enablement | Sebastian Reichel | [link](https://patch.msgid.link/20260806-synopsys-dw-dp-improvements-v11-3-0d508505f383@collabora.com) |
| 0044 | drm/bridge: synopsys: dw-dp: Document missing reset line deassert | Sebastian Reichel | [link](https://patch.msgid.link/20260806-synopsys-dw-dp-improvements-v11-4-0d508505f383@collabora.com) |
| 0045 | drm/bridge: synopsys: dw-dp: Add missing mutex cleanups on module removal | Sebastian Reichel | [link](https://patch.msgid.link/20260806-synopsys-dw-dp-improvements-v11-5-0d508505f383@collabora.com) |
| 0046 | drm/bridge: synopsys: dw-dp: Fix AUX transfer timeout race condition | Sebastian Reichel | [link](https://patch.msgid.link/20260806-synopsys-dw-dp-improvements-v11-6-0d508505f383@collabora.com) |
| 0047 | drm/bridge: synopsys: dw-dp: Fix support for short I2C reads | Sebastian Reichel | [link](https://patch.msgid.link/20260806-synopsys-dw-dp-improvements-v11-7-0d508505f383@collabora.com) |
| 0048 | drm/bridge: synopsys: dw-dp: Free output_fmts when none are valid | Sebastian Reichel | [link](https://patch.msgid.link/20260806-synopsys-dw-dp-improvements-v11-8-0d508505f383@collabora.com) |
| 0049 | drm/bridge: synopsys: dw-dp: Support MEDIA_BUS_FMT_FIXED | Sebastian Reichel | [link](https://patch.msgid.link/20260806-synopsys-dw-dp-improvements-v11-9-0d508505f383@collabora.com) |
| 0050 | drm/bridge: synopsys: dw-dp: Add follow-up bridge support | Sebastian Reichel | [link](https://patch.msgid.link/20260806-synopsys-dw-dp-improvements-v11-10-0d508505f383@collabora.com) |
| 0051 | drm/bridge: Add out-of-band HPD notify handler | Sebastian Reichel | [link](https://patch.msgid.link/20260806-synopsys-dw-dp-improvements-v11-11-0d508505f383@collabora.com) |
| 0052 | drm/bridge: synopsys: dw-dp: Support software triggered OOB HPD | Sebastian Reichel | [link](https://patch.msgid.link/20260806-synopsys-dw-dp-improvements-v11-12-0d508505f383@collabora.com) |
| 0053 | drm/rockchip: dw_dp: Implement out-of-band HPD handling | Sebastian Reichel | [link](https://patch.msgid.link/20260806-synopsys-dw-dp-improvements-v11-13-0d508505f383@collabora.com) |
| 0054 | drm/bridge: synopsys: dw-dp: Add Runtime PM support | Sebastian Reichel | [link](https://patch.msgid.link/20260806-synopsys-dw-dp-improvements-v11-14-0d508505f383@collabora.com) |
| 0055 | drm/rockchip: dw_dp: Add runtime PM support | Sebastian Reichel | [link](https://patch.msgid.link/20260806-synopsys-dw-dp-improvements-v11-15-0d508505f383@collabora.com) |
| 0056 | drm/bridge: synopsys: dw-dp: Protect sdp_reg_bank from concurrent access | Sebastian Reichel | [link](https://patch.msgid.link/20260806-synopsys-dw-dp-improvements-v11-16-0d508505f383@collabora.com) |
| 0057 | drm/bridge: synopsys: dw-dp: Drop useless reservation of first slot | Sebastian Reichel | [link](https://patch.msgid.link/20260806-synopsys-dw-dp-improvements-v11-17-0d508505f383@collabora.com) |
| 0058 | drm/bridge: synopsys: dw-dp: Clear only enabled SDPs on atomic disable | Sebastian Reichel | [link](https://patch.msgid.link/20260806-synopsys-dw-dp-improvements-v11-18-0d508505f383@collabora.com) |
| 0059 | drm/bridge: synopsys: dw-dp: Use regmap_set_bits in dw_dp_send_sdp | Sebastian Reichel | [link](https://patch.msgid.link/20260806-synopsys-dw-dp-improvements-v11-19-0d508505f383@collabora.com) |
| 0060 | dt-bindings: display: rockchip: dw-dp: Fix sound DAI cells | Sebastian Reichel | [link](https://patch.msgid.link/20260806-synopsys-dw-dp-improvements-v11-20-0d508505f383@collabora.com) |
| 0061 | drm/bridge: synopsys: dw-dp: Add audio support | Sebastian Reichel | [link](https://patch.msgid.link/20260806-synopsys-dw-dp-improvements-v11-21-0d508505f383@collabora.com) |
| 0063 | usb: typec: mux: initialize orientation switch array | Haobo Cheng | [link](https://patch.msgid.link/20260804083434.20885-1-i@4t.pw) |
| 0064 | usb: typec: mux: initialize mux switch array | Sebastian Reichel | [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/9e1bfcaf758d271d7aa57a056351e065dc5d9a8c) |
| 0065 | drm/connector: Cache out-of-band hotplug events | Sebastian Reichel | [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/9b8b3adadabe758cf1848df72dce497d2a37d99f) |
| 0066 | arm64: dts: rockchip: Fix DP sound-dai-cells on RK3588 | Sebastian Reichel | [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/d2872441c3d55c2cbb9c0449a6c90e22babadb8d) |

## Notes, results and test tools

- [notes/RESULTS.md](notes/RESULTS.md)
