# rkvenc: VEPU580 (rkvenc) V4L2 stateless H.264 encoder driver

- Workspace branch: `opi5/rkvenc-7.3` (exported 2026-10-30)
- Kernel fork branch: `opi5/rkvenc` (see PUBLISH.md)
- Sits on: `board-sata` (base commit `5e33b74b04cf`)
- Hardware test: yes: working on the board, both cores in parallel, 0 decode errors
- Next upstream step: RFC to linux-media after the H.264 encode uAPI; cover letter draft included
- Patches: 13 = 5 ours, 7 carried from others, 1 local-only

Apply with `git am` in the order listed in [`series`](series), on top of the parent topic (or check out the fork branch). Patch numbers are the position in that order.

## (a) Ours, intended for upstream (`ours/`)

| # | Subject | Author | Link |
|---|---|---|---|
| 0008 | media: h264: Only write the SPS and PPS of a stateless encode when they change | Arun Iyengar |  |
| 0009 | media: h264: Support picture order count type 2 in stateless encode | Arun Iyengar |  |
| 0011 | dt-bindings: media: Add the Rockchip VEPU580 video encoder | Arun Iyengar |  |
| 0012 | media: rockchip: Add a VEPU580 stateless video encoder driver | Arun Iyengar |  |
| 0013 | arm64: dts: rockchip: Add the VEPU580 encoder cores to the RK3588 | Arun Iyengar |  |

## (b) Carried from others, authorship kept (`carried/`)

| # | Subject | Author | Link |
|---|---|---|---|
| 0001 | media: h264: Add a more generic reflist builder init | Paul Kocialkowski | [link](https://patch.msgid.link/20260522101653.2565125-2-paulk@sys-base.io) |
| 0002 | media: uapi: Add H.264 stateless encode support | Paul Kocialkowski | [link](https://patch.msgid.link/20260522101653.2565125-3-paulk@sys-base.io) |
| 0003 | media: h264: Add SPS video definitions | Paul Kocialkowski | [link](https://patch.msgid.link/20260522101653.2565125-4-paulk@sys-base.io) |
| 0004 | media: h264: Add stateless encode core | Paul Kocialkowski | [link](https://patch.msgid.link/20260522101653.2565125-5-paulk@sys-base.io) |
| 0005 | media: h264: Add stateless encode rbsp | Paul Kocialkowski | [link](https://patch.msgid.link/20260522101653.2565125-6-paulk@sys-base.io) |
| 0006 | media: h264: Add stateless encode reference management | Paul Kocialkowski | [link](https://patch.msgid.link/20260522101653.2565125-7-paulk@sys-base.io) |
| 0007 | media: h264: Add stateless encode rate control | Paul Kocialkowski | [link](https://patch.msgid.link/20260522101653.2565125-8-paulk@sys-base.io) |

## (c) Local only / DO NOT UPSTREAM (`local/`)

| # | Subject | Author | Link |
|---|---|---|---|
| 0010 | DO NOT UPSTREAM: media: v4l2-ctrls: Keep the v4l2-core symbol versions | Arun Iyengar |  |

## Notes, results and test tools

- [notes/RESULTS.md](notes/RESULTS.md)
- [notes/board-run1.txt](notes/board-run1.txt)
- [notes/board-run2.txt](notes/board-run2.txt)
- [cover-letter.txt](cover-letter.txt)
- [notes/tools/Makefile](notes/tools/Makefile)
- [notes/tools/psnr.sh](notes/tools/psnr.sh)
- [notes/tools/rkvenc-enc.c](notes/tools/rkvenc-enc.c)
- [notes/tools/run-tests.sh](notes/tools/run-tests.sh)
