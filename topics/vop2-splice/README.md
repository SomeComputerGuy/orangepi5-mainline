# vop2-splice: VOP2: drive modes wider than 4096 pixels by splicing video ports 0 and 1 (plus four small VOP2 fixes the feature needs)

- Workspace branch: `k15-splice~2` (exported 2026-11-05)
- Kernel fork branch: `opi5/vop2-splice` (see PUBLISH.md)
- Sits on: `image` (base commit `bb1a61971a26`)
- Hardware test: tested on the board (kernel 7.3.0-15sp3, camera-checked on HDMI and DP): 4K60, 4096 wide and 1080p spliced modes good, SDR/HDR10 switching good with identical HDR infoframes, 200 spliced mode transitions with 0 POST_BUF_EMPTY, 0 kernel warnings. A later ACLK commit and the splice_force test parameter are not included
- Next upstream step: a later ACLK change is built, not tested, and left out
- Patches: 6 = 6 ours, 0 carried from others, 0 local-only

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
