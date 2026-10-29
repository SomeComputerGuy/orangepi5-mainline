# v7.4-dp-altmode: 7.4 base: dw-dp / dwc3 glue series

- Workspace branch: `opi5/dp-altmode` (exported 2026-10-29)
- Kernel fork branch: `opi5/v7.4-dp-altmode` (see PUBLISH.md)
- Sits on: `c339f4010` (base commit `c339f4010dea`)
- Hardware test: via dp-altmode (v7.3)
- Next upstream step: rebase onto 7.4-rc1
- Patches: 28 = 0 ours, 28 carried from others, 0 local-only

Apply with `git am` in the order listed in [`series`](series), on top of the parent topic (or check out the fork branch). Patch numbers are the position in that order.

## (b) Carried from others, authorship kept (`carried/`)

| # | Subject | Author | Link |
|---|---|---|---|
| 0001 | drm/bridge: synopsys: dw-dp: Register DP AUX on bridge attach | Sebastian Reichel | [link](https://patch.msgid.link/20260806-synopsys-dw-dp-improvements-v11-1-0d508505f383@collabora.com) |
| 0002 | drm/bridge: synopsys: dw-dp: Fix incorrect resource lifetimes in bind callback | Sebastian Reichel | [link](https://patch.msgid.link/20260806-synopsys-dw-dp-improvements-v11-2-0d508505f383@collabora.com) |
| 0003 | drm/bridge: synopsys: dw-dp: Fix error handling for DP link enablement | Sebastian Reichel | [link](https://patch.msgid.link/20260806-synopsys-dw-dp-improvements-v11-3-0d508505f383@collabora.com) |
| 0004 | drm/bridge: synopsys: dw-dp: Document missing reset line deassert | Sebastian Reichel | [link](https://patch.msgid.link/20260806-synopsys-dw-dp-improvements-v11-4-0d508505f383@collabora.com) |
| 0005 | drm/bridge: synopsys: dw-dp: Add missing mutex cleanups on module removal | Sebastian Reichel | [link](https://patch.msgid.link/20260806-synopsys-dw-dp-improvements-v11-5-0d508505f383@collabora.com) |
| 0006 | drm/bridge: synopsys: dw-dp: Fix AUX transfer timeout race condition | Sebastian Reichel | [link](https://patch.msgid.link/20260806-synopsys-dw-dp-improvements-v11-6-0d508505f383@collabora.com) |
| 0007 | drm/bridge: synopsys: dw-dp: Fix support for short I2C reads | Sebastian Reichel | [link](https://patch.msgid.link/20260806-synopsys-dw-dp-improvements-v11-7-0d508505f383@collabora.com) |
| 0008 | drm/bridge: synopsys: dw-dp: Free output_fmts when none are valid | Sebastian Reichel | [link](https://patch.msgid.link/20260806-synopsys-dw-dp-improvements-v11-8-0d508505f383@collabora.com) |
| 0009 | drm/bridge: synopsys: dw-dp: Support MEDIA_BUS_FMT_FIXED | Sebastian Reichel | [link](https://patch.msgid.link/20260806-synopsys-dw-dp-improvements-v11-9-0d508505f383@collabora.com) |
| 0010 | drm/bridge: synopsys: dw-dp: Add follow-up bridge support | Sebastian Reichel | [link](https://patch.msgid.link/20260806-synopsys-dw-dp-improvements-v11-10-0d508505f383@collabora.com) |
| 0011 | drm/bridge: Add out-of-band HPD notify handler | Sebastian Reichel | [link](https://patch.msgid.link/20260806-synopsys-dw-dp-improvements-v11-11-0d508505f383@collabora.com) |
| 0012 | drm/bridge: synopsys: dw-dp: Support software triggered OOB HPD | Sebastian Reichel | [link](https://patch.msgid.link/20260806-synopsys-dw-dp-improvements-v11-12-0d508505f383@collabora.com) |
| 0013 | drm/rockchip: dw_dp: Implement out-of-band HPD handling | Sebastian Reichel | [link](https://patch.msgid.link/20260806-synopsys-dw-dp-improvements-v11-13-0d508505f383@collabora.com) |
| 0014 | drm/bridge: synopsys: dw-dp: Add Runtime PM support | Sebastian Reichel | [link](https://patch.msgid.link/20260806-synopsys-dw-dp-improvements-v11-14-0d508505f383@collabora.com) |
| 0015 | drm/rockchip: dw_dp: Add runtime PM support | Sebastian Reichel | [link](https://patch.msgid.link/20260806-synopsys-dw-dp-improvements-v11-15-0d508505f383@collabora.com) |
| 0016 | drm/bridge: synopsys: dw-dp: Protect sdp_reg_bank from concurrent access | Sebastian Reichel | [link](https://patch.msgid.link/20260806-synopsys-dw-dp-improvements-v11-16-0d508505f383@collabora.com) |
| 0017 | drm/bridge: synopsys: dw-dp: Drop useless reservation of first slot | Sebastian Reichel | [link](https://patch.msgid.link/20260806-synopsys-dw-dp-improvements-v11-17-0d508505f383@collabora.com) |
| 0018 | drm/bridge: synopsys: dw-dp: Clear only enabled SDPs on atomic disable | Sebastian Reichel | [link](https://patch.msgid.link/20260806-synopsys-dw-dp-improvements-v11-18-0d508505f383@collabora.com) |
| 0019 | drm/bridge: synopsys: dw-dp: Use regmap_set_bits in dw_dp_send_sdp | Sebastian Reichel | [link](https://patch.msgid.link/20260806-synopsys-dw-dp-improvements-v11-19-0d508505f383@collabora.com) |
| 0020 | dt-bindings: display: rockchip: dw-dp: Fix sound DAI cells | Sebastian Reichel | [link](https://patch.msgid.link/20260806-synopsys-dw-dp-improvements-v11-20-0d508505f383@collabora.com) |
| 0021 | drm/bridge: synopsys: dw-dp: Add audio support | Sebastian Reichel | [link](https://patch.msgid.link/20260806-synopsys-dw-dp-improvements-v11-21-0d508505f383@collabora.com) |
| 0022 | phy: rockchip: usbdp: Track PHY power state | Sebastian Reichel | [link](https://patch.msgid.link/20261021-b4-rockchip-dwc3-rockchip-glue-v18-1-60000d03fca2@collabora.com) |
| 0023 | phy: rockchip: usbdp: Add reset hook support for dwc3 | Sebastian Reichel | [link](https://patch.msgid.link/20261021-b4-rockchip-dwc3-rockchip-glue-v18-2-60000d03fca2@collabora.com) |
| 0024 | usb: dwc3: rockchip: introduce glue driver | Sebastian Reichel | [link](https://patch.msgid.link/20261021-b4-rockchip-dwc3-rockchip-glue-v18-3-60000d03fca2@collabora.com) |
| 0025 | usb: dwc3: core: add post PHY registration hook for platform glue | Sebastian Reichel | [link](https://patch.msgid.link/20261021-b4-rockchip-dwc3-rockchip-glue-v18-4-60000d03fca2@collabora.com) |
| 0026 | usb: dwc3: rockchip: add USBDP PHY reset quirk | Sebastian Reichel | [link](https://patch.msgid.link/20261021-b4-rockchip-dwc3-rockchip-glue-v18-5-60000d03fca2@collabora.com) |
| 0027 | usb: gadget: define stub for usb_udc_vbus_handler | Sebastian Reichel | [link](https://patch.msgid.link/20261021-b4-rockchip-dwc3-rockchip-glue-v18-6-60000d03fca2@collabora.com) |
| 0028 | usb: dwc3: rockchip: fix USB-C reconnect in gadget mode | Sebastian Reichel | [link](https://patch.msgid.link/20261021-b4-rockchip-dwc3-rockchip-glue-v18-7-60000d03fca2@collabora.com) |
