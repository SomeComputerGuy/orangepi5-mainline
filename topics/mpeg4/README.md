# mpeg4: MPEG-4 Part 2, H.263 and Sorenson Spark decoding on the RK3588 VPU121 (VDPU2); uAPI from Jernej Skrabec's H616 series

- Workspace branch: `k15-mpeg4` (exported 2026-11-05)
- Kernel fork branch: `opi5/mpeg4` (see PUBLISH.md)
- Sits on: `mpeg1` (base commit `091166b16f08`)
- Hardware test: built (kernel 7.3.0-15m4v1), NOT yet tested on hardware
- Next upstream step: board test
- Patches: 3 = 1 ours, 2 carried from others, 0 local-only

Apply with `git am` in the order listed in [`series`](series), on top of the parent topic (or check out the fork branch). Patch numbers are the position in that order.

## (a) Ours, intended for upstream (`ours/`)

| # | Subject | Author | Link |
|---|---|---|---|
| 0003 | media: verisilicon: rockchip: vpu2: decode MPEG-4 Part 2, H.263 and Sorenson Spark | Arun Iyengar |  |

## (b) Carried from others, authorship kept (`carried/`)

| # | Subject | Author | Link |
|---|---|---|---|
| 0001 | media: Documentation: biblio: add ISO/IEC 14496-2 and ITU-T H.263 | Jernej Skrabec |  |
| 0002 | media: uapi: add MPEG-4 Part 2, H.263 and Sorenson Spark stateless decoder controls | Jernej Skrabec |  |
