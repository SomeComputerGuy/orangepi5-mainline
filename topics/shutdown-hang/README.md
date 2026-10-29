# shutdown-hang: arm-smmu-v3: PCIe SMMU power domain and clock (SATA-root reboot hang)

- Workspace branch: `opi5/shutdown-hang-7.3` (exported 2026-10-29)
- Kernel fork branch: `opi5/shutdown-hang` (see PUBLISH.md)
- Sits on: `board-sata` (base commit `5e33b74b04cf`)
- Hardware test: yes: reboot hang fixed, reboots take <1 s; in the image kernel (patches/linux/0130-0134)
- Next upstream step: send bindings + driver + dts as one series (iommu, devicetree, linux-rockchip)
- Patches: 5 = 5 ours, 0 carried from others, 0 local-only

Apply with `git am` in the order listed in [`series`](series), on top of the parent topic (or check out the fork branch). Patch numbers are the position in that order.

## (a) Ours, intended for upstream (`ours/`)

| # | Subject | Author | Link |
|---|---|---|---|
| 0001 | dt-bindings: iommu: arm,smmu-v3: allow a power domain | Arun Iyengar |  |
| 0002 | arm64: dts: rockchip: add the PCIe power domain to the RK3588 PCIe SMMU | Arun Iyengar |  |
| 0003 | dt-bindings: iommu: arm,smmu-v3: allow clocks | Arun Iyengar |  |
| 0004 | iommu/arm-smmu-v3: enable optional clocks | Arun Iyengar |  |
| 0005 | arm64: dts: rockchip: add the clock of the RK3588 PCIe SMMU | Arun Iyengar |  |

## Notes, results and test tools

- [notes/RESULTS.md](notes/RESULTS.md)
