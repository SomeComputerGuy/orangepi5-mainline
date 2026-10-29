# V4L2 HEVC stateless encoding uAPI: design note

Branch `opi5/hevc-enc-uapi` (worktree `~/orangepi5/work/hevc-enc-uapi`), 2026-10-29.
Compile-tested and KUnit-tested only; no hardware was available.

## 1. Summary

This is a proposal for the first V4L2 **HEVC stateless encoding** uAPI. It sits on
top of Paul Kocialkowski's H.264 stateless encode series and follows its
design: the kernel writes the bitstream headers, keeps the reconstructed
reference pictures, and selects the QP. Userspace decides the picture types,
the GOP structure and which pictures are references, and sends per-picture
parameters through requests.

| Piece | Where |
|---|---|
| uAPI | `include/uapi/linux/v4l2-controls.h`, `videodev2.h` |
| control framework (types, validation, defaults) | `drivers/media/v4l2-core/v4l2-ctrls-{core,defs}.c`, `include/media/v4l2-ctrls.h` |
| H.265 syntax constants | `include/media/v4l2-hevc.h` (extends the existing header) |
| RBSP writer: VPS/SPS/PPS/AUD/slice segment header, emulation prevention | `drivers/media/v4l2-core/v4l2-hevc-enc-rbsp.c`, `include/media/v4l2-hevc-enc-rbsp.h` |
| Encode core: accommodation, RPS/DPB, ref lists, QP, headers, feedback | `drivers/media/v4l2-core/v4l2-hevc-enc.c`, `include/media/v4l2-hevc-enc.h` |
| KUnit: writer (19 cases) and core (4 cases) | `v4l2-hevc-enc-rbsp-kunit.c`, `v4l2-hevc-enc-kunit.c`, `drivers/media/v4l2-core/.kunitconfig` |
| Documentation | `Documentation/userspace-api/media/v4l/ext-ctrls-codec-stateless.rst` and 4 smaller files |
| Reference tools (not in the kernel) | `tools/hevc_ref.py` (independent writer and parser), `tools/rst_check.py`, `tools/vectors-trace.txt` |

The single most important decision: **references are explicit**. Userspace
lists the reference picture set (RPS) of each picture by OUTPUT-buffer
timestamp. The kernel computes the POC deltas and the reference lists. This
fits HEVC naturally, because HEVC signals the full RPS in every slice header,
and it resolves the 2026 Media Summit action item on reference handling for
HEVC without MMCO-style complexity.

## 2. Base

- Paul Kocialkowski, `[PATCH 00/14] media: Add V4L2 H.264 stateless encode
  and VC8000E support`, **v1**, 2026-05-22,
  <https://lore.kernel.org/all/20260522101653.2565125-1-paulk@sys-base.io/>.
  v2 had not been posted by the time of the survey (2026-10-29: "v2 in
  progress", 2026-09-24).
- Aligned with the H.264 base the other agents use (branch
  `opi5/vepu121-h264enc`): Paul's v1 patches **1-8, 10, 11** applied unchanged
  (authorship and `Link:` tags kept; Marco Felsch's 10/14 included), plus the
  two generic fixes from that branch, "media: h264: Only write the SPS and PPS
  of a stateless encode when they change" (fixes the re-emission inversion)
  and "media: h264: Support picture order count type 2 in stateless encode".
  They were cherry-picked from `opi5/vepu121-h264enc` commits `dc7ce80a1..633623e0d`,
  `e57b66afd`, `0fde3e94e`, `dfeeecfc9`, `4bbc2fa31` and `d418ea388`. The
  patch-ids are identical, and `drivers/media/v4l2-core`, `include/media` and
  `include/uapi` are byte-identical to that branch at `d418ea388`, so the
  branches merge cleanly. Not taken: 9/14 and 12-14 (VC8000E driver and
  imx8mp DT, which that branch does not carry either), the sibling's
  VEPU121/VEPU2 driver commits, and its "DO NOT UPSTREAM: keep v4l2-core
  symbol versions".
- The HEVC work is 7 commits on top and touches no H.264 file.

```
5e33b74b0 (base: opi5/multicore-7.3)
67e412586 media: h264: Add a more generic reflist builder init        [Paul 1/14]
3bf62ab6f media: uapi: Add H.264 stateless encode support             [Paul 2/14]
e3d00e37b media: h264: Add SPS video definitions                      [Paul 3/14]
e839a6d1c media: h264: Add stateless encode core                      [Paul 4/14]
4942c96ce media: h264: Add stateless encode rbsp                      [Paul 5/14]
5025a51b6 media: h264: Add stateless encode reference management      [Paul 6/14]
93a93f455 media: h264: Add stateless encode rate control              [Paul 7/14]
2ee450bfb media: verisilicon: Report default pixel coding for non-JPEG and fix JPEG case [Paul 8/14]
abf5e0ce7 media: hantro: use hantro_decoded_buffer only for dst_vq    [Marco 10/14]
57162d0f3 media: verisilicon: Add common encoder parm and frameintervals ioctls [Paul 11/14]
0d64428f4 media: h264: Only write the SPS and PPS of a stateless encode when they change [sibling fix]
8b8a57855 media: h264: Support picture order count type 2 in stateless encode [sibling fix]
b4c184b4d media: hevc: Add H.265 syntax definitions
104dedacb media: uapi: Add HEVC stateless encode support
18be16148 media: hevc: Add stateless encode RBSP writer
7b3ee3fab media: hevc: Add KUnit tests for the stateless encode RBSP writer
b96f43163 media: hevc: Add stateless encode core
615e1a863 media: hevc: Add KUnit tests for the stateless encode core
ae7404f75 media: docs: Document the HEVC stateless encode uAPI
```

## 3. How the H.264 design carries over

| H.264 series (Paul v1) | HEVC proposal | Why |
|---|---|---|
| Coded format `V4L2_PIX_FMT_H264_SLICE`, renamed `H264_SL` at the 2026 Summit | `V4L2_PIX_FMT_HEVC_SLICE` ('S265'), documented for encoders. If the H.264 rename lands, `HEVC_SL` follows the same way | Same pattern. A new fourcc would be gratuitous. The device direction (encoder) defines the semantics: one access unit per CAPTURE buffer |
| `V4L2_CID_STATELESS_H264_SPS/PPS`, decoder structs reused | `V4L2_CID_STATELESS_HEVC_SPS/PPS`, `struct v4l2_ctrl_hevc_sps/pps` reused | Same reuse. All coding-tool fields an encoder needs are present |
| `struct v4l2_h264_sps_video` (kernel-internal: VUI, cropping) | `struct v4l2_hevc_sps_video` (kernel-internal: PTL, conformance window, temporal nesting, VUI, VPS timing) | The decoder SPS lacks these because a decoder does not need them. They come from the format, S_PARM and stateful controls, exactly as for H.264 |
| `V4L2_CID_STATELESS_H264_ENCODE_PARAMS` | `V4L2_CID_STATELESS_HEVC_ENCODE_PARAMS` (`CODEC_STATELESS_BASE + 410`) | Per-picture slice header values |
| `nal_ref_idc` (reference marking) plus a sliding-window DPB in the kernel | Explicit RPS: `refs[]` by timestamp plus `V4L2_HEVC_ENCODE_FLAG_REFERENCE` | HEVC has no sliding window. The RPS is the marking (see 5) |
| `slice_qp_delta` in encode params, overwritten by kernel RC | Not in encode params. The QP comes from the stateful QP/RC controls (which can be set per request) and is reported in feedback | A kernel-written field inside a userspace-set request control cannot be read back per request (see 6) |
| Write-back of SPS/PPS/ENCODE_PARAMS into the controls | Write-back of SPS/PPS. Per-picture results go to the new read-only `V4L2_CID_STATELESS_HEVC_ENCODE_FEEDBACK` | Reaches userspace through completed requests today, without read-only request support |
| `V4L2_CID_STATELESS_H264_START_CODE`, `AU_DELIMITER`, `PREPEND_SPSPPS_TO_IDR` | `V4L2_CID_STATELESS_HEVC_START_CODE` (existing), `AU_DELIMITER`, `PREPEND_SPSPPS_TO_IDR` (applied to all IRAP pictures) | Same |
| Stateful RC controls (`FRAME_RC_ENABLE`, `BITRATE_MODE`, `BITRATE`, `CONSTANT_QUALITY`, `H264_{I,P,B}_FRAME_QP`, `H264_MIN/MAX_QP`) | Same, with the `HEVC_*` QP controls | Same |
| RBSP writer with driver ops (`bits/ue/se/align`) for hardware header writers | Writer without ops (sticky-error, byte-wise emulation prevention) | No known HEVC encoder needs bit-level header injection (VEPU580 and VC8000E both take CPU-written headers in the output buffer). Can be added |
| HW flags `HW_AUD/SPS/PPS/SLICE_HEADER`, `INTER_PRED/BIPRED` | Same plus `HW_VPS`, `HW_TEMPORAL_ID`, `SCALING_LIST`, `TILES`, `ENTROPY_CODING_SYNC` | Hardware differences found in VEPU580 and VC8000E |
| `v4l2_h264_enc_init/step/complete/exit`, `state_constrain`, `rec_buffer_alloc/free` | `v4l2_hevc_enc_init/step/complete/exit`, the same ops | Drivers that implement both codecs use one pattern |
| In-kernel RC (direct, CQ, CBR) | Direct QP and CQ in the core. CBR/VBR through driver `rc_ops` | Paul's RC is typed on `struct v4l2_h264_enc_state`, so it cannot be reused without a refactor (open question 9.3) |

## 4. uAPI in detail

### 4.1 Setup (unchanged from the H.264 model)

ENUM_FMT/S_FMT on CAPTURE with `V4L2_PIX_FMT_HEVC_SLICE` and the visible size.
S_FMT on OUTPUT for the raw format. S_PARM sets the frame interval (VUI/VPS
timing, RC). Optional S_SELECTION crop: the driver passes it as `enc->crop`
and it becomes the conformance window. SPS/PPS controls hold the coding
tools. The kernel overwrites `pic_width/height_in_luma_samples` from the
format, aligned to the minimum CB size.

### 4.2 `struct v4l2_ctrl_hevc_encode_params` (288 bytes, no implicit padding)

| Field | Justification |
|---|---|
| `nal_unit_type` | Userspace owns the GOP structure: IDR vs CRA vs BLA, `_N` vs `_R`, TSA/STSA/RADL/RASL. Validated against Table 7-1 VCL types. Same name and type as in `v4l2_ctrl_hevc_slice_params` |
| `nuh_temporal_id_plus1` | Temporal scalability (SVC-T). Validated (1..7, 1 for IRAP, >1 for TSA/STSA). On hardware that cannot write it (VEPU580), the core patches the NAL headers after the run, which is what MPP does in userspace |
| `slice_type` | `V4L2_HEVC_SLICE_TYPE_*` (existing). P is turned into I on intra-only hardware (as in H.264). B is rejected without `INTER_BIPRED` |
| `pic_parameter_set_id` | Mirrors H.264. Forced to the single PPS |
| `pic_order_cnt_val` | Full POC rather than `slice_pic_order_cnt_lsb`. The kernel needs the full value to compute RPS deltas and LT MSB cycles, and validates that a decoder can re-derive the MSB from prevTid0Pic (8.3.1) |
| `num_ref_idx_l0/l1_active_minus1` + `..._NUM_REF_IDX_ACTIVE_OVERRIDE` | Same as the slice header. Clamped to the hardware limits. The core sets the override flag itself when clamping requires it |
| `collocated_ref_idx`, `COLLOCATED_FROM_L0` | TMVP collocated picture. The core resolves it to a DPB slot (`enc->ref.collocated`), which tells VEPU580 which `cmvr` buffer to read |
| `five_minus_max_num_merge_cand` | Encoder tuning choice that is visible in the bitstream |
| `slice_cb/cr_qp_offset`, `slice_beta/tc_offset_div2`, `DEBLOCKING_FILTER_OVERRIDE`, `SLICE_DEBLOCKING_FILTER_DISABLED`, `SLICE_LOOP_FILTER_ACROSS_SLICES_ENABLED`, `SLICE_SAO_LUMA/CHROMA`, `SLICE_TEMPORAL_MVP_ENABLED`, `MVD_L1_ZERO`, `CABAC_INIT`, `NO_PIC_OUTPUT`, `NO_OUTPUT_OF_PRIOR_PICS` | One-to-one slice header syntax elements that the SPS/PPS enable. Flags already in the decoder uAPI use the **same bit values** as `V4L2_HEVC_SLICE_PARAMS_FLAG_*` (bits 0-5, 7, 8). Encoder-only flags start at bit 16 |
| `num_refs` + `refs[16]` (`{u64 timestamp; u8 flags; u8 reserved[7]}`), flags `USED_BY_CURR_PIC`, `LONG_TERM` | The RPS (section 5). 16 = `V4L2_HEVC_DPB_ENTRIES_NUM_MAX`. Timestamps are how both stateless decoders and Paul's 2025 encoder proposal identify pictures |
| `V4L2_HEVC_ENCODE_FLAG_REFERENCE` | Tells the kernel whether to keep the reconstruction. HEVC has no `nal_ref_idc`, and `_N` NAL types do not say whether a higher sub-layer will reference the picture. VEPU580 skips the recon write (`cur_frm_ref=0`) without it |
| `reserved`, `flags` (u64) | Room to grow. Unknown flags are rejected, so they can be given meaning later |

Fields deliberately left out: `slice_qp_delta` (see 6), `colour_plane_id`
(separate colour planes are unsupported), `slice_segment_address`/dependent
slices (per-segment, driver-internal with multi-slice), entry points (only
known after encoding), weighted prediction tables, `ref_pic_lists_modification`
(lists are always the default order; userspace picks the reference with
`USED_BY_CURR_PIC` instead), `short_term_ref_pic_set_idx` (RPS always inline,
open question 9.5), SCC/range-extension elements.

### 4.3 Validation (`std_validate_compound`)

Rejects (`-EINVAL`): unknown flags; non-VCL or reserved NAL types; slice type
> 2; TemporalId 0 or > 7; IRAP with P/B or TemporalId ≠ 0; TSA/STSA with
TemporalId 0; `num_refs` > 16; merge candidates > 5; chroma offsets outside
±12; deblocking offsets outside ±6 when overridden; ref idx ≥ 15; unknown ref
flags; duplicate reference timestamps; IRAP with a used reference (NumPicTotalCurr
must be 0); P/B without a used reference.

Zeroes (accommodation, as in the H.264 validator): POC and refs of IDR
pictures; list sizes, TMVP, collocated, CABAC init and merge fields of I
slices; L1 fields of non-B slices; deblocking offsets when not overridden;
reserved fields; unused `refs[]` entries. `COLLOCATED_FROM_L0` is forced for
P (inferred 1 by 7.4.7.1).

The default value (`std_init_compound`) is a valid IDR picture with
`REFERENCE`, so a freshly opened device does not hold an invalid control.

### 4.4 `struct v4l2_ctrl_hevc_encode_feedback` (112 bytes, read-only)

| Field | Justification |
|---|---|
| `timestamp` | Which picture this describes. It is also the key to use in later `refs[]` |
| `pic_order_cnt_val`, `nal_unit_type`, `nuh_temporal_id_plus1`, `slice_type` | The values after accommodation (for example P to I on intra-only hardware) |
| `slice_qp` | SliceQpY chosen by the kernel RC. This is what `V4L2_CID_MPEG_VIDEO_AVERAGE_QP` gives stateful encoders, but per request |
| `num_ref_idx_l0/l1_active`, `ref_idx_l0/l1[16]` | The resolved reference lists, as indices into `refs[]`. Userspace (or a test) can verify exactly what was predicted from. This is the "explicit DPB/L0/L1 feedback" Paul listed as open |
| `stats` (`struct v4l2_stateless_encode_stats`) | Codec-agnostic per-frame statistics (below) |
| `flags` (`FEEDBACK_FLAG_REFERENCE`) | Whether the recon was kept |

`struct v4l2_stateless_encode_stats` (48 bytes) is deliberately
codec-agnostic, so an H.264 feedback control can embed the same structure:
`flags` (validity: `QP`, `SSE_LUMA`, `BLOCKS`, `SKIP_BLOCKS`), `header_size`
(bytes written by the kernel, always valid), `qp_sum`/`qp_count`/`qp_min`/`qp_max`,
`sse_luma` (PSNR), `num_intra/inter/skip_blocks` in 8x8 units. Raw sums are
reported instead of averages, so no fixed-point convention is needed and
userspace can aggregate across frames. Hardware-specific RC inputs such as
VEPU580 MADI/MADP, the per-QP histogram and Hantro checkpoints are **not**
exposed: rate control is in the kernel, so those stay driver-internal (and
"don't abuse controls" argues against vendor-unit fields).

### 4.5 Capability reporting

This follows Paul's "accommodation rather than combinatory capabilities":

- B frames: `INTER_BIPRED` driver flag. Userspace learns of it by having
  `slice_type = B` rejected. VIDIOC_TRY_EXT_CTRLS with a driver `try_ctrl` that
  calls the same check is a possible refinement (open question 9.4).
- Max references: `enc->max_l0_refs/max_l1_refs` (1 is valid; VEPU580 = 1/0).
  The PPS defaults are clamped and written back, so G_EXT_CTRLS on the PPS
  after the first run shows `num_ref_idx_l0_default_active_minus1 = 0`.
- RPS size: `enc->rps_limits` (VEPU580: 4 negative, 0 positive, 3 long-term).
- Coding tools: `state_constrain` clears what the hardware lacks, and the
  written-back SPS/PPS show the result.
- Profiles/levels/tiers: the existing stateful `V4L2_CID_MPEG_VIDEO_HEVC_PROFILE/LEVEL/TIER`
  menus with driver-set ranges. These are the "upside-down" decoder
  capability controls that Nicolas asked for.

## 5. Reference handling: explicit RPS

- Every encoded picture with `FLAG_REFERENCE` has its reconstruction (plus
  whatever side buffers the hardware needs: VEPU580 FBC header/body, ¼
  thumbnail, collocated MVs) stored in a driver-allocated slot, keyed by the
  OUTPUT timestamp, with its POC. Slots are grown on demand up to
  `sps_max_dec_pic_buffering_minus1 + 1` and never shrunk (Paul's policy),
  plus one "current" buffer that is swapped into a free slot on completion.
- The RPS of each picture lists **all** pictures to keep. Those not listed are
  dropped at completion. This mirrors the decoder's 8.3.2 marking exactly, so
  encoder and decoder DPBs cannot diverge.
- The kernel sorts short-term entries by |ΔPOC| (closest first), codes
  `delta_poc_s0/s1_minus1` and the used flags, codes LT entries with
  `poc_lsb_lt`, always with `delta_poc_msb_present_flag = 1` (so the LSB can
  never be ambiguous), and accumulates `delta_poc_msb_cycle_lt` (7-52). It
  then builds RefPicList0/1 per 8.3.4 without modification, truncated to the
  hardware's list size.
- **Single-reference hardware**: the reference picture is the first
  used-by-curr entry in L0 order. For P pictures, that is the closest
  preceding used short-term picture, then following ones, then LT.
  Userspace selects which stored picture VEPU580 reads by marking just
  that one as used. Others stay `USED_BY_CURR_PIC = 0` (kept, not read). This
  is MPP's "multiple references = choosing the slot" model, expressed in
  standard syntax.
- Errors leave state untouched: the DPB is only updated in
  `v4l2_hevc_enc_complete()`. A failed run, or one that userspace drops or
  re-encodes (MPP-style RC re-encode at a higher QP), can be resubmitted with
  the same refs. Parameter sets written for an incomplete run are re-sent.
- Checked: references not in the DPB, an LT picture used as ST, ΔPOC = 0 or >
  2^15, LT MSB in the future, the POC-MSB derivation window, `num_refs` >
  `sps_max_dec_pic_buffering_minus1`, and hardware RPS limits.

Why not the H.264 sliding window: HEVC has none. Encoding "sliding window"
in the kernel would mean inventing a policy that the RPS syntax then encodes
explicitly anyway, and userspace would still have no say in LTR or temporal
layers. Explicit RPS is also what VA-API (`VAPictureParameterBufferHEVC.reference_frames`)
and Vulkan Video (`StdVideoEncodeH265ReferenceInfo`/`pReferenceSlots`)
expose, so userspace stacks map onto it directly.

## 6. Feedback path

`v4l2_ctrl_request_complete()` copies the current value of every control that
the request did not set into the request (`v4l2-ctrls-request.c`,
`cur_to_req`). A control that userspace never sets, and that the driver
updates before completing the request, is therefore readable per request
with `VIDIOC_G_EXT_CTRLS(request_fd)` today, without the read-only-request
series (2026 Summit note). By contrast, Paul's write-back of
`H264_ENCODE_PARAMS` is invisible in a request that set that control
(`p_req_valid`). That is why HEVC puts kernel-chosen values (QP, lists) in a
separate read-only control.

Driver requirement: call `v4l2_hevc_enc_complete()` (which sets the feedback
control and may sleep) and then `v4l2_ctrl_request_complete()` from process
context **after** the hardware finished. Hantro calls `request_complete` in
`device_run`, before the hardware runs, so an encoder must defer it.

## 7. Kernel helpers

### 7.1 RBSP writer (`v4l2-hevc-enc-rbsp`)

- `v4l2_hevc_enc_rbsp_{init,bytes,error,bits,ue,se,trailing_bits,nal_begin,nal_end}`,
  plus `..._{aud,vps,sps,pps,slice_header}`. The low-level calls are exported
  so drivers can write SEI or other NAL units.
- Emulation prevention is byte-wise as bytes are produced: a byte ≤ 3 after
  two zero bytes gets a 0x03 first. It is off for start codes and the 2-byte
  NAL header, which is always non-zero in byte 2. Slice headers end with
  `byte_alignment()`, whose last byte is non-zero, so hardware-produced slice
  data that follows cannot complete an emulated start code across the
  boundary.
- Errors are sticky (`-ENOSPC`, `-EINVAL`), so the syntax functions read like
  the spec tables.
- Supported subset: single layer; sub-layers with the ordering info coded once;
  inline RPS; default scaling lists; no lists modification (written as "no
  modification" when the PPS allows it); no weighted prediction, HRD, SEI or
  extensions. Asking for more returns `-EINVAL` rather than writing a wrong
  bitstream.
- It does **not** reuse Paul's H.264 bit writer, which is `static` in
  `v4l2-h264-enc-rbsp.c` and typed on `struct v4l2_h264_enc_rbsp`. Using it
  would have meant modifying his patches. Open question 9.2 proposes a
  shared `v4l2-rbsp-writer`.

### 7.2 Encode core (`v4l2-hevc-enc`)

Driver-facing API (see FOR-DRIVER.md):
`v4l2_hevc_enc_init/exit/step/complete`, `struct v4l2_hevc_enc_ops`
(`state_constrain`, `rec_buffer_alloc/free`), `struct v4l2_hevc_enc_rc_ops`
(`estimate`, `complete`), flags, `max_l0/l1_refs`, `rps_limits`, `crop`. After
`step()` the driver reads `state_active` (SPS/PPS/encode), `ref` (current recon
buffer, `l0/l1` slots, `collocated` slot), `slice` (resolved slice header,
which is also the register source for hardware slice-header writers), `qp`, and
`header_size`.

Accommodation rules: 4:2:0 only; one VPS/SPS/PPS (IDs clamped); CTB 16..64;
min CB ≤ 64; coded size = CAPTURE size aligned to min CB; conformance window
from the visible/crop rectangle (even offsets); temporal nesting is set when
there is a single sub-layer; PTL from the stateful menus (Main is also
signalled as Main10-compatible, MSP as Main/Main10-compatible); the level is
auto-selected from Table A.8 MaxLumaPs/MaxLumaSr when there is no level
control; VUI timing from S_PARM; colour description from colorimetry
(BT.601/709/2020, SMPTE240M, sRGB, PQ, DCI-P3); scaling lists, tiles and WPP
only with the matching driver flags. Tiles and WPP also require hardware slice
headers, because entry points are only known after encoding. Weighted
prediction is off. A changed SPS is held until the next IRAP (7.4.2.4.2). QP:
direct I/P/B controls, linear CQ, or driver RC. It is clamped to the min/max
controls and the bit-depth range.

## 8. Validation done

| Check | Result |
|---|---|
| `make W=1 drivers/media/v4l2-core/` (arm64, `CONFIG_V4L2_HEVC_ENC=m CONFIG_V4L2_HEVC_ENC_RBSP=m CONFIG_V4L2_H264_ENC=m`) | no warnings |
| KUnit (UML): `./tools/testing/kunit/kunit.py run --kunitconfig=drivers/media/v4l2-core` | 23/23 pass (writer 19, core 4) |
| Mutation check (EPB threshold `<=` → `<`) | caught by 3 test cases |
| Writer vectors | Generated by `tools/hevc_ref.py`, an independent implementation (bit lists from the syntax tables plus a separate EPB pass) that also parses every vector back and checks it. **No x265/ffmpeg/gstreamer on the host**, so no encoder-generated vectors. The VPS of configuration A equals a VPS commonly seen in x265 output (`40 01 0c 01 ff ff 01 60 00 00 03 00 90 00 00 03 00 00 03 00 5d 95 98 09`, recalled from memory, not regenerated) |
| Core end-to-end | The IDR and P access units produced by the core in KUnit were dumped and parsed with the reference parser: well-formed VPS/SPS/PPS/slice headers, 720p30 auto-selected level 3.1, RPS/TMVP as requested |
| uAPI headers | `headers_install`, then a C99 program `-Wall -Wextra -Werror` with `_Static_assert` on sizes/offsets/IDs/flag equalities: x86-64 and arm64 (full), i386 (freestanding, `v4l2-controls.h`) all OK. Same layout everywhere |
| `scripts/kernel-doc -none -Wall` | clean on all new headers and sources (2 pre-existing warnings in `v4l2-hevc.h`) |
| `.rst` | docutils 0.23 with the kernel's own `rstFlatTable.py` (`tools/rst_check.py`): 0 new messages in the 4 edited files. `make htmldocs` not run (no Sphinx on the host) |
| `checkpatch --strict` | only "Missing Signed-off-by" (by design), "MAINTAINERS need updating?" for new files, and 2 `pr_cont` warnings that follow the existing pattern of `v4l2_ctrl_type_op_log()` |
| Bisectability | each of the 7 HEVC commits builds its changed objects with W=1 and no warnings; checkpatch run per commit |

To regenerate and check the vectors:
`python3 -I tools/hevc_ref.py check` (writes, parses back, asserts) and
`python3 -I tools/hevc_ref.py carrays` (prints the C arrays used in the test).

## 9. Hardware mappings

### 9.1 RK3588 VEPU580 (from `~/orangepi5/docs/vepu580-programming-model.md`; HEVC register offsets there are UNVERIFIED)

| uAPI / core value | VEPU580 register (field) | Notes |
|---|---|---|
| codec | `enc_pic.enc_stnd = 1` | |
| `state_active.sps` coded size | `enc_rsl.pic_wd8_m1/pic_hd8_m1`, `src_fill` | CTB 64 fixed in MPP, so `state_constrain` sets min CB 8, CTB 64, TB 4..32 |
| `sps.flags` SAO / TMVP / strong intra / LT present, `log2_max_poc_lsb`, `num_short_term_ref_pic_sets` (0) / `num_long_term_ref_pics_sps` (0) | `reg0237+` SPS group: `smpl_adpt_ofst_e`, `tmpl_mvp_e`, `strg_intra_smth`, `lt_ref_pic_prsnt`, `log2_max_poc_lsb`, `num_st_ref_pic`, `num_lt_ref_pic` | The HW writes the slice header and needs the SPS context |
| `pps` flags and values | PPS group: `dpdnt_sli_seg_en`, `out_flg_prsnt_flg`, `num_extr_sli_hdr`, `sgn_dat_hid_en`, `cbc_init_prsnt_flg`, `pic_init_qp`, `cu_qp_dlt_en/depth`, `chrm_qp_ofst_prsn` (+ cb/cr offsets), `lp_fltr_acrs_sli/til`, `dblk_fltr_ovrd_en`, `lst_mdfy_prsnt_flg`, `sli_seg_hdr_extn` | |
| `slice.nal_unit_type`, `slice_type`, `pps_id`, `NO_OUTPUT_OF_PRIOR_PICS`, `NO_PIC_OUTPUT` | `sli_type`, `sli_pps_id`, `no_out_pri_pic`, `pic_out_flg` + NAL type field | TemporalId not supported: the core patches it (no `HW_TEMPORAL_ID`), as MPP `hal_h265e_amend_temporal_id()` does |
| `slice.slice_pic_order_cnt_lsb` | `sli_poc_lsb` | |
| `slice.st_rps` | `st_ref_pic_flg` (=0, inline), `num_negative_pics`, `num_pos_pic`, `used_by_s0_flg`, `dlt_poc_s0_m10..m13` | `rps_limits = {4, 0, 3}` |
| `slice.lt[]` | `num_lt_pic`, `poc_lsb_lt0..2`, `used_by_lt_flg0..2`, `dlt_poc_msb_prsnt0..2`, `dlt_poc_msb_cycl0..2` | |
| `slice.num_ref_idx_*`, override | `num_refidx_l0/l1_act`, `num_refidx_act_ovrd` | `max_l0_refs = 1`, no `INTER_BIPRED` |
| NumPicTotalCurr | `enc_pic.num_pic_tot_cur` | = used entries (0 or 1) |
| `slice.flags` SAO, TMVP, CABAC init, MVD L1 zero, collocated, deblocking override/disable, LF across slices | `sli_sao_luma/chrm_flg`, `sli_tmprl_mvp_e`, `cbc_init_flg`, `mvd_l1_zero_flg`, `col_frm_l0_flg`, `col_ref_idx`, `dblk_fltr_ovrd_flg`, `sp_dblk_fltr_dis`, tc/beta offsets, `lp_fltr_acrs_sli` | |
| `five_minus_max_num_merge_cand` | `max_mrg_cnd` | |
| `slice_cb/cr_qp_offset` | `sli_cb_qp_ofst` (+ cr) | |
| `ref_pic_lists_modification` (none) | `ref_pic_lst_mdf_l0 = 0`, `lst_entry_l0` | |
| slice header extension (0) | `sli_hdr_ext_len = 0` | |
| `enc->qp` | `enc_pic.pic_qp`. Row RC `rc_qp`, `rc_tgt.ctu_ebit`, `rc_dthd`, `qp_adj` from driver `rc_ops` | Hardware CTU-row RC sits under the kernel frame RC |
| `ref.buffer_current` | `rfpw_h/b`, `dspw`, `cmvw`. `enc_pic.cur_frm_ref = FLAG_REFERENCE` | One FBC + thumb + cmv triple per slot, allocated in `rec_buffer_alloc` |
| `ref.l0[0]` | `rfpr_h/b`, `dspr` | single read port |
| `ref.collocated` | `cmvr` | |
| `header_size` | `adr_bsbs = base + header_size`, `bsbb = base`, `bsbt = base + size - 1` | |
| `HW_SLICE_HEADER` (yes), `HW_VPS/SPS/PPS` (no) | | |
| tiles (`TILES` flag, later) | `tile_pos`, `tile_cfg`, `lpfw/lpfr`, DCHS | Deferred. Up to 4 uniform columns, dual-core |
| feedback `stats` | `bs_lgth_l32/h8` → payload; `qp_sum` → `qp_sum` (+ `qp_count` = 8x8 block count); `st_b8_qp[52]` → `qp_min/qp_max` (lowest/highest non-zero bin); `sse_l16/h32` → `sse_luma`; `st_pnum_p64..p8` → inter blocks, `st_pnum_i32..i4` → intra blocks (in 8x8 units) | Flags `QP | SSE_LUMA | BLOCKS`. No skip count, so `SKIP_BLOCKS` stays clear. MADI/MADP feed driver RC only |

### 9.2 Hantro VC8000E HEVC (from the register header in Paul's 12/14, `hantro_vc8000e_regs.h`)

The VC8000E register file already contains the HEVC fields (Paul notes this
in 12/14). Paul's driver only implements H.264.

| uAPI / core value | VC8000E field | Notes |
|---|---|---|
| codec | `swreg4.mode = HANTRO_VC8000E_SWREG4_MODE_HEVC`; capability `swreg80.hwhevcsupport` | |
| `nal_unit_type`, TemporalId | `nal_unit_type`, `nuh_temporal_id` | Sets `HW_TEMPORAL_ID` |
| POC | `poc` (`swreg11`) | Full POC |
| `slice.st_rps` | `num_negative_pics`, `num_positive_pics` (2 bits each), `l0_delta_poc0/1` (+ `_msb`), `l0_used_by_curr_pic0/1`, `l0_long_term_flag0/1`, `l1_*` likewise, `l0/l1_used_by_next_pic0/1` (the kept-only entries), `rps_id` | `max_l0_refs = max_l1_refs = 2`, `INTER_BIPRED`, `rps_limits` ≤ 3 each |
| LT | `long_term_ref_pics_present_flag`, `num_long_term_pics` (2 bits) | |
| lists modification | `ref_pic_list_modi_flag_l0/l1`, `list_entry_l0/l1_pic0/1` | Set to 0 (default order) |
| SPS tools | `sao_enable`, `scaling_list_enabled_flag`, `strong_intra_smoothing_enabled_flag`, `max_cb_size`, `min_cb_size`, `max_trb_size`, `max_trans_hierarchy_depth_inter/intra` | |
| PPS | `pps_id`, `pic_init_qp`, `chroma_qp_offset`, `cu_qp_delta_enabled`, `diff_cu_qp_delta_depth`, `pps_deblocking_filter_override_enabled_flag`, `tiles_enabled_flag`, `num_tile_rows/columns`, `loop_filter_across_tiles_enabled_flag` | |
| slice | `cabac_init_flag`, `slice_deblocking_filter_override_flag`, `deblocking_filter_dis`, `deblocking_beta/tc_offset`, `slice_size` (multi-slice) | |
| collocated MVs | `colctbs_store_base`, `colctbs_load_base` | Per-slot side buffer |
| byte stream vs NAL | `output_strm_mode` | `START_CODE` control |
| feedback | `qp_sum` (`swreg183`) → `qp_sum`; `sse_div_256` (`swreg133`) → `sse_luma` (× 256); `skipcu8num` (`swreg112`) → `num_skip_blocks` | `QP | SSE_LUMA | SKIP_BLOCKS` |

Both hardware designs program their slice headers from the same
`struct v4l2_hevc_slice_header`, and both take CPU-written VPS/SPS/PPS in
front of the hardware stream. **This gives the "second implementation, not
just a variant of the same brand" Nicolas asked for: Rockchip VEPU580 and
VeriSilicon VC8000E need nothing beyond this uAPI.**

## 10. Open questions for upstream review

1. **Explicit references in HEVC vs sliding window in H.264.** Is the
   asymmetry acceptable? HEVC's RPS is explicit by design, so this is the
   natural fit. Should H.264 also move to explicit references (timestamps +
   kernel-generated MMCO/RPLM), as Paul's 2025 proposal had? The Summit
   action item is still open.
2. **Shared RBSP bit writer.** Factor Paul's private H.264 writer and this one
   into a codec-agnostic `v4l2-rbsp-writer` (with Paul's optional HW
   bit-injection ops)? It would also serve VP8/AV1 headers.
3. **Rate control sharing.** Paul's RC is typed on `struct v4l2_h264_enc_state`.
   Making it take a codec-neutral `{slice class, bitrate, frame interval,
   block count, last size, last QP}` state would give HEVC CBR/VBR for free.
   Until then, HEVC CBR/VBR needs driver `rc_ops`.
4. **Capability discovery.** Is reject-on-use plus written-back accommodation
   enough (B frames, list sizes, RPS limits), or do we want a read-only
   `V4L2_CID_STATELESS_HEVC_ENCODE_CAPS` compound, or `try_ctrl` helpers?
5. **SPS RPS candidates.** Always coding the RPS inline costs a few bytes per
   slice. Should `V4L2_CID_STATELESS_HEVC_EXT_SPS_ST_RPS` be honoured on
   encoders, with the kernel matching each picture's RPS against the
   candidates (`short_term_ref_pic_set_idx`)?
6. **Feedback as a control vs read-only requests.** The read-only control
   works today. Is that the intended pattern, and should the generic
   `struct v4l2_stateless_encode_stats` become its own codec-agnostic control
   (for H.264/VP8/AV1) instead of being embedded per codec?
7. **Pixel format naming.** Reuse `V4L2_PIX_FMT_HEVC_SLICE` (proposed), or
   introduce `HEVC_SL` alongside the approved `H264_SL` rename?
8. **SEI / HDR metadata.** The existing `V4L2_CID_COLORIMETRY_HDR10_CLL_INFO`/
   `MASTERING_DISPLAY` controls could make the kernel emit prefix SEI.
   Anything else (user data unregistered, recovery point) needs a generic
   SEI-passthrough design.
9. **TemporalId patching in the core.** It is fine for VEPU580, which writes
   Annex B start codes. Is post-encode patching of the CAPTURE buffer
   acceptable in a helper, or should drivers do it?
10. **Multi-slice and tiles.** Per-slice headers with
    `V4L2_CID_MPEG_VIDEO_MULTI_SLICE_*` (Paul's plan), entry points for
    kernel-written headers (requires a post-pass), and VEPU580 dual-core tile
    encoding (needs a non-m2m scheduler) are all deferred.
11. **SAR.** There is no HEVC VUI SAR control. Paul uses the H.264 ones. Add
    generic `V4L2_CID_MPEG_VIDEO_VUI_SAR_*`?
12. **Interaction with Collabora's Vulkan Video plan for RK3588.** Nicolas
    opposes two interfaces for the same hardware. This uAPI stands on its own
    (it fits VC8000E equally well), but the VEPU580 driver question remains
    political, not technical.

### Review notes on Paul's v1 that came up while doing this

- The encode params write-back cannot reach userspace per request when the
  request sets the control (see 6). A separate feedback control avoids this.
- `v4l2_h264_enc_complete()` must not sleep if a driver calls it from the hard
  IRQ. Any feedback-control update needs process context.
- The bit writer and RC are not reusable outside H.264 as posted.

## 11. What is not supported (v1)

4:2:2/4:4:4, separate colour planes, >1 VPS/SPS/PPS, RPS in SPS, LT pictures
in SPS, custom scaling lists, weighted prediction, lists modification, PCM is
allowed but untested on hardware, tiles/WPP with kernel slice headers,
multi-slice, dependent slices, HRD/SEI, field coding, layered extensions,
SCC/range extensions.

---

## 12. Draft RFC cover letter (not sent)

See `COVER-LETTER.txt` (same text).
