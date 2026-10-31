# hantro-validate: Hantro JPEG encoder input validation

- Workspace branch: `opi5/hantro-validate` (exported 2026-10-31)
- Kernel fork branch: `opi5/hantro-validate` (see PUBLISH.md)
- Sits on: `multicore` (base commit `d1b5768a932b`)
- Hardware test: see TESTING.md
- Next upstream step: send to linux-media
- Patches: 4 = 4 ours, 0 carried from others, 0 local-only

Apply with `git am` in the order listed in [`series`](series), on top of the parent topic (or check out the fork branch). Patch numbers are the position in that order.

## (a) Ours, intended for upstream (`ours/`)

| # | Subject | Author | Link |
|---|---|---|---|
| 0001 | media: verisilicon: Enforce a minimum CAPTURE sizeimage for the encoder | Arun Iyengar |  |
| 0002 | media: verisilicon: Keep the encoder coded size in sync with OUTPUT | Arun Iyengar |  |
| 0003 | media: verisilicon: Refuse JPEG encode jobs with inconsistent geometry | Arun Iyengar |  |
| 0004 | media: verisilicon: Report fixed JPEG colorimetry on the encoder | Arun Iyengar |  |

## Notes, results and test tools

- [notes/TESTING.md](notes/TESTING.md)
