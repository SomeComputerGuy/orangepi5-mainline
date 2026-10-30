# jpeg-dec: New driver: RK3588 VDPU720 JPEG decoder (rkjpegd)

- Workspace branch: `opi5/rkjpegd-7.3` (exported 2026-10-30)
- Kernel fork branch: `opi5/jpeg-dec` (see PUBLISH.md)
- Sits on: `board-sata` (base commit `5e33b74b04cf`)
- Hardware test: yes: decodes on the board, PSNR 66-80 dB vs FFmpeg
- Next upstream step: send v1 to linux-media + devicetree
- Patches: 3 = 3 ours, 0 carried from others, 0 local-only

Apply with `git am` in the order listed in [`series`](series), on top of the parent topic (or check out the fork branch). Patch numbers are the position in that order.

## (a) Ours, intended for upstream (`ours/`)

| # | Subject | Author | Link |
|---|---|---|---|
| 0001 | dt-bindings: media: Add Rockchip VDPU720 JPEG decoder | Arun Iyengar |  |
| 0002 | media: rockchip: Add VDPU720 JPEG decoder driver | Arun Iyengar |  |
| 0003 | arm64: dts: rockchip: Add the JPEG decoder to rk3588-base | Arun Iyengar |  |

## Notes, results and test tools

- [notes/DESIGN.md](notes/DESIGN.md)
- [notes/RESULTS.md](notes/RESULTS.md)
- [notes/test/cmp.sh](notes/test/cmp.sh)
- [notes/test/gen.sh](notes/test/gen.sh)
- [notes/test/gen2.sh](notes/test/gen2.sh)
- [notes/test/jdec.c](notes/test/jdec.c)
