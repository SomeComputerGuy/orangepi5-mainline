# vop2-splice: VOP2: drive modes wider than 4096 pixels by splicing video ports 0 and 1 (plus four small VOP2 fixes the feature needs)

- Workspace branch: `e8bad16014dc` (exported 2026-11-07)
- Kernel fork branch: `opi5/vop2-splice` (see PUBLISH.md)
- Sits on: `image` (base commit `bb1a61971a26`)
- Hardware test: tested on the board, camera-checked on HDMI and DP: 4K60, 4096-wide and 1080p spliced modes good, SDR/HDR10 switching good with identical HDR infoframes, 200 spliced mode transitions with 0 POST_BUF_EMPTY, 0 kernel warnings; includes raising the VOP2 ACLK to 750 MHz for modes wider than 2560 pixels. Modes wider than 4096 pixels are not tested (no such display). Open: an intermittent POST_BUF_EMPTY underrun on video port 2 after modesets (fix under test). The splice_force test parameter is not included
- Next upstream step: in the 7.3.0+opi5.16 release candidate (under test); fix the intermittent underrun
- Patches: 8 = 7 ours, 0 carried from others, 1 local-only

Apply with `git am` in the order listed in [`series`](series), on top of the parent topic (or check out the fork branch). Patch numbers are the position in that order.

## (a) Ours, intended for upstream (`ours/`)

| # | Subject | Author | Link |
|---|---|---|---|
| 0001 | drm/rockchip: vop2: Find the first mixer of a video port with Esmart3 too | Arun Iyengar |  |
| 0002 | drm/rockchip: vop2: Keep the other LUT_PORT_SEL fields on gamma LUT updates | Arun Iyengar |  |
| 0003 | drm/rockchip: vop2: Program a window from given rectangles | Arun Iyengar |  |
| 0004 | drm/rockchip: vop2: Fix the AFBC offsets of a source that starts inside a superblock | Arun Iyengar |  |
| 0005 | drm/rockchip: vop2: Set up the overlay from a list of windows | Arun Iyengar |  |
| 0006 | drm/rockchip: vop2: Splice video ports 0 and 1 for modes wider than 4096 | Arun Iyengar |  |
| 0008 | drm/rockchip: vop2: Raise ACLK for modes larger than 2560 pixels | Arun Iyengar |  |

## (c) Local only / DO NOT UPSTREAM (`local/`)

| # | Subject | Author | Link |
|---|---|---|---|
| 0007 | TEST: drm/rockchip: vop2: Add a splice_force module parameter | Arun Iyengar |  |
