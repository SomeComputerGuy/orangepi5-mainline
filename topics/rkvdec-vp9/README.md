# rkvdec-vp9: VP9 decode on rkvdec VDPU381 (carried series + multi-core port + smaller-frame fix)

- Workspace branch: `opi5/rkvdec-vp9-7.3` (exported 2026-10-30)
- Kernel fork branch: `opi5/rkvdec-vp9` (see PUBLISH.md)
- Sits on: `multicore` (base commit `d1b5768a932b`)
- Hardware test: yes: fluster VP9 224/305 baseline, matches the series author
- Next upstream step: offer review/Tested-by on the VP9 series; send the smaller-frame fix after it lands
- Patches: 6 = 2 ours, 4 carried from others, 0 local-only

Apply with `git am` in the order listed in [`series`](series), on top of the parent topic (or check out the fork branch). Patch numbers are the position in that order.

## (a) Ours, intended for upstream (`ours/`)

| # | Subject | Author | Link |
|---|---|---|---|
| 0005 | media: rkvdec: vdpu381-vp9: adapt to the multi-core core/master split | Arun Iyengar |  |
| 0006 | media: rkvdec: vdpu381-vp9: allow frames smaller than the CAPTURE format | Arun Iyengar |  |

## (b) Carried from others, authorship kept (`carried/`)

| # | Subject | Author | Link |
|---|---|---|---|
| 0001 | media: rkvdec: vp9: Changing get_ref_buf function name to get_ref_buf_vp9 | Venkata Atchuta Bheemeswara Sarma Darbha |  |
| 0002 | media: rkvdec: Move vp9 functions to common file | Venkata Atchuta Bheemeswara Sarma Darbha |  |
| 0003 | media: rkvdec: Add VP9 support for VDPU381 variant | Venkata Atchuta Bheemeswara Sarma Darbha |  |
| 0004 | media: rkvdec: align bytesperline to 64 bytes in rkvdec_fill_decoded_pixfmt() | Igor Paunovic |  |

## Notes, results and test tools

- [notes/NOTES.md](notes/NOTES.md)
