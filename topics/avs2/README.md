# avs2: AVS2 (GB/T 33475.2) stateless decoding on the RK3588 rkvdec (VDPU381): new uAPI pixel format and controls, rkvdec backend

- Workspace branch: `k15-avs2` (exported 2026-11-07)
- Kernel fork branch: `opi5/avs2` (see PUBLISH.md)
- Sits on: `image` (base commit `bb1a61971a26`)
- Hardware test: tested on the board: bit-exact on the 12 PKU AVS2 conformance streams (416x240 to 1080p) and 5 xavs2 streams (1080p, 2160p); v4l2-compliance 56/57 (the VIDIOC_DECODER_CMD test needs a v4l-utils that knows AVS2). Not tested: weighting quant and background pictures (no streams); field coding is refused
- Next upstream step: in the 7.3.0+opi5.16 release candidate (under test); needs an AVS2 userspace client (FFmpeg hwaccel) before posting
- Patches: 2 = 2 ours, 0 carried from others, 0 local-only

Apply with `git am` in the order listed in [`series`](series), on top of the parent topic (or check out the fork branch). Patch numbers are the position in that order.

## (a) Ours, intended for upstream (`ours/`)

| # | Subject | Author | Link |
|---|---|---|---|
| 0001 | media: uapi: add AVS2 stateless decoder pixel format and controls | Arun Iyengar |  |
| 0002 | media: rkvdec: add AVS2 decoding on VDPU381 | Arun Iyengar |  |
