# board-dt: Combined board DT used on the test board (DT commits from the topics above)

- Workspace branch: `opi5/board-dt` (exported 2026-10-31)
- Kernel fork branch: `opi5/board-dt` (see PUBLISH.md)
- Sits on: `board-sata` (base commit `5e33b74b04cf`)
- Hardware test: yes: the test board boots this DTB
- Next upstream step: none (integration only)
- Patches: 22 = 16 ours, 6 carried from others, 0 local-only

Apply with `git am` in the order listed in [`series`](series), on top of the parent topic (or check out the fork branch). Patch numbers are the position in that order.

## (a) Ours, intended for upstream (`ours/`)

| # | Subject | Author | Link |
|---|---|---|---|
| 0001 | dt-bindings: media: add Rockchip IEP2 deinterlacer | Arun Iyengar |  |
| 0002 | arm64: dts: rockchip: add IEP2 deinterlacer to RK3588 | Arun Iyengar |  |
| 0003 | dt-bindings: media: Add Rockchip VDPU720 JPEG decoder | Arun Iyengar |  |
| 0004 | arm64: dts: rockchip: Add the JPEG decoder to rk3588-base | Arun Iyengar |  |
| 0005 | dt-bindings: media: rockchip,rk3568-vepu: Add the reset lines | Arun Iyengar |  |
| 0006 | arm64: dts: rockchip: Add the reset lines of the RK3588 VEPU121 cores | Arun Iyengar |  |
| 0007 | dt-bindings: iommu: arm,smmu-v3: allow a power domain | Arun Iyengar |  |
| 0008 | arm64: dts: rockchip: add the PCIe power domain to the RK3588 PCIe SMMU | Arun Iyengar |  |
| 0009 | dt-bindings: iommu: arm,smmu-v3: allow clocks | Arun Iyengar |  |
| 0010 | arm64: dts: rockchip: add the clock of the RK3588 PCIe SMMU | Arun Iyengar |  |
| 0011 | arm64: dts: rockchip: Add the encoder interrupt of the RK3588 VPU121 | Arun Iyengar |  |
| 0012 | arm64: dts: rockchip: Add the VEPU580 encoder cores to the RK3588 | Arun Iyengar |  |
| 0018 | arm64: dts: rockchip: use rgmii-id for the Orange Pi 5/5B ethernet PHY | Arun Iyengar |  |
| 0019 | arm64: dts: rockchip: add the SPI NOR flash supply on Orange Pi 5 | Arun Iyengar |  |
| 0020 | arm64: dts: rockchip: set the RK806 reset mode on Orange Pi 5 boards | Arun Iyengar |  |
| 0022 | arm64: dts: rockchip: Add USB-C DP AltMode for Orange Pi 5/5B | Arun Iyengar | [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/7983809d4d2c5a6c39d936ed3140e378a3257ebd) [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/c2d2e2b10a55c4d740a2faf1526a70c4f19da047) |

## (b) Carried from others, authorship kept (`carried/`)

| # | Subject | Author | Link |
|---|---|---|---|
| 0013 | dt-bindings: npu: rockchip: allow DVFS and thermal properties | Igor Paunovic |  |
| 0014 | arm64: dts: rockchip: rk3588: add an OPP table for the NPU | Igor Paunovic | [link](https://gitlab.collabora.com/nicolas/linux/-/commits/rock5b-npu-poc-4) |
| 0015 | arm64: dts: rockchip: rk3588: add passive cooling to the NPU thermal zone | Igor Paunovic |  |
| 0016 | dt-bindings: gpu: mali-valhall-csf: Add bus clock for RK3588 | Jonas Karlman | [link](https://github.com/armbian/linux-rockchip/pull/380) |
| 0017 | arm64: dts: rockchip: rk3588: Use SCMI GPU clock as the GPU core clock | Jonas Karlman | [link](https://github.com/armbian/linux-rockchip/pull/380) |
| 0021 | arm64: dts: rockchip: Fix DP sound-dai-cells on RK3588 | Sebastian Reichel | [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/d2872441c3d55c2cbb9c0449a6c90e22babadb8d) |
