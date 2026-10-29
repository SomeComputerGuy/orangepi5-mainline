# iep2: New driver: RK3588 IEP2 deinterlacer

- Workspace branch: `opi5/iep2-7.3` (exported 2026-10-29)
- Kernel fork branch: `opi5/iep2` (see PUBLISH.md)
- Sits on: `board-sata` (base commit `5e33b74b04cf`)
- Hardware test: yes: board run 3 passes (runs 1-2 found and fixed an IOMMU fault storm)
- Next upstream step: send v1 as RFC (new uAPI controls) to linux-media
- Patches: 4 = 4 ours, 0 carried from others, 0 local-only

Apply with `git am` in the order listed in [`series`](series), on top of the parent topic (or check out the fork branch). Patch numbers are the position in that order.

## (a) Ours, intended for upstream (`ours/`)

| # | Subject | Author | Link |
|---|---|---|---|
| 0001 | media: uapi: add Rockchip IEP deinterlacer controls | Arun Iyengar |  |
| 0002 | dt-bindings: media: add Rockchip IEP2 deinterlacer | Arun Iyengar |  |
| 0003 | media: rockchip: add IEP2 deinterlacer driver | Arun Iyengar |  |
| 0004 | arm64: dts: rockchip: add IEP2 deinterlacer to RK3588 | Arun Iyengar |  |

## Notes, results and test tools

- [notes/DESIGN.md](notes/DESIGN.md)
- [notes/RESULTS.md](notes/RESULTS.md)
- [notes/board-results-run2.txt](notes/board-results-run2.txt)
- [notes/dmesg-storm1.txt](notes/dmesg-storm1.txt)
- [notes/tools/board-test.sh](notes/tools/board-test.sh)
- [notes/tools/guard.sh](notes/tools/guard.sh)
- [notes/tools/iep-test.c](notes/tools/iep-test.c)
- [notes/tools/psnrmat.c](notes/tools/psnrmat.c)
