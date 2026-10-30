# multicore: RGA3 and rkvdec (VDPU381) multi-core scheduling on v7.3

- Workspace branch: `opi5/multicore-7.3` (exported 2026-10-30)
- Kernel fork branch: `opi5/multicore` (see PUBLISH.md)
- Sits on: `v7.3` (base commit `c03c1a14507d`)
- Hardware test: yes: 2x 4K HEVC throughput, bit-exact vs FFmpeg, RGA3 jobs on both cores
- Next upstream step: track the posted series (RGA multi-core v2, rkvdec multi-core v2); offer Tested-by on the 7.4-rc rebase
- Patches: 22 = 0 ours, 21 carried from others, 1 local-only

Apply with `git am` in the order listed in [`series`](series), on top of the parent topic (or check out the fork branch). Patch numbers are the position in that order.

## (b) Carried from others, authorship kept (`carried/`)

| # | Subject | Author | Link |
|---|---|---|---|
| 0002 | media: rockchip: rga: zero cmdbuf in shared code | Sven Püschel |  |
| 0003 | media: rockchip: rga: add comment about pixel alignment for YUV formats | Sven Püschel |  |
| 0004 | media: rockchip: rga: move early return into if condition in vidioc_enum_fmt | Sven Püschel |  |
| 0005 | media: rockchip: rga: removed unused regmap member | Sven Püschel |  |
| 0006 | media: rockchip: rga: use devres version of pm_runtime_enable | Sven Püschel |  |
| 0007 | media: v4l2-mem2mem: drop curr_ctx member from v4l2_m2m_dev struct | Sven Püschel |  |
| 0008 | media: v4l2-mem2mem: support running multiple jobs in parallel | Sven Püschel |  |
| 0009 | media: rockchip: rga: move power handling to device_run | Sven Püschel |  |
| 0010 | media: rockchip: rga: adjust get_version to return the version | Sven Püschel |  |
| 0011 | media: rockchip: rga: add rga_core structure | Sven Püschel |  |
| 0012 | media: rockchip: rga: use components to manage multiple cores | Sven Püschel |  |
| 0013 | media: rockchip: rga: move rockchip_rga allocation to master probe | Sven Püschel |  |
| 0014 | media: rockchip: rga: move core initialization from bind to probe | Sven Püschel |  |
| 0015 | media: rockchip: rga: move video device to the master | Sven Püschel |  |
| 0016 | media: rockchip: rga: bind all cores to the master | Sven Püschel |  |
| 0017 | media: rockchip: rga: put all cores into first core iommu domain | Sven Püschel |  |
| 0018 | media: rockchip: rga: schedule jobs to multiple cores | Sven Püschel |  |
| 0019 | media: rkvdec: Keep RCB to the correct size | Detlev Casanova |  |
| 0020 | media: rkvdec: Remove unused need_reset | Detlev Casanova |  |
| 0021 | media: rkvdec: Split into core and master platform drivers | Detlev Casanova |  |
| 0022 | media: rkvdec: Add multicore support | Detlev Casanova |  |

## (c) Local only / DO NOT UPSTREAM (`local/`)

| # | Subject | Author | Link |
|---|---|---|---|
| 0001 | media: rockchip: rga, rkvdec: sync with v7.4 merge window (c339f4010) | Arun Iyengar |  |

## Notes, results and test tools

- [notes/NOTES.md](notes/NOTES.md)
