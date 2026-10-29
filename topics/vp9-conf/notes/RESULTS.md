# VDPU381 VP9: the 7 unexplained conformance failures

Branch `opi5/vp9-conf-7.3` (worktree `work/vp9-conf-7.3`), on top of `opi5/rkvdec-vp9-7.3`.
Module: `rockchip-vdec.ko.fix1` (sha256 4ecd49fa…), built against the board kernel (7.3.0-opi5).

## Method
- `cmpvp9.sh <vector>` (on the board): decodes with fluster's pipeline (`parsebin ! v4l2slvp9dec !
  videoconvert dither=none ! I420 ! filesink`) and with ffmpeg libvpx-vp9, then `cmp.py` compares
  frame by frame. GStreamer pads I420 strides to 4 bytes, so `cmp.py` crops them (my first version
  didn't, which made segkey_adpq (852 wide) look like it failed from frame 0).
- `sumhdr.py`: one line per coded frame from `ffmpeg -bsf:v trace_headers` (decode/display index,
  frame type, show_frame, refresh flags, loop-filter deltas, segmentation flags and features).
- References: MPP `hal_vdpu34x_vp9d.c` / `vdpu34x_com.h` (register meaning only), the RK3399 backend,
  GStreamer 1.28 `gstv4l2codecvp9dec.c` / `gstvp9decoder.c`.

## Root causes

### 1. Register set never cleared (lf_deltas; also stale segment features)
The register set lives in `rkvdec_vp9_ctx` and is never cleared between frames. reg94 (ref deltas)
and reg75 (mode deltas) are filled with `|=`, so after the deltas change the hardware gets
OR(old, new). vp90-2-09-lf_deltas: frame #4 changes ref deltas {1,0,-1,-1} -> {2,0,-2,-2} and mode
deltas {0,0} -> {-2,2}. #5 has the deltas disabled and decodes correctly. #6 is the first frame
after that to use them, and the first one to mismatch (display 5). Every later frame using deltas
is wrong too (25/30 frames). The per-segment feature enable bits in reg67-74 are only ever set,
never cleared.
Fix: `memset(regs, 0, ...)` per frame, as the VDPU381 H.264 and HEVC backends already do (commit 1).

### 2. Segmentation map ping-pong (aq2, skip, skip-01, skip-02; likely segkey_adpq)
The hardware reads the persistent segment map from `segidlast` and writes the current one to
`segidcur`. The RK3399-derived rule swapped the buffers before inter frames with seg disabled or
update_map=1, and otherwise left `segidlast` on the *older* map. So every update_map=0 frame read
the map from before the most recent update. Evidence: in each vector the first bad frame is the
first update_map=0 frame right after an update_map=1 frame:
- skip: #1 codes a map with SEG_LVL_SKIP on segment 1 (good). #2 is update_map=0 and is the first bad frame.
- skip-01: #4 update_map=1 (good), #5 update_map=0 is the first bad frame.
- aq2: #1 (hidden) update_map=1 temporal, #2 update_map=0 is the first bad frame (display 1).
- skip-02: same at #2. It also has a seg-disabled frame (#4) followed by update_map=0 frames, and
  update_map=0 frames after a seg-disabled key frame (#8).
- segkey_adpq: first bad display frame 6 = #8, the update_map=0 frame after hidden #7, which
  updates the map with temporal prediction.

Fix (commit 2), following MPP's VDPU34x HAL: `segidlast` always points to the latest map. The maps
swap only after a frame that produces a new map: (seg enabled and update_map), intra-only/key,
error resilient, or a size change. Those frames set reg75 bit 15 `vp9_segment_id_update`
(bits 14/15 were "reserved" in the kernel header). `segmentation_enable_lstframe` is now "seg was
enabled on some frame since the last intra frame", not "on the previous frame", because the map
survives seg-disabled frames. The previous frame size is now kept in the context for
`last_widhheight_eqcur`, rather than read from a CAPTURE buffer userspace may already have reused.

### 3. vp90-2-22-svc_1280x720_3.ivf: not a kernel bug (GStreamer + spec feature)
Each superframe holds 3 spatial layers: 320x180 (key, then inter), 640x360, 1280x720. All have
show_frame=1 and the larger layers are inter frames predicting from the smaller ones (scaled
reference, larger than the CAPTURE buffers). GStreamer's GstVp9Decoder logs "Drop frame on
non-keyframe format change" on the first 640x360 frame (v4l2slvp9dec doesn't set
`support_non_kf_change`) and then "Drop frame before initial keyframe" for the remaining 58
frames. The stream has only one key frame, so it ends with "No valid frames decoded" (fluster ☠).
This is the same class as the 26 resize_inter vectors. It also needs CAPTURE buffers sized for
the largest layer, and libvpx outputs only the last frame of each superframe, whereas GStreamer
would output all three layers. Fixing it needs the GStreamer work in `_out/rkvdec-vp9/NOTES.md`
plus that output behaviour. The kernel already decodes frames smaller than the CAPTURE format.

## Before / after
| vector | before (first bad display frame) | after |
|---|---|---|
| vp90-2-09-lf_deltas | FAIL (5; 25/30 bad) | PASS |
| vp90-2-09-aq2 | FAIL (1; 98/100 bad) | PASS |
| vp90-2-15-segkey_adpq | FAIL (6; 144/150 bad) | PASS |
| vp90-2-19-skip | FAIL (2; 58/60) | PASS |
| vp90-2-19-skip-01 | FAIL (5; 55/60) | PASS |
| vp90-2-19-skip-02 | FAIL (2; 6/12) | PASS |
| vp90-2-22-svc_1280x720_3 | ERROR (GStreamer drops every frame) | unchanged (GStreamer) |

Fluster (`-j2`, the same as the baseline): before 224/305, after **230/305** (+6, no regressions; diff against
`~/vp9conf/after-resize-patch.md` on the board shows only the 6 vectors flipping to pass). Board results:
`~/vp9conf/fix1.md`, `fix1.log`.
Note: at `-j4`, 14 vp90-2-14-resize-fp-tiles vectors fail with "dma alloc of size 16-18 MB failed"
(CMA exhaustion with four parallel high-resolution decoders). They pass at `-j1`/`-j2`. This is
unrelated to these changes: always run fluster at `-j2` or lower on this board.

## Not fixed / notes
- Previous-frame MVs (`vp9_refcolmv_base`) live in the previous frame's CAPTURE buffer. If that frame
  is not a reference (refresh_frame_flags=0) and is shown, userspace may reuse the buffer before
  the next frame reads its MVs. No failing vector shows this; MPP uses separate per-slot MV
  buffers. A possible follow-up is a driver-owned MV ping-pong buffer.
- The RK3399 backend (`rkvdec-vp9.c`) uses the same segment-map swap rule. MPP's RK3399 HAL swaps
  only on (enabled && update_map). Not touched here (different hardware, can't test).
