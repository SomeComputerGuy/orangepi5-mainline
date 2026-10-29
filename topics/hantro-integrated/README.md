# hantro-integrated: hantro-validate on top of hantro-robust-mc (integration branch)

- Workspace branch: `opi5/hantro-integrated` (exported 2026-10-29)
- Kernel fork branch: `opi5/hantro-integrated` (see PUBLISH.md)
- Sits on: `hantro-robust-mc` (base commit `e170bd977f2a`)
- Hardware test: integration of the above
- Next upstream step: none (integration only)
- Patches: 4 = 4 ours, 0 carried from others, 0 local-only

Apply with `git am` in the order listed in [`series`](series), on top of the parent topic (or check out the fork branch). Patch numbers are the position in that order.

## (a) Ours, intended for upstream (`ours/`)

| # | Subject | Author | Link |
|---|---|---|---|
| 0001 | media: verisilicon: Enforce a minimum CAPTURE sizeimage for the encoder | Arun Iyengar |  |
| 0002 | media: verisilicon: Keep the encoder coded size in sync with OUTPUT | Arun Iyengar |  |
| 0003 | media: verisilicon: Refuse JPEG encode jobs with inconsistent geometry | Arun Iyengar |  |
| 0004 | media: verisilicon: Report fixed JPEG colorimetry on the encoder | Arun Iyengar |  |
