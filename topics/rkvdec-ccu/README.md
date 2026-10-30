# rkvdec-ccu: IN PROGRESS, NOT IN THE IMAGE: rkvdec decodes one stream on both RK3588 cores through the CCU, including VP9 (hardware probability adaptation) and field/MBAFF H.264 (field pairs on both cores); on the image-k6 stack, planned as patches/linux 1601-1614

- Workspace branch: `opi5/rkvdec-ccu-k6-7.3` (exported 2026-10-30)
- Kernel fork branch: `opi5/rkvdec-ccu` (see PUBLISH.md)
- Sits on: `image-k6` (base commit `996168d5c3b1`)
- Hardware test: in progress: earlier build HEVC 4K 130->228 fps and H.264 4K 67.6->121.4 fps bit-exact; this series (reset-all-cores-once-idle, VP9/field on the CCU) awaits board validation (ccu-repro, fluster, ccu-verify)
- Next upstream step: finish the board tests and fluster, then RFC to linux-media
- Patches: 14 = 14 ours, 0 carried from others, 0 local-only

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
| 0008 | media: rkvdec: vdpu381: program the H.264 POC high bits for the CCU | Arun Iyengar |  |
| 0009 | media: rkvdec: vdpu381: reset failed cores, don't let POC aliases deadlock the CCU | Arun Iyengar |  |
| 0010 | media: v4l2-mem2mem: let detached jobs hold the capture buffer | Arun Iyengar |  |
| 0011 | media: rkvdec: decode the two fields of a frame on both cores | Arun Iyengar |  |
| 0012 | media: rkvdec: vdpu381: adapt the VP9 probabilities in hardware | Arun Iyengar |  |
| 0013 | media: rkvdec: vdpu381: decode VP9 on both RK3588 cores with the CCU | Arun Iyengar |  |
| 0014 | media: rkvdec: vdpu381: reset the cores together once they are idle | Arun Iyengar |  |

## Notes, results and test tools

- [notes/RESULTS.md](notes/RESULTS.md)
- [notes/fieldpair/NOTES.md](notes/fieldpair/NOTES.md)
- [notes/k4/install-k4.sh](notes/k4/install-k4.sh)
- [notes/k5e/install.sh](notes/k5e/install.sh)
- [notes/scripts/baseline.sh](notes/scripts/baseline.sh)
- [notes/scripts/build.sh](notes/scripts/build.sh)
- [notes/scripts/ccu-lib.sh](notes/scripts/ccu-lib.sh)
- [notes/scripts/ccu-repro.sh](notes/scripts/ccu-repro.sh)
- [notes/scripts/ccu-verify.sh](notes/scripts/ccu-verify.sh)
- [notes/scripts/fluster.sh](notes/scripts/fluster.sh)
- [notes/scripts/hhi-ab.sh](notes/scripts/hhi-ab.sh)
- [notes/vp9hw/NOTES.md](notes/vp9hw/NOTES.md)
- [notes/vp9hw/harness/build.sh](notes/vp9hw/harness/build.sh)
- [notes/vp9hw/harness/gen/coef.c](notes/vp9hw/harness/gen/coef.c)
- [notes/vp9hw/harness/gen/invmap.c](notes/vp9hw/harness/gen/invmap.c)
- [notes/vp9hw/harness/gen/kern_tbl.c](notes/vp9hw/harness/gen/kern_tbl.c)
- [notes/vp9hw/harness/gen/mpp_bitput.c](notes/vp9hw/harness/gen/mpp_bitput.c)
- [notes/vp9hw/harness/gen/mpp_tbl.c](notes/vp9hw/harness/gen/mpp_tbl.c)
- [notes/vp9hw/harness/gen/v4l2_tbl.c](notes/vp9hw/harness/gen/v4l2_tbl.c)
- [notes/vp9hw/harness/gen/v4l2_vp9_types.h](notes/vp9hw/harness/gen/v4l2_vp9_types.h)
- [notes/vp9hw/harness/harness.h](notes/vp9hw/harness/harness.h)
- [notes/vp9hw/harness/kern_shim.h](notes/vp9hw/harness/kern_shim.h)
- [notes/vp9hw/harness/main_kern.c](notes/vp9hw/harness/main_kern.c)
- [notes/vp9hw/harness/main_mpp.c](notes/vp9hw/harness/main_mpp.c)
- [notes/vp9hw/harness/mpp_shim.h](notes/vp9hw/harness/mpp_shim.h)
