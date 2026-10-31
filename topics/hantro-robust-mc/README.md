# hantro-robust-mc: hantro-robust rebased on hantro-multicore

- Workspace branch: `opi5/hantro-robust-mc` (exported 2026-10-31)
- Kernel fork branch: `opi5/hantro-robust-mc` (see PUBLISH.md)
- Sits on: `hantro-multicore` (base commit `86102e78de87`)
- Hardware test: see hantro-robust/TESTING.md
- Next upstream step: as hantro-robust
- Patches: 6 = 6 ours, 0 carried from others, 0 local-only

Apply with `git am` in the order listed in [`series`](series), on top of the parent topic (or check out the fork branch). Patch numbers are the position in that order.

## (a) Ours, intended for upstream (`ours/`)

| # | Subject | Author | Link |
|---|---|---|---|
| 0001 | media: verisilicon: Drop the runtime PM reference when clocks fail to enable | Arun Iyengar |  |
| 0002 | media: verisilicon: Make the codec run error handling consistent | Arun Iyengar |  |
| 0003 | media: verisilicon: Reset the Rockchip encoder cores on timeout | Arun Iyengar |  |
| 0004 | media: verisilicon: Reinitialize the IOMMU after a timeout | Arun Iyengar |  |
| 0005 | dt-bindings: media: rockchip,rk3568-vepu: Add the reset lines | Arun Iyengar |  |
| 0006 | arm64: dts: rockchip: Add the reset lines of the RK3588 VEPU121 cores | Arun Iyengar |  |

## Notes, results and test tools

- [notes/TESTING.md](notes/TESTING.md)
