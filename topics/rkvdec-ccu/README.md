# rkvdec-ccu: IN PROGRESS, NOT IN THE IMAGE: rkvdec decodes one stream on both RK3588 cores through the CCU, including VP9 (hardware probability adaptation) and field/MBAFF H.264 (field pairs on both cores); rebased on the rkvdec-reset timeout recovery (planned as patches/linux 1601-1616)

- Workspace branch: `opi5/rkvdec-reset-ccu-7.3` (exported 2026-10-30)
- Kernel fork branch: `opi5/rkvdec-ccu` (see PUBLISH.md)
- Sits on: `rkvdec-reset` (base commit `ef49dbd97305`)
- Hardware test: in progress: earlier builds bit-exact (fluster identical to single-core, 600/600, HEVC 4K 130->227 fps, H.264 67->121 fps); the P4 board proof of this rebased series (KASAN kernel, recovery stress) is running
- Next upstream step: finish the P4 board proof and fluster, then RFC to linux-media
- Patches: 16 = 16 ours, 0 carried from others, 0 local-only

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
| 0009 | media: rkvdec: vdpu381: reset failed cores in the CCU, avoid POC alias deadlocks | Arun Iyengar |  |
| 0010 | media: v4l2-mem2mem: let detached jobs hold the capture buffer | Arun Iyengar |  |
| 0011 | media: rkvdec: decode the two fields of a frame on both cores | Arun Iyengar |  |
| 0012 | media: rkvdec: vdpu381: adapt the VP9 probabilities in hardware | Arun Iyengar |  |
| 0013 | media: rkvdec: vdpu381: decode VP9 on both RK3588 cores with the CCU | Arun Iyengar |  |
| 0014 | media: rkvdec: vdpu381: reset the cores together once they are idle | Arun Iyengar |  |
| 0015 | media: rkvdec: fix two races around job completion and core resets | Arun Iyengar |  |
| 0016 | media: rkvdec: vdpu381: sync H.264 field and frame pictures across cores correctly | Arun Iyengar |  |

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
- [notes/scripts/fm.sh](notes/scripts/fm.sh)
- [notes/scripts/fmfm.sh](notes/scripts/fmfm.sh)
- [notes/scripts/h3b.sh](notes/scripts/h3b.sh)
- [notes/scripts/hhi-ab.sh](notes/scripts/hhi-ab.sh)
- [notes/scripts/reopen.sh](notes/scripts/reopen.sh)
- [notes/scripts/stopcore-01ed182a.py](notes/scripts/stopcore-01ed182a.py)
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
