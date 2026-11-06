# h264-mvc: H.264 MVC (Stereo High, two views) decoding on rkvdec VDPU381: new stateless MVC controls, reference-list change, driver

- Workspace branch: `k15-mvc` (exported 2026-11-06)
- Kernel fork branch: `opi5/h264-mvc` (see PUBLISH.md)
- Sits on: `avs2` (base commit `ae151227ff1a`)
- Hardware test: tested on the board (kernel 7.3.0-15mvc): 15 of 15 two-view JVT-MVC streams bit-exact on both views against JM 19, and 20 of 20 base views in base-only mode; no kernel warnings. No stock userspace drives it (own test client)
- Next upstream step: RFC for the uAPI; needs a userspace DPB for the second view
- Patches: 3 = 3 ours, 0 carried from others, 0 local-only

Apply with `git am` in the order listed in [`series`](series), on top of the parent topic (or check out the fork branch). Patch numbers are the position in that order.

## (a) Ours, intended for upstream (`ours/`)

| # | Subject | Author | Link |
|---|---|---|---|
| 0001 | media: uapi: h264: add stateless MVC decoding controls | Arun Iyengar |  |
| 0002 | media: v4l2-h264: Leave MVC inter-view references out of the reference lists | Arun Iyengar |  |
| 0003 | media: rkvdec: vdpu381: Add H.264 MVC (Stereo High) decoding | Arun Iyengar |  |
