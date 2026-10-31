# rkvdec-ccu-base: Base for rkvdec-ccu: the three codec-quality rkvdec commits

- Workspace branch: `opi5/rkvdec-ccu-base-7.3` (exported 2026-10-31)
- Kernel fork branch: `opi5/rkvdec-ccu-base` (see PUBLISH.md)
- Sits on: `integration` (base commit `1afa8d268718`)
- Hardware test: via codec-quality
- Next upstream step: none (base only)
- Patches: 3 = 3 ours, 0 carried from others, 0 local-only

Apply with `git am` in the order listed in [`series`](series), on top of the parent topic (or check out the fork branch). Patch numbers are the position in that order.

## (a) Ours, intended for upstream (`ours/`)

| # | Subject | Author | Link |
|---|---|---|---|
| 0001 | media: rkvdec: vdpu381: Compress the co-located motion vectors of H.264 | Arun Iyengar |  |
| 0002 | media: rkvdec: vdpu381: Compress the co-located motion vectors of HEVC | Arun Iyengar |  |
| 0003 | media: rkvdec: Give the HEVC SPS control a default the driver accepts | Arun Iyengar |  |
