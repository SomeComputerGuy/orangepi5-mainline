# v7.4-rkvdec-vp9: 7.4 base: VDPU381 VP9 series as posted

- Workspace branch: `opi5/rkvdec-vp9` (exported 2026-10-29)
- Kernel fork branch: `opi5/v7.4-rkvdec-vp9` (see PUBLISH.md)
- Sits on: `c339f4010` (base commit `c339f4010dea`)
- Hardware test: via rkvdec-vp9 (v7.3)
- Next upstream step: rebase onto 7.4-rc1
- Patches: 4 = 0 ours, 4 carried from others, 0 local-only

Apply with `git am` in the order listed in [`series`](series), on top of the parent topic (or check out the fork branch). Patch numbers are the position in that order.

## (b) Carried from others, authorship kept (`carried/`)

| # | Subject | Author | Link |
|---|---|---|---|
| 0001 | media: rkvdec: vp9: Changing get_ref_buf function name to get_ref_buf_vp9 | Venkata Atchuta Bheemeswara Sarma Darbha |  |
| 0002 | media: rkvdec: Move vp9 functions to common file | Venkata Atchuta Bheemeswara Sarma Darbha |  |
| 0003 | media: rkvdec: Add VP9 support for VDPU381 variant | Venkata Atchuta Bheemeswara Sarma Darbha |  |
| 0004 | media: rkvdec: align bytesperline to 64 bytes in rkvdec_fill_decoded_pixfmt() | Igor Paunovic |  |
