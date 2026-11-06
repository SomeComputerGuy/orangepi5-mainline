# h1-h264-rc: H.264 encoder constant-bitrate mode reworked in the v4l2-h264-enc-rc helper (shared by Hantro H1 and VEPU580)

- Workspace branch: `k15-h1rc` (exported 2026-11-06)
- Kernel fork branch: `opi5/h1-h264-rc` (see PUBLISH.md)
- Sits on: `rkvenc-h264-rc` (base commit `338d22cfaaf5`)
- Hardware test: tested on the board (kernel 7.3.0-15h1rc2), 1080p clips at 2-16 Mbit/s: Hantro H1 mean absolute bitrate error 4.3% -> 1.1% (max 8.2% -> 2.3%), VEPU580 mean 1.6%
- Next upstream step: send with the encode uAPI series
- Patches: 2 = 2 ours, 0 carried from others, 0 local-only

Apply with `git am` in the order listed in [`series`](series), on top of the parent topic (or check out the fork branch). Patch numbers are the position in that order.

## (a) Ours, intended for upstream (`ours/`)

| # | Subject | Author | Link |
|---|---|---|---|
| 0001 | media: v4l2-h264-enc-rc: Rework the constant bitrate mode | Arun Iyengar |  |
| 0002 | media: rockchip: rkvenc: Use the CBR mode of the H.264 encode core | Arun Iyengar |  |
