# vp9-conf: VDPU381 VP9 conformance fixes (register reset per frame, segmentation map)

- Workspace branch: `opi5/vp9-conf-7.3` (exported 2026-10-29)
- Kernel fork branch: `opi5/vp9-conf` (see PUBLISH.md)
- Sits on: `rkvdec-vp9` (base commit `afe2d3426baf`)
- Hardware test: yes: fixed vectors verified on the board
- Next upstream step: send as fixes on top of the VP9 series
- Patches: 2 = 2 ours, 0 carried from others, 0 local-only

Apply with `git am` in the order listed in [`series`](series), on top of the parent topic (or check out the fork branch). Patch numbers are the position in that order.

## (a) Ours, intended for upstream (`ours/`)

| # | Subject | Author | Link |
|---|---|---|---|
| 0001 | media: rkvdec: vdpu381-vp9: reset the register set for every frame | Arun Iyengar |  |
| 0002 | media: rkvdec: vdpu381-vp9: fix segmentation map handling | Arun Iyengar |  |

## Notes, results and test tools

- [notes/RESULTS.md](notes/RESULTS.md)
- [notes/cmp.py](notes/cmp.py)
- [notes/cmpvp9.sh](notes/cmpvp9.sh)
- [notes/fluster-fix1.md](notes/fluster-fix1.md)
- [notes/sumhdr.py](notes/sumhdr.py)
