# v7.4-rkisp2: 7.4 base: rkisp2 series

- Workspace branch: `opi5/rkisp2` (exported 2026-10-30)
- Kernel fork branch: `opi5/v7.4-rkisp2` (see PUBLISH.md)
- Sits on: `c339f4010` (base commit `c339f4010dea`)
- Hardware test: via camera (v7.3)
- Next upstream step: rebase onto 7.4-rc1
- Patches: 7 = 2 ours, 5 carried from others, 0 local-only

Apply with `git am` in the order listed in [`series`](series), on top of the parent topic (or check out the fork branch). Patch numbers are the position in that order.

## (a) Ours, intended for upstream (`ours/`)

| # | Subject | Author | Link |
|---|---|---|---|
| 0006 | media: rkisp2: Adapt set_fmt pad op to the v4l2_subdev_client_info argument | Arun Iyengar |  |
| 0007 | media: rkisp2: Fix missing HIST_BIG2 entry in stats block info table | Arun Iyengar |  |

## (b) Carried from others, authorship kept (`carried/`)

| # | Subject | Author | Link |
|---|---|---|---|
| 0001 | media: rockchip: rkisp2: Add rkisp2 driver | Xu Hongfei | [link](https://patch.msgid.link/20260827-rkisp2-v3-1-e91ff0a604d6@ideasonboard.com) |
| 0002 | media: rkisp2: Add parameters output video node | Paul Elder | [link](https://patch.msgid.link/20260827-rkisp2-v3-2-e91ff0a604d6@ideasonboard.com) |
| 0003 | media: rkisp2: Add statistics capture video node | Paul Elder | [link](https://patch.msgid.link/20260827-rkisp2-v3-3-e91ff0a604d6@ideasonboard.com) |
| 0004 | dt-bindings: media: Add rockchip rkisp2 | Paul Elder | [link](https://patch.msgid.link/20260827-rkisp2-v3-4-e91ff0a604d6@ideasonboard.com) |
| 0005 | arm64: dts: rockchip: add ISP nodes to rk3588 | Xu Hongfei | [link](https://patch.msgid.link/20260827-rkisp2-v3-5-e91ff0a604d6@ideasonboard.com) |
