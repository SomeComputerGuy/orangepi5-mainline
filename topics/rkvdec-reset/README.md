# rkvdec-reset: IN THE IMAGE (patches/linux 1801, 1802, 1804): rkvdec timeout recovery (ignore interrupts of a core without a job; reset a core whose job failed or timed out: soft reset, bus idle, CRU pulse, IOMMU reprogrammed) and rockchip-iommu log_iova() not walking a page table that a reset took away

- Workspace branch: `opi5/rkvdec-reset-7.3` (exported 2026-10-31)
- Kernel fork branch: `opi5/rkvdec-reset` (see PUBLISH.md)
- Sits on: `image-k6` (base commit `c257cc692edd`)
- Hardware test: yes: KASAN kernel, 3178 recoveries with 0 crash/KASAN/ODEBUG reports and 0 canary hits, 600/600 bit-exact after every stress step, fluster unchanged, 600 reopen cycles (notes/RESULTS.md)
- Next upstream step: send the rkvdec patches to linux-media and the iommu fix to iommu
- Patches: 4 = 4 ours, 0 carried from others, 0 local-only

Apply with `git am` in the order listed in [`series`](series), on top of the parent topic (or check out the fork branch). Patch numbers are the position in that order.

## (a) Ours, intended for upstream (`ours/`)

| # | Subject | Author | Link |
|---|---|---|---|
| 0001 | media: rkvdec: Handle interrupts of a core that has no job | Arun Iyengar |  |
| 0002 | media: rkvdec: Reset a core whose job failed or timed out | Arun Iyengar |  |
| 0003 | iommu/rockchip: Don't walk a page table that a reset took away | Arun Iyengar |  |
| 0004 | media: rkvdec: Let a timed-out core finish its job before resetting it | Arun Iyengar |  |

## Notes, results and test tools

- [notes/RESULTS.md](notes/RESULTS.md)
- [notes/rstprobe/Makefile](notes/rstprobe/Makefile)
- [notes/rstprobe/rkvdec_rstprobe.c](notes/rstprobe/rkvdec_rstprobe.c)
- [notes/rstprobe.txt](notes/rstprobe.txt)
- [notes/scripts/add-debug.py](notes/scripts/add-debug.py)
- [notes/scripts/build-kasan.sh](notes/scripts/build-kasan.sh)
- [notes/scripts/build-mod.sh](notes/scripts/build-mod.sh)
