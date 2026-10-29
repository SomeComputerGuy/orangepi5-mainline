# vepu121-h264enc: H.264 stateless encode on the RK3588 VPU121 VEPU2 (hantro) on Paul Kocialkowski's H.264 encode uAPI RFC

- Workspace branch: `opi5/vepu121-h264enc` (exported 2026-10-29)
- Kernel fork branch: `opi5/vepu121-h264enc` (see PUBLISH.md)
- Sits on: `hantro-robust-mc` (base commit `e170bd977f2a`)
- Hardware test: yes: encodes on the board, decodes cleanly in FFmpeg
- Next upstream step: depends on the H.264 stateless encode uAPI landing; send as RFC follow-up
- Patches: 16 = 5 ours, 10 carried from others, 1 local-only

Apply with `git am` in the order listed in [`series`](series), on top of the parent topic (or check out the fork branch). Patch numbers are the position in that order.

## (a) Ours, intended for upstream (`ours/`)

| # | Subject | Author | Link |
|---|---|---|---|
| 0011 | media: h264: Only write the SPS and PPS of a stateless encode when they change | Arun Iyengar |  |
| 0012 | media: h264: Support picture order count type 2 in stateless encode | Arun Iyengar |  |
| 0013 | media: verisilicon: Share the H.264 CABAC context initialization table | Arun Iyengar |  |
| 0014 | media: verisilicon: Add H.264 encoding to the Rockchip VEPU2 of the RK3588 | Arun Iyengar |  |
| 0015 | arm64: dts: rockchip: Add the encoder interrupt of the RK3588 VPU121 | Arun Iyengar |  |

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

## (c) Local only / DO NOT UPSTREAM (`local/`)

| # | Subject | Author | Link |
|---|---|---|---|
| 0016 | DO NOT UPSTREAM: media: v4l2-ctrls: Keep the v4l2-core symbol versions | Arun Iyengar |  |

## Notes, results and test tools

- [notes/RESULTS.md](notes/RESULTS.md)
- [notes/tools/build-modules.sh](notes/tools/build-modules.sh)
- [notes/tools/run-tests.sh](notes/tools/run-tests.sh)
- [notes/tools/v4l2-h264-slenc.c](notes/tools/v4l2-h264-slenc.c)
