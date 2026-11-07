# iep2-first-ts: IEP2 field-rate mode: time the second field of the first frame from the next input buffer

- Workspace branch: `k15-iepts` (exported 2026-11-07)
- Kernel fork branch: `opi5/iep2-first-ts` (see PUBLISH.md)
- Sits on: `iep2-std-deint` (base commit `6e3ad41adda3`)
- Hardware test: tested on the board: output identical in 72 of 72 cases, timestamps exact when two buffers are queued before STREAMON, v4l2-compliance 57/57
- Next upstream step: in the 7.3.0+opi5.16 release candidate (under test); fold into the IEP2 driver series
- Patches: 1 = 1 ours, 0 carried from others, 0 local-only

Apply with `git am` in the order listed in [`series`](series), on top of the parent topic (or check out the fork branch). Patch numbers are the position in that order.

## (a) Ours, intended for upstream (`ours/`)

| # | Subject | Author | Link |
|---|---|---|---|
| 0001 | media: rockchip: iep: time the first frame's second field from the next input | Arun Iyengar |  |
