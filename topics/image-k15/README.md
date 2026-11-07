# image-k15: Earlier image kernel (tag image-7.3.0+opi5.15): v7.3 + patches/linux as of 7.3.0+opi5.15; the feature branches below sit on it. The current image kernel is branch opi5/image

- Workspace branch: `k15-v4` (exported 2026-11-07)
- Kernel fork: tag `image-7.3.0+opi5.15` (retired branch `opi5/image-k15`; see PUBLISH.md)
- Sits on: `v7.3` (base commit `c03c1a14507d`)
- Hardware test: yes: ran on the board as the stock kernel
- Next upstream step: none (integration only); provenance in docs/image-kernel/MANIFEST.md
- Patches: 30 = 24 ours, 6 carried from others, 0 local-only

Apply with `git am` in the order listed in [`series`](series), on top of the parent topic (or check out the fork branch). Patch numbers are the position in that order.

## (a) Ours, intended for upstream (`ours/`)

| # | Subject | Author | Link |
|---|---|---|---|
| 0001 | v7.3 + patches/linux (450) | Arun Iyengar |  |
| 0002 | pmdomain: rockchip: remove subdomain links before the domains on error | Arun Iyengar |  |
| 0003 | pmdomain: rockchip: do not report probe deferral of a domain as an error | Arun Iyengar |  |
| 0004 | media: rockchip: rga: Register the video device after binding the cores | Arun Iyengar |  |
| 0005 | media: rockchip: rga: Drop the runtime PM reference on core bind errors | Arun Iyengar |  |
| 0006 | media: rockchip: rga: Print the version of the core being bound | Arun Iyengar |  |
| 0007 | media: rockchip: rga: Limit the RGA2 destination to 4096x4096 | Arun Iyengar |  |
| 0008 | drm/bridge: synopsys: dw-dp: Don't let detection clobber the link being trained | Arun Iyengar |  |
| 0009 | drm/bridge: synopsys: dw-dp: Ignore controller plug events with OOB HPD | Arun Iyengar |  |
| 0010 | drm/rockchip: vop2: Plan the video PLL for all video ports in atomic_check | Arun Iyengar |  |
| 0017 | drm/display: hdmi-state-helper: Force a modeset on Colorspace or HDR metadata changes | Arun Iyengar |  |
| 0018 | drm/rockchip: dw_hdmi_qp: Use the BT.2020 matrix for BT.2020 YCbCr output | Arun Iyengar |  |
| 0019 | drm/bridge: synopsys: dw-dp: Signal BT.2020 colorimetry for the output encoding | Arun Iyengar |  |
| 0020 | usb: typec: tcpm: Don't cut a pending state delay short on a re-queue | Arun Iyengar |  |
| 0021 | arm64: dts: rockchip: Mark the Orange Pi 5/5B Type-C port self-powered | Arun Iyengar |  |
| 0022 | usb: typec: fusb302: Toggle with the default Rp current | Arun Iyengar |  |
| 0023 | drm/rockchip: dw_dp: Attach the "color format" connector property | Arun Iyengar |  |
| 0024 | drm/rockchip: vop2: Add limited range RGB output | Arun Iyengar |  |
| 0025 | drm/rockchip: dw_hdmi_qp: Send limited range RGB and attach "Broadcast RGB" | Arun Iyengar |  |
| 0026 | drm/rockchip: dw_hdmi_qp: Encode SD and BT.601 YCbCr with the BT.601 matrix | Arun Iyengar |  |
| 0027 | dt-bindings: display: vop2: Add the RK3588 DCLK sources and their parents | Arun Iyengar |  |
| 0028 | drm/rockchip: vop2: Plan the video PLL in a private atomic object | Arun Iyengar |  |
| 0029 | clk: rockchip: rk3588: Don't reparent the VOP DCLK sources on a rate change | Arun Iyengar |  |
| 0030 | arm64: dts: rockchip: Add the VOP DCLK sources and their parents to RK3588 | Arun Iyengar |  |

## (b) Carried from others, authorship kept (`carried/`)

| # | Subject | Author | Link |
|---|---|---|---|
| 0011 | drm/rockchip: dw_hdmi_qp: attach the HDMI Colorspace connector property | Igor Paunovic |  |
| 0012 | drm/dp: Add drm_dp_hdr_metadata_infoframe_sdp_pack() | Igor Paunovic |  |
| 0013 | drm/display: bridge-connector: Preserve max bpc across connector reset | Igor Paunovic |  |
| 0014 | drm/rockchip: dw_dp: Attach "max bpc" connector property | Igor Paunovic |  |
| 0015 | drm/bridge: synopsys: dw-dp: Add HDR static metadata support | Igor Paunovic |  |
| 0016 | drm/bridge: synopsys: dw-dp: Add BT.2020 colorimetry support | Igor Paunovic |  |
