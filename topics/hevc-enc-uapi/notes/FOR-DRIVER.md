# Using the HEVC stateless encode uAPI in the VEPU580 (rkvenc) driver

For the agent writing the driver on `opi5/rkvenc-7.3`. The uAPI is an
unmerged RFC, like Paul's H.264 one. See DESIGN.md for the rationale.

## 1. What to cherry-pick

Your H.264 base should be the one on `opi5/vepu121-h264enc` (Paul v1 1-8, 10,
11 plus the two h264 fixes). `opi5/hevc-enc-uapi` carries exactly the same
commits (same patch-ids, and byte-identical `drivers/media/v4l2-core`,
`include/media` and `include/uapi`), so you only need the 7 HEVC commits on
top:

```sh
git cherry-pick 8b8a57855..opi5/hevc-enc-uapi   # = b4c184b4d .. ae7404f75, 7 commits
```

| Commit | Needed by the driver |
|---|---|
| `b4c184b4d` media: hevc: Add H.265 syntax definitions | yes |
| `104dedacb` media: uapi: Add HEVC stateless encode support | yes |
| `18be16148` media: hevc: Add stateless encode RBSP writer | yes |
| `7b3ee3fab` KUnit tests for the RBSP writer | optional |
| `b96f43163` media: hevc: Add stateless encode core | yes |
| `615e1a863` KUnit tests for the core | optional |
| `ae7404f75` docs | optional (keep it for an upstream series) |

The patches are also in `~/orangepi5/work/_out/hevc-enc-uapi/patches/`. They
touch no H.264 file. The only shared files are `v4l2-core/Kconfig` and
`Makefile` and `v4l2-ctrls-*`; the hunks sit next to the H.264 ones and apply
cleanly on the vepu121 base.

Kconfig: `select V4L2_HEVC_ENC` (it selects `V4L2_HEVC_ENC_RBSP`) next to
`select V4L2_H264_ENC`.

## 2. Controls to register (HEVC context)

```c
/* compound, no ops needed (core reads p_cur) */
V4L2_CID_STATELESS_HEVC_SPS
V4L2_CID_STATELESS_HEVC_PPS
V4L2_CID_STATELESS_HEVC_ENCODE_PARAMS
V4L2_CID_STATELESS_HEVC_ENCODE_FEEDBACK      /* read-only, set by the core */
V4L2_CID_STATELESS_HEVC_START_CODE           /* menu: ANNEX_B only (min=max=ANNEX_B), VEPU580 always writes start codes */
/* stateful, optional but recommended */
V4L2_CID_MPEG_VIDEO_HEVC_PROFILE  (MAIN [, MAIN_STILL_PICTURE]; no MAIN_10: VEPU580 is 8-bit)
V4L2_CID_MPEG_VIDEO_HEVC_LEVEL    (up to 6.1/6.2 per what you validate)
V4L2_CID_MPEG_VIDEO_HEVC_TIER
V4L2_CID_MPEG_VIDEO_HEVC_{MIN,MAX,I_FRAME,P_FRAME}_QP
V4L2_CID_MPEG_VIDEO_FRAME_RC_ENABLE, _BITRATE_MODE (CQ; CBR/VBR only with your rc_ops), _BITRATE, _CONSTANT_QUALITY
V4L2_CID_MPEG_VIDEO_AU_DELIMITER, _PREPEND_SPSPPS_TO_IDR
```

The CAPTURE format is `V4L2_PIX_FMT_HEVC_SLICE` and the CAPTURE buffers must
be CPU-mappable (`vb2_plane_vaddr()` must work, as with dma-contig/sg), because
the core writes VPS/SPS/PPS there.

## 3. Context setup (start_streaming of CAPTURE)

```c
static const struct v4l2_hevc_enc_rps_limits vepu580_rps_limits = {
	.num_negative_pics = 4,		/* dlt_poc_s0_m10..m13 */
	.num_positive_pics = 0,		/* no s1 delta registers */
	.num_long_term_pics = 3,	/* poc_lsb_lt0..2 */
};

static const struct v4l2_hevc_enc_ops vepu580_hevc_ops = {
	.state_constrain  = vepu580_hevc_constrain,
	.rec_buffer_alloc = vepu580_rec_alloc,	/* FBC hdr+body, thumb, cmv */
	.rec_buffer_free  = vepu580_rec_free,
};

enc->ops = &vepu580_hevc_ops;
enc->rc_ops = &vepu580_hevc_rc_ops;	/* optional, for CBR/VBR */
enc->private_data = ctx;
enc->format_mplane = &ctx->dst_fmt;	/* or ->format for single-planar */
enc->crop = &ctx->crop;			/* optional, S_SELECTION; else NULL */
enc->timeperframe = &ctx->timeperframe;
enc->ctrl_handler = &ctx->ctrl_handler;
enc->max_l0_refs = 1;
enc->max_l1_refs = 1;			/* ignored without INTER_BIPRED */
enc->rps_limits = &vepu580_rps_limits;
enc->ref_slots_count_init = 1;		/* grows to sps_max_dec_pic_buffering_minus1 + 1 */
enc->flags = V4L2_HEVC_ENC_FLAG_INTER_PRED |
	     V4L2_HEVC_ENC_FLAG_HW_SLICE_HEADER;	/* not HW_TEMPORAL_ID: the core patches it */
ret = v4l2_hevc_enc_init(enc);		/* allocates the current recon + initial slots */
```

`v4l2_hevc_enc_exit(enc)` goes in stop_streaming.

`rec_buffer_alloc` sizes (HEVC, from the programming model §2.2): with
`cw = DIV_ROUND_UP(w, 64)` and `ch = DIV_ROUND_UP(h, 64) + 1`, the FBC header
is `ALIGN(cw*ch*64, SZ_8K)`, the body `cw*ch*4096*3/2`, the thumbnail
`cw*ch*256` and the collocated MV buffer `ALIGN(cw*ch*96, 256)`. Store the DMA
addresses in `buffer->private_data`. One call means one reference slot (or the
current buffer). The core swaps the buffers between slots, so never cache a
slot index between frames.

`state_constrain(enc, state)` is called after the core's accommodation, and
you may modify `state->sps/pps/encode`. For VEPU580:

- `sps.log2_min_luma_coding_block_size_minus3 = 0`,
  `sps.log2_diff_max_min_luma_coding_block_size = 3` (CTB 64), and
  recompute `state->ctb_log2_size = 6`, `width_ctbs`, `height_ctbs`;
- TB 4..32 (`log2_min_luma_transform_block_size_minus2 = 0`, `diff = 3`),
  and clamp the transform hierarchy depths to what MPP uses;
- `bit_depth_* = 0`, clear `PCM_ENABLED`, `SCALING_LIST_ENABLED` (unless you
  program the SCL tables), and `TRANSQUANT_BYPASS`;
- PPS: clear `TILES_ENABLED`/`ENTROPY_CODING_SYNC` until tiles are
  implemented (the core already does unless you set the `TILES` flags);
- return `-EINVAL` for things you cannot accommodate.

## 4. device_run

```c
v4l2_m2m_buf_copy_metadata(src, dst);			/* the dst timestamp must be the source's */
v4l2_ctrl_request_setup(src->vb2_buf.req_obj.req, &ctx->ctrl_handler);
ret = v4l2_hevc_enc_step(enc, dst);			/* may sleep: process context */
if (ret)
	goto job_error;			/* nothing changed in the DPB: safe to fail the job */
```

Then program the hardware from:

| Source | Use |
|---|---|
| `enc->state_active.sps / .pps` | SPS/PPS syntax registers (reg0237+), `enc_rsl`, `src_fill` |
| `enc->slice` (`struct v4l2_hevc_slice_header`) | All slice syntax registers: `nal_unit_type`, `slice_type`, `slice_pic_order_cnt_lsb`, `st_rps.{num_negative_pics, delta_poc_s0_minus1[], used_by_curr_pic_s0}` (st_ref_pic_flg = 0), `num_long_term_pics`, `lt[i].{poc_lsb_lt, used_by_curr_pic_lt, delta_poc_msb_present, delta_poc_msb_cycle_lt}`, `num_ref_idx_l0_active_minus1` + `flags & NUM_REF_IDX_ACTIVE_OVERRIDE`, `collocated_ref_idx`, `five_minus_max_num_merge_cand`, `slice_qp_delta`, chroma/deblocking offsets, `flags` (SAO luma/chroma, TMVP, CABAC init, deblocking override/disable, LF across slices, NO_OUTPUT_OF_PRIOR_PICS, NO_PIC_OUTPUT) |
| `enc->qp` | `enc_pic.pic_qp`, and the RC min/max |
| `enc->state_active.encode.flags & V4L2_HEVC_ENCODE_FLAG_REFERENCE` | `enc_pic.cur_frm_ref` (skip `rfpw` when clear) |
| `enc->ref.buffer_current.private_data` | recon write `rfpw_h/b`, `dspw`, `cmvw` |
| `enc->ref.l0_count`, `enc->ref.l0[0]` | if `l0_count`, then `v4l2_hevc_enc_ref_buffer(enc, enc->ref.l0[0])->private_data` gives `rfpr_h/b`, `dspr` |
| `enc->ref.collocated` (>= 0 when TMVP is on) | `cmvr` from that slot's buffer |
| `enc->slice.st_rps` used count + used LT | `enc_pic.num_pic_tot_cur` (0 or 1) |
| `enc->header_size` | `adr_bsbs = dst_dma + header_size`; `bsbb = dst_dma`; `bsbt = dst_dma + size - 1` |

Note that `enc->header_size` may be 0, for P pictures without parameter sets
and without an AUD.

## 5. Completion (IRQ thread / workqueue, never hard IRQ)

```c
struct v4l2_stateless_encode_stats stats = {
	.flags = V4L2_STATELESS_ENCODE_STATS_FLAG_QP |
		 V4L2_STATELESS_ENCODE_STATS_FLAG_SSE_LUMA |
		 V4L2_STATELESS_ENCODE_STATS_FLAG_BLOCKS,
	.qp_sum = st->qp_sum,
	.qp_count = <number of 8x8 blocks summed>,
	.qp_min = <lowest non-empty st_b8_qp[] bin>,
	.qp_max = <highest non-empty st_b8_qp[] bin>,
	.sse_luma = ((u64)st->sse_h32 << 16) | st->sse_l16,
	.num_intra_blocks = i32*16 + i16*4 + i8 + i4/4,	/* 8x8 units; check the units of st_pnum_* */
	.num_inter_blocks = p64*64 + p32*16 + p16*4 + p8,
};	/* no skip count on VEPU580: leave SKIP_BLOCKS clear */

vb2_set_plane_payload(&dst->vb2_buf, 0, enc->header_size + bs_lgth);
ret = v4l2_hevc_enc_complete(enc, dst, &stats);	/* DPB update, TemporalId patch, flags, feedback ctrl */
v4l2_ctrl_request_complete(src->vb2_buf.req_obj.req, &ctx->ctrl_handler);	/* AFTER complete() */
v4l2_m2m_buf_done_and_job_finish(..., ret ? VB2_BUF_STATE_ERROR : VB2_BUF_STATE_DONE);
```

- Call `v4l2_ctrl_request_complete()` here, **not** in device_run as hantro
  does, or the feedback never reaches the request.
- On hardware error, overflow (`bsf_oflw`) or timeout, do **not** call
  `v4l2_hevc_enc_complete()`. Mark the buffer as an error and still complete
  the request. The DPB stays as it was, and the next run re-sends the
  parameter sets if this run carried them.
- The TemporalId patch needs the hardware to write Annex B start codes
  (VEPU580 does), and it runs over `[header_size, bytesused)`.

## 6. Rate control (optional)

`enc->rc_ops->estimate(enc, state, &qp)` is called in `step()` when
`FRAME_RC_ENABLE` is set and `BITRATE_MODE` is CBR or VBR. `complete(enc,
state, bytesused, stats)` is called on completion. Program the hardware
CTU-row RC (`rc_cfg`, `rc_qp`, `rc_tgt.ctu_ebit`, `rc_dthd`, `qp_adj`) from your
own target in device_run. Without `rc_ops`, only direct-QP and CQ work, and
CBR/VBR make `step()` return `-EOPNOTSUPP`, so advertise only the modes you
support in the `BITRATE_MODE` menu.

## 7. Userspace sequence to test (no board yet)

1. S_FMT CAPTURE `HEVC_SLICE` WxH, then S_FMT OUTPUT NV12, then S_PARM 30 fps.
2. S_EXT_CTRLS SPS: `log2_max_pic_order_cnt_lsb_minus4 = 4`,
   `sps_max_dec_pic_buffering_minus1 = 1`, flags SAO|TMVP|STRONG_INTRA (AMP
   optional). PPS: flags `LOOP_FILTER_ACROSS_SLICES`, plus
   `DEBLOCKING_FILTER_CONTROL_PRESENT` if you want slice overrides.
3. Frame 0 (in a request): ENCODE_PARAMS `{IDR_W_RADL, tid1 1, I, poc 0,
   flags REFERENCE}`.
4. Frame n: `{TRAIL_R, tid1 1, P, poc n, num_refs 1, refs[0] = {ts(n-1),
   USED_BY_CURR_PIC}, flags REFERENCE|SLICE_TEMPORAL_MVP_ENABLED|SLICE_SAO_LUMA|SLICE_SAO_CHROMA}`.
5. After each request completes, G_EXT_CTRLS(request_fd) FEEDBACK: check
   `slice_qp`, `ref_idx_l0[0] == 0` and the stats.
6. Concatenate the CAPTURE payloads into a `.hevc` file and check it with
   `ffmpeg -i out.hevc -f null -` / `ffprobe -show_frames`, or decode it with
   the rkvdec HEVC decoder via fluster / GStreamer `v4l2slh265dec`.

The core's KUnit suite (`v4l2-hevc-enc-kunit.c`) is a working example of
this whole flow without hardware, with a fake vb2 buffer and recon
allocator.
