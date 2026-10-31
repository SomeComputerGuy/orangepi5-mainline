# camera: MIPI-CSI camera: rkisp2 v3 series + fixups + Orange Pi 5 CAM1 sensor overlays

- Workspace branch: `opi5/camera-7.3` (exported 2026-10-31)
- Kernel fork branch: `opi5/camera` (see PUBLISH.md)
- Sits on: `board-sata` (base commit `5e33b74b04cf`)
- Hardware test: partly: no camera module attached; detection only
- Next upstream step: test with an IMX219/OV13850 module; report the fixups on the rkisp2 v3 thread
- Patches: 9 = 4 ours, 5 carried from others, 0 local-only

Apply with `git am` in the order listed in [`series`](series), on top of the parent topic (or check out the fork branch). Patch numbers are the position in that order.

## (a) Ours, intended for upstream (`ours/`)

| # | Subject | Author | Link |
|---|---|---|---|
| 0006 | media: rkisp2: Fix missing HIST_BIG2 entry in stats block info table | Arun Iyengar |  |
| 0007 | arm64: dts: rockchip: rk3588: Drop third ISP0 interrupt | Arun Iyengar |  |
| 0008 | arm64: dts: rockchip: Add IMX219 camera overlay for Orange Pi 5 CAM1 | Arun Iyengar |  |
| 0009 | arm64: dts: rockchip: Add OV13850/OV13855 overlays for Orange Pi 5 CAM1 | Arun Iyengar |  |

## (b) Carried from others, authorship kept (`carried/`)

| # | Subject | Author | Link |
|---|---|---|---|
| 0001 | media: rockchip: rkisp2: Add rkisp2 driver | Xu Hongfei | [link](https://patch.msgid.link/20260827-rkisp2-v3-1-e91ff0a604d6@ideasonboard.com) |
| 0002 | media: rkisp2: Add parameters output video node | Paul Elder | [link](https://patch.msgid.link/20260827-rkisp2-v3-2-e91ff0a604d6@ideasonboard.com) |
| 0003 | media: rkisp2: Add statistics capture video node | Paul Elder | [link](https://patch.msgid.link/20260827-rkisp2-v3-3-e91ff0a604d6@ideasonboard.com) |
| 0004 | dt-bindings: media: Add rockchip rkisp2 | Paul Elder | [link](https://patch.msgid.link/20260827-rkisp2-v3-4-e91ff0a604d6@ideasonboard.com) |
| 0005 | arm64: dts: rockchip: add ISP nodes to rk3588 | Xu Hongfei | [link](https://patch.msgid.link/20260827-rkisp2-v3-5-e91ff0a604d6@ideasonboard.com) |

## Notes, results and test tools

- [notes/RESULTS.md](notes/RESULTS.md)
- [notes/detect/rk3588s-orangepi-5-cam-detect.dtso](notes/detect/rk3588s-orangepi-5-cam-detect.dtso)
- [notes/oot-cam1-imx219.dtso](notes/oot-cam1-imx219.dtso)
