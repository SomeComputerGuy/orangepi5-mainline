# rkvenc-h264-rc: VEPU580 H.264: SPS/PPS nal_ref_idc fix, a frame-level CBR rate control modelled on MPP behaviour, no adaptive QP with the row rate control, moving-scene RDO tuning

- Workspace branch: `k15-vencrc` (exported 2026-11-07)
- Kernel fork branch: `opi5/rkvenc-h264-rc` (see PUBLISH.md)
- Sits on: `image` (base commit `bb1a61971a26`)
- Hardware test: tested on the board with GStreamer v4l2slh264enc, 1080p and 4K clips at 2-40 Mbit/s: bitrate error from -2.8..-9.4% to -0.6..+2.5%, PSNR-Y +0.7 to +3.6 dB at 1080p
- Next upstream step: in the 7.3.0+opi5.16 release candidate (under test); send to linux-media with the encoder series
- Patches: 4 = 4 ours, 0 carried from others, 0 local-only

Apply with `git am` in the order listed in [`series`](series), on top of the parent topic (or check out the fork branch). Patch numbers are the position in that order.

## (a) Ours, intended for upstream (`ours/`)

| # | Subject | Author | Link |
|---|---|---|---|
| 0001 | media: h264: Write the stateless encode SPS and PPS with nal_ref_idc 3 | Arun Iyengar |  |
| 0002 | media: rockchip: rkvenc: Add a CBR frame rate control for H.264 | Arun Iyengar |  |
| 0003 | media: rockchip: rkvenc: Don't enable adaptive QP with the row rate control | Arun Iyengar |  |
| 0004 | media: rockchip: rkvenc: Use MPP's moving-scene H.264 RDO tuning | Arun Iyengar |  |
