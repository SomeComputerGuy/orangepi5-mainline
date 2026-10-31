# rkvenc-hevc: HEVC encoding for the VEPU580 driver (uses hevc-enc-uapi)

- Workspace branch: `opi5/rkvenc-hevc-7.3` (exported 2026-10-31)
- Kernel fork branch: `opi5/rkvenc-hevc` (see PUBLISH.md)
- Sits on: `rkvenc` (base commit `c12698a646ee`)
- Hardware test: not yet: compile- and KUnit-tested only
- Next upstream step: board test, then RFC together with hevc-enc-uapi
- Patches: 10 = 9 ours, 0 carried from others, 1 local-only

Apply with `git am` in the order listed in [`series`](series), on top of the parent topic (or check out the fork branch). Patch numbers are the position in that order.

## (a) Ours, intended for upstream (`ours/`)

| # | Subject | Author | Link |
|---|---|---|---|
| 0001 | media: hevc: Add H.265 syntax definitions | Arun Iyengar |  |
| 0002 | media: uapi: Add HEVC stateless encode support | Arun Iyengar |  |
| 0003 | media: hevc: Add stateless encode RBSP writer | Arun Iyengar |  |
| 0004 | media: hevc: Add KUnit tests for the stateless encode RBSP writer | Arun Iyengar |  |
| 0005 | media: hevc: Add stateless encode core | Arun Iyengar |  |
| 0006 | media: hevc: Add KUnit tests for the stateless encode core | Arun Iyengar |  |
| 0007 | media: docs: Document the HEVC stateless encode uAPI | Arun Iyengar |  |
| 0009 | media: rockchip: rkvenc: Prepare the VEPU580 helpers for a second codec | Arun Iyengar |  |
| 0010 | media: rockchip: rkvenc: Add HEVC encoding | Arun Iyengar |  |

## (c) Local only / DO NOT UPSTREAM (`local/`)

| # | Subject | Author | Link |
|---|---|---|---|
| 0008 | DO NOT UPSTREAM: media: v4l2-ctrls: Keep the v4l2-core symbol versions for HEVC encode | Arun Iyengar |  |

## Notes, results and test tools

- [notes/RESULTS.md](notes/RESULTS.md)
- [notes/board-run1-sps-patched.txt](notes/board-run1-sps-patched.txt)
- [notes/board-run1.txt](notes/board-run1.txt)
- [notes/board-run2.txt](notes/board-run2.txt)
- [notes/tools/Makefile](notes/tools/Makefile)
- [notes/tools/hevc_dump.py](notes/tools/hevc_dump.py)
- [notes/tools/psnr.sh](notes/tools/psnr.sh)
- [notes/tools/rkvenc-enc.c](notes/tools/rkvenc-enc.c)
- [notes/tools/run-tests-hevc.sh](notes/tools/run-tests-hevc.sh)
- [notes/tools/sps_patch.py](notes/tools/sps_patch.py)
- [notes/tools/sps_scaling_patch.py](notes/tools/sps_scaling_patch.py)
