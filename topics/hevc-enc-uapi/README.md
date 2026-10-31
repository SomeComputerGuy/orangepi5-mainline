# hevc-enc-uapi: Proposed V4L2 HEVC stateless encode uAPI + helpers + KUnit tests

- Workspace branch: `opi5/hevc-enc-uapi` (exported 2026-10-31)
- Kernel fork branch: `opi5/hevc-enc-uapi` (see PUBLISH.md)
- Sits on: `board-sata` (base commit `5e33b74b04cf`)
- Hardware test: not applicable (uAPI); KUnit passes
- Next upstream step: RFC to linux-media; cover letter draft included
- Patches: 19 = 9 ours, 10 carried from others, 0 local-only

Apply with `git am` in the order listed in [`series`](series), on top of the parent topic (or check out the fork branch). Patch numbers are the position in that order.

## (a) Ours, intended for upstream (`ours/`)

| # | Subject | Author | Link |
|---|---|---|---|
| 0011 | media: h264: Only write the SPS and PPS of a stateless encode when they change | Arun Iyengar |  |
| 0012 | media: h264: Support picture order count type 2 in stateless encode | Arun Iyengar |  |
| 0013 | media: hevc: Add H.265 syntax definitions | Arun Iyengar |  |
| 0014 | media: uapi: Add HEVC stateless encode support | Arun Iyengar |  |
| 0015 | media: hevc: Add stateless encode RBSP writer | Arun Iyengar |  |
| 0016 | media: hevc: Add KUnit tests for the stateless encode RBSP writer | Arun Iyengar |  |
| 0017 | media: hevc: Add stateless encode core | Arun Iyengar |  |
| 0018 | media: hevc: Add KUnit tests for the stateless encode core | Arun Iyengar |  |
| 0019 | media: docs: Document the HEVC stateless encode uAPI | Arun Iyengar |  |

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
| 0008 | media: verisilicon: Report default pixel coding for non-JPEG and fix JPEG case | Paul Kocialkowski | [link](https://patch.msgid.link/20260522101653.2565125-9-paulk@sys-base.io) |
| 0009 | media: hantro: use hantro_decoded_buffer only for dst_vq | Marco Felsch | [link](https://patch.msgid.link/20260522101653.2565125-11-paulk@sys-base.io) |
| 0010 | media: verisilicon: Add common encoder parm and frameintervals ioctls | Paul Kocialkowski | [link](https://patch.msgid.link/20260522101653.2565125-12-paulk@sys-base.io) |

## Notes, results and test tools

- [cover-letter.txt](cover-letter.txt)
- [notes/DESIGN.md](notes/DESIGN.md)
- [notes/FOR-DRIVER.md](notes/FOR-DRIVER.md)
- [notes/tools/hevc_ref.py](notes/tools/hevc_ref.py)
- [notes/tools/rst_check.py](notes/tools/rst_check.py)
- [notes/tools/vectors-trace.txt](notes/tools/vectors-trace.txt)
