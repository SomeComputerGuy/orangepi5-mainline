# hevc-enc-rc: Encoder CBR rate control moved to a shared helper; HEVC constant bitrate mode on the VEPU580

- Workspace branch: `k15-hevcrc` (exported 2026-11-06)
- Kernel fork branch: `opi5/hevc-enc-rc` (see PUBLISH.md)
- Sits on: `h1-h264-rc` (base commit `956c85289a35`)
- Hardware test: built, NOT yet tested on hardware
- Next upstream step: board test queued
- Patches: 3 = 3 ours, 0 carried from others, 0 local-only

Apply with `git am` in the order listed in [`series`](series), on top of the parent topic (or check out the fork branch). Patch numbers are the position in that order.

## (a) Ours, intended for upstream (`ours/`)

| # | Subject | Author | Link |
|---|---|---|---|
| 0001 | media: v4l2-core: Move the H.264 encode CBR rate control to a helper | Arun Iyengar |  |
| 0002 | media: v4l2-hevc-enc: Add a constant bitrate mode | Arun Iyengar |  |
| 0003 | media: rockchip: rkvenc: Use the CBR mode of the HEVC encode core | Arun Iyengar |  |

## Notes, results and test tools

- [notes/STATE.md](notes/STATE.md)
- [notes/tools/HANDOFF.md](notes/tools/HANDOFF.md)
- [notes/tools/hevcrc-test.sh](notes/tools/hevcrc-test.sh)
- [notes/tools/hrun.sh](notes/tools/hrun.sh)
- [notes/tools/verdict.py](notes/tools/verdict.py)
