# rga-fixes: RGA: RGA2 flip direction, RGA3 crop offset and size registers, larger userspace bytesperline, NV20 on RGA3

- Workspace branch: `k15-rgafu` (exported 2026-11-06)
- Kernel fork branch: `opi5/rga-fixes` (see PUBLISH.md)
- Sits on: `rga3-10bit` (base commit `75a7d381d88c`)
- Hardware test: tested on the board (kernel 7.3.0-15rgafu1): RGA2 flip+rotation, RGA3 crop/compose, padded 416-wide strides and NV20 cases correct, v4l2-compliance 48/48 on both nodes, no regressions
- Next upstream step: send to linux-media with rga3-10bit
- Patches: 4 = 4 ours, 0 carried from others, 0 local-only

Apply with `git am` in the order listed in [`series`](series), on top of the parent topic (or check out the fork branch). Patch numbers are the position in that order.

## (a) Ours, intended for upstream (`ours/`)

| # | Subject | Author | Link |
|---|---|---|---|
| 0001 | media: rockchip: rga: Fix the direction of the RGA2 flips | Arun Iyengar |  |
| 0002 | media: rockchip: rga: Honour the crop and compose rectangles on the RGA3 | Arun Iyengar |  |
| 0003 | media: rockchip: rga: Keep a larger bytesperline of userspace | Arun Iyengar |  |
| 0004 | media: rockchip: rga: Support NV20 on the RGA3 | Arun Iyengar |  |

## Notes, results and test tools

- [notes/HANDOFF.md](notes/HANDOFF.md)
- [notes/tools/board.sh](notes/tools/board.sh)
- [notes/tools/cases.txt](notes/tools/cases.txt)
- [notes/tools/check.py](notes/tools/check.py)
- [notes/tools/judge.py](notes/tools/judge.py)
- [notes/tools/prep-fu.py](notes/tools/prep-fu.py)
- [notes/tools/prep.py](notes/tools/prep.py)
- [notes/tools/rga-xtest.c](notes/tools/rga-xtest.c)
- [notes/tools/run.sh](notes/tools/run.sh)
