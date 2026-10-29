# VP9 on RK3588 rkvdec (VDPU381) — status and follow-ups

## Branch
`opi5/rkvdec-vp9-7.3` (worktree `work/rkvdec-vp9-7.3`), on top of `opi5/multicore-7.3`:
- "media: rkvdec: Add VP9 support for VDPU381 variant" series (v1, 2026-07-26, Venkata Atchuta
  Bheemeswara Sarma Darbha; not in linux-next) + Igor Paunovic's bytesperline-64 fix.
- Local: port of the VP9 backend to the multi-core core/master split.
- Local: accept inter-frame resolution changes that fit the allocated CAPTURE buffers (see below).

Board: `/lib/modules/7.3.0-opi5/updates/opi5-multicore/rockchip-vdec.ko`. Previous modules kept at
`/var/tmp/rockchip-vdec.ko.multicore-only` and `/var/tmp/rockchip-vdec.ko.vp9-v1`.

## Conformance (fluster 0.7.1 from Ubuntu, GStreamer-VP9-V4L2SL, VP9-TEST-VECTORS)
Baseline with multi-core + VP9: **224/305**, identical to the series author's result.
Failures: 46 frames < 64x64 and 2 non-4:2:0 (hardware limits); 26 inter-frame resizes; 7 not
root-caused (09-aq2, 09-lf_deltas, 15-segkey_adpq, 19-skip, 19-skip-01, 19-skip-02, 22-svc_1280x720_3).
Results on the board: `~/vp9conf/*.md`.

## Inter-frame resolution change: root cause
The 24 `vp90-2-21-resize_inter_*` vectors shrink (to 1/2 or 3/4) on a non-keyframe. GStreamer's
GstVp9Decoder logs "Drop frame on non-keyframe format change" and then drops every frame until a
keyframe that never comes: `v4l2slvp9dec` does not call
`gst_vp9_decoder_set_non_keyframe_format_change_support()` (d3d11/nvcodec/va do). It can't simply
renegotiate either: the V4L2 stateless resolution-change sequence frees all CAPTURE buffers, and VP9
needs the old-size references afterwards. The kernel also rejected any frame whose aligned size
differed from the CAPTURE format ("unexpected bitstream resolution").

### Done (kernel)
rkvdec-vdpu381-vp9.c accepts frames whose 64-aligned size is <= the decoded format and decodes them in
place; plane/MV offsets now come from the buffer format (shared by all CAPTURE buffers) while the
per-reference size and scale registers use each frame's real size. Not exercisable end to end with
stock GStreamer (it drops the frames first); regression-checked with the full fluster run.

### TODO (GStreamer half, deferred)
Patch `sys/v4l2codecs/gstv4l2codecvp9dec.c` (gst-plugins-bad 1.28.6, Ubuntu source package):
1. Call `gst_vp9_decoder_set_non_keyframe_format_change_support (decoder, TRUE)`.
2. In `new_sequence`/format-change handling for a non-keyframe: if the new aligned size fits the
   current V4L2 CAPTURE format, do NOT streamoff/reallocate; only update the output state (caps
   width/height) and keep the existing pool. Set GstVideoMeta/crop so downstream sees the real size
   with the buffer's stride.
3. If the new frame is larger than the CAPTURE buffers on a non-keyframe, fail that frame cleanly
   (needs larger buffers up front — option: allocate CAPTURE at the stream's maximum size, e.g. a
   property or max from the first keyframe x2 — the VP9 spec allows refs up to 2x larger).
4. Rebuild only the v4l2codecs plugin with meson against the system GStreamer, install to
   `~/.local/lib/gstreamer-1.0` or `GST_PLUGIN_PATH`, rerun fluster. Expected: the 24 shrink-only
   `resize_inter` vectors pass; 05-resize / 18-resize also grow and likely still fail (step 3).
Upstream note: the kernel change and the GStreamer change need to land together; the kernel side
should probably be posted as a follow-up to the VDPU381 VP9 series, with Tested-by from fluster.

## Other open items
- 4K VP9 decode is ~63 fps (8-bit) / ~52 fps (10-bit), slower than HEVC on the same core (~100 fps);
  suspect per-frame CPU work (probability adaptation, count table readback). Not profiled.
- 2 parallel 4K streams give 100 fps (1.6x) with uneven core use.
- The 7 unexplained conformance failures.
