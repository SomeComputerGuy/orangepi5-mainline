# rkvdec-ccu: IN PROGRESS, NOT IN THE IMAGE: rkvdec decodes one stream on both RK3588 cores through the CCU (opi5/rkvdec-ccu-k4 in the workspace = the same commits on patches/linux)

- Workspace branch: `opi5/rkvdec-ccu-7.3` (exported 2026-10-30)
- Kernel fork branch: `opi5/rkvdec-ccu` (see PUBLISH.md)
- Sits on: `rkvdec-ccu-base` (base commit `866097dbb931`)
- Hardware test: in progress: HEVC 4K 130->228 fps and H.264 4K 67.6->121.4 fps bit-exact; VP9 kept off the CCU; an H.264 (interlaced/POC) fix is under test
- Next upstream step: finish the board tests and fluster, then RFC to linux-media
- Patches: 9 = 8 ours, 0 carried from others, 1 local-only

Apply with `git am` in the order listed in [`series`](series), on top of the parent topic (or check out the fork branch). Patch numbers are the position in that order.

## (a) Ours, intended for upstream (`ours/`)

| # | Subject | Author | Link |
|---|---|---|---|
| 0001 | media: v4l2-mem2mem: add v4l2_m2m_buf_detach_and_job_finish() | Arun Iyengar |  |
| 0002 | media: rkvdec: complete decode jobs independently of the m2m job | Arun Iyengar |  |
| 0003 | media: rkvdec: vdpu381: give every job its own H.264/HEVC tables | Arun Iyengar |  |
| 0004 | dt-bindings: media: rockchip: add the RK3588 video decoder CCU | Arun Iyengar |  |
| 0005 | media: rkvdec: decode one stream on both RK3588 cores with the CCU | Arun Iyengar |  |
| 0006 | arm64: dts: rockchip: add the RK3588 video decoder CCU | Arun Iyengar |  |
| 0007 | media: rkvdec: vdpu381: enable and flush the read caches for every job | Arun Iyengar |  |
| 0009 | media: rkvdec: keep interlaced H.264 off the CCU, program the POC high bits | Arun Iyengar |  |

## (c) Local only / DO NOT UPSTREAM (`local/`)

| # | Subject | Author | Link |
|---|---|---|---|
| 0008 | DEBUG: media: rkvdec: A/B module parameters for the CCU board tests | Arun Iyengar |  |

## Notes, results and test tools

- [notes/RESULTS.md](notes/RESULTS.md)
- [notes/k4/install-k4.sh](notes/k4/install-k4.sh)
- [notes/scripts/baseline.sh](notes/scripts/baseline.sh)
- [notes/scripts/build.sh](notes/scripts/build.sh)
- [notes/scripts/ccu-lib.sh](notes/scripts/ccu-lib.sh)
- [notes/scripts/ccu-verify.sh](notes/scripts/ccu-verify.sh)
- [notes/scripts/fluster.sh](notes/scripts/fluster.sh)
