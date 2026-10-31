# dsi: MIPI DSI LCD: ili9881c Innolux AFJ101-BA2131 panel, dsi2 sentinel fix, LCD overlays

- Workspace branch: `opi5/dsi-7.3` (exported 2026-10-31)
- Kernel fork branch: `opi5/dsi` (see PUBLISH.md)
- Sits on: `board-sata` (base commit `5e33b74b04cf`)
- Hardware test: not yet: no panel attached
- Next upstream step: the dsi2 sentinel fix can go now; panel + overlays after a panel test
- Patches: 4 = 4 ours, 0 carried from others, 0 local-only

Apply with `git am` in the order listed in [`series`](series), on top of the parent topic (or check out the fork branch). Patch numbers are the position in that order.

## (a) Ours, intended for upstream (`ours/`)

| # | Subject | Author | Link |
|---|---|---|---|
| 0001 | dt-bindings: display: panel: ilitek,ili9881c: Add Innolux AFJ101-BA2131 | Arun Iyengar |  |
| 0002 | drm/panel: ilitek-ili9881c: Add Innolux AFJ101-BA2131 support | Arun Iyengar |  |
| 0003 | drm/rockchip: dsi2: Add missing sentinel to the RK3588 chip data | Arun Iyengar |  |
| 0004 | arm64: dts: rockchip: Add Orange Pi 5 MIPI LCD overlays | Arun Iyengar |  |

## Notes, results and test tools

- [notes/RESULTS.md](notes/RESULTS.md)
