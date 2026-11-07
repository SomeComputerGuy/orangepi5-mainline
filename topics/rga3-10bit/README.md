# rga3-10bit: RGA: descriptor table off-by-one and per-plane sizing fix, larger imported DMA-BUFs, NV15/P010 and rotation/flip on RGA3

- Workspace branch: `k15-rga3nv15` (exported 2026-11-07)
- Kernel fork branch: `opi5/rga3-10bit` (see PUBLISH.md)
- Sits on: `image` (base commit `bb1a61971a26`)
- Hardware test: tested on the board: 10-bit HEVC output to XRGB at 57-58 dB vs reference (BT.709 and BT.2020), all flip+rotation cases correct, v4l2-compliance 48/48 on both nodes
- Next upstream step: in the 7.3.0+opi5.16 release candidate (under test); send to linux-media
- Patches: 4 = 4 ours, 0 carried from others, 0 local-only

Apply with `git am` in the order listed in [`series`](series), on top of the parent topic (or check out the fork branch). Patch numbers are the position in that order.

## (a) Ours, intended for upstream (`ours/`)

| # | Subject | Author | Link |
|---|---|---|---|
| 0001 | media: rockchip: rga: Don't write past the end of the descriptor table | Arun Iyengar |  |
| 0002 | media: rockchip: rga: Accept imported DMA-BUFs larger than the frame | Arun Iyengar |  |
| 0003 | media: rockchip: rga: Support NV15 and P010 on the RGA3 | Arun Iyengar |  |
| 0004 | media: rockchip: rga: Support rotation and flipping on the RGA3 | Arun Iyengar |  |

## Notes, results and test tools

- [notes/HANDOFF-rga2.md](notes/HANDOFF-rga2.md)
- [notes/HANDOFF.md](notes/HANDOFF.md)
- [notes/tools/board.sh](notes/tools/board.sh)
- [notes/tools/cases.txt](notes/tools/cases.txt)
- [notes/tools/check.py](notes/tools/check.py)
- [notes/tools/judge.py](notes/tools/judge.py)
- [notes/tools/prep.py](notes/tools/prep.py)
- [notes/tools/rga-xtest.c](notes/tools/rga-xtest.c)
- [notes/tools/run.sh](notes/tools/run.sh)
