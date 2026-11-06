# venc-8k: VEPU580: encode pictures wider than 4096 pixels (external line buffer)

- Workspace branch: `k15-venc8k` (exported 2026-11-06)
- Kernel fork branch: `opi5/venc-8k` (see PUBLISH.md)
- Sits on: `hevc-enc-rc` (base commit `4a63c9b23492`)
- Hardware test: built, NOT yet tested on hardware
- Next upstream step: board test queued
- Patches: 1 = 1 ours, 0 carried from others, 0 local-only

Apply with `git am` in the order listed in [`series`](series), on top of the parent topic (or check out the fork branch). Patch numbers are the position in that order.

## (a) Ours, intended for upstream (`ours/`)

| # | Subject | Author | Link |
|---|---|---|---|
| 0001 | media: rockchip: rkvenc: Encode pictures wider than 4096 pixels | Arun Iyengar |  |

## Notes, results and test tools

- [notes/tools/HANDOFF.md](notes/tools/HANDOFF.md)
- [notes/tools/v8run.sh](notes/tools/v8run.sh)
- [notes/tools/venc8k-test.sh](notes/tools/venc8k-test.sh)
- [notes/tools/verdict.py](notes/tools/verdict.py)
