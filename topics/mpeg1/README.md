# mpeg1: MPEG-1 video decoding on the RK3588 VPU121 (hantro VDPU2) with the V4L2_PIX_FMT_MPEG1_SLICE coded format

- Workspace branch: `k15-mpeg1` (exported 2026-11-07)
- Kernel fork branch: `opi5/mpeg1` (see PUBLISH.md)
- Sits on: `image-k15` (base commit `bb1a61971a26`)
- Hardware test: tested on the board: all 5 hardware-decodable ISO/IEC 13818-4 MPEG-1 vectors and a 1080p30 stream decode, with the MPEG1_SLICE format (29/29 checks). D-pictures are not supported (no RK3588 decoder handles them)
- Next upstream step: in the 7.3.0+opi5.16 release candidate (under test)
- Patches: 6 = 6 ours, 0 carried from others, 0 local-only

Apply with `git am` in the order listed in [`series`](series), on top of the parent topic (or check out the fork branch). Patch numbers are the position in that order.

## (a) Ours, intended for upstream (`ours/`)

| # | Subject | Author | Link |
|---|---|---|---|
| 0001 | media: uapi: mpeg2: add MPEG-1 sequence and full pel flags | Arun Iyengar |  |
| 0002 | media: verisilicon: mpeg2: reject the MPEG-1 extensions of the uAPI | Arun Iyengar |  |
| 0003 | media: verisilicon: rockchip: vpu2: decode MPEG-1 | Arun Iyengar |  |
| 0004 | media: uapi: add the MPEG-1 parsed slice format | Arun Iyengar |  |
| 0005 | media: verisilicon: rockchip: vpu2: advertise MPEG-1 as V4L2_PIX_FMT_MPEG1_SLICE | Arun Iyengar |  |
| 0006 | media: uapi: mpeg2: document that D-pictures are optional | Arun Iyengar |  |
