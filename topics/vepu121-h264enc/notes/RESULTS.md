# RK3588 V4L2 stateless H.264 encoder (hantro, Rockchip VEPU2) — results

Branch `opi5/vepu121-h264enc` (worktree `~/orangepi5/work/vepu121-h264enc`), based on
`opi5/hantro-robust-mc`. Build dir `~/orangepi5/build/wt-vepu121-h264enc`.
Tested on the Orange Pi 5 (RK3588S), kernel 7.3.0-opi5 #2, 2026-10-29.

## Key finding: the VEPU121 cores are JPEG-only

The brief targeted the four VEPU121 cores (0xfdba0000/4000/8000/c000). On the RK3588 these
are **JPEG encoders only** (the Rockchip BSP DT calls them `jpege-core`): programmed for
H.264 they raise a normal frame-ready IRQ but write a JPEG scan (stream ends in `FF D9`,
QP_SUM 0). No fault, no hang.

The H.264-capable VEPU2 of the RK3588 is the **encoder half of the VPU121 at 0xfdb50000**
(BSP `vepu@fdb50000`, `rockchip,vpu-encoder-v2`, GIC SPI 120), next to the VDPU2 decoder at
+0x400 that mainline already drives (SPI 119). It shares clocks, power domain (PD_VDPU) and
IOMMU with the decoder. So:
- the H.264 encoder is a **single core**; the 4-core VEPU121 cluster stays JPEG-only;
- encode and decode jobs on the VPU121 share one mem2mem queue (serialised);
- mainline DT had to gain the `vepu` interrupt (commit b5c58f976; binding already allows it).

## Commits (`git log --oneline opi5/hantro-robust-mc..`)

```
557d52c49 DO NOT UPSTREAM: media: v4l2-ctrls: Keep the v4l2-core symbol versions     (ours, deploy only)
b5c58f976 arm64: dts: rockchip: Add the encoder interrupt of the RK3588 VPU121        (ours)
75cea8eda media: verisilicon: Add H.264 encoding to the Rockchip VEPU2 of the RK3588  (ours)
6665187a3 media: verisilicon: Share the H.264 CABAC context initialization table      (ours)
0501550b4 media: h264: Support picture order count type 2 in stateless encode         (ours, core + rbsp)
4bbc2fa31 media: h264: Only write the SPS and PPS of a stateless encode when they ... (ours, fix to Paul 4/14)
dfeeecfc9 media: verisilicon: Add common encoder parm and frameintervals ioctls       (Paul 11/14)
0fde3e94e media: hantro: use hantro_decoded_buffer only for dst_vq                    (Marco Felsch 10/14)
e57b66afd media: verisilicon: Report default pixel coding for non-JPEG and fix ...    (Paul 8/14)
633623e0d..dc7ce80a1  media: h264 / uapi: Paul 1-7/14
```

### uAPI source
Paul Kocialkowski, "[PATCH 00/14] media: Add V4L2 H.264 stateless encode and VC8000E
support", **v1** (2026-05-22, `20260522101653.2565125-1-paulk@sys-base.io`), via `b4 am`;
`b4 am -c` found no v2. Applied 1-7 + the generic hantro patches 8, 10, 11 with original
authorship and an added `Link: https://patch.msgid.link/<msgid>`. Context conflicts fixed by
hand, no code changes. Skipped 9 (already solved on hantro-robust-mc), 12-14 (VC8000E).
Mbox: `~/orangepi5/work/_downloads/vepu121-h264enc/paul-v1/`.

### Fixes to Paul's core (feedback for his v2)
- 4bbc2fa31: the "SPS/PPS changed" check is inverted, so SPS+PPS were emitted before
  every picture.
- 0501550b4: POC type 2 (core POC derivation + the SPS writer, which returned -EINVAL for
  type 2 — found on the board with function_graph tracing).
- Found, not fixed: `state_commit()` publishes the controls before `rc_step()` sets
  `slice_qp_delta`, so the QP fed back to userspace in the request is the pre-RC value
  (the QP actually used is right, see QP_SUM below).

## Design

- Variant `rk3588_vpu121_variant` matched on `rockchip,rk3588-vpu121`: VEPU2 encoder at +0
  (H.264 only; JPEG stays on the VEPU121 cluster) + VDPU2 decoders at +0x400. The `vepu` IRQ
  is optional: with an old DT the encoder is just not registered and decoding is unchanged.
  The RK3568 VEPU / RK3399 / PX30 are not enabled (not tested).
- Coded `V4L2_PIX_FMT_H264_SLICE` (capture); raw NV12M, YUV420M, YUYV, UYVY (output);
  96x96..1920x1088, MB-aligned source; visible size = OUTPUT crop -> SPS frame cropping.
- Requests required on the OUTPUT queue; per-frame `V4L2_CID_STATELESS_H264_ENCODE_PARAMS`;
  controls: SPS, PPS, START_CODE (Annex B only), AU_DELIMITER, PREPEND_SPSPPS_TO_IDR,
  FRAME_RC_ENABLE, BITRATE_MODE (CBR/CQ), BITRATE, CONSTANT_QUALITY, H264_{I,P}_FRAME_QP,
  H264_{MIN,MAX}_QP.
- Paul's core: state/constrain, SPS/PPS/AUD writing by the CPU, frame RC, DPB, internal
  reconstructed buffers (one MB-aligned NV12 buffer each, allocated by the driver).
- The **hardware writes the slice NAL** (start code, header, data). Its slice header has no
  POC (type 2), a 16-bit frame_num, no RPLM/MMCO, always a reference. `state_constrain` forces
  that (and 1 ref, no LTR, no ref-idx override, deblocking-control present, idr_pic_id 4 bits,
  Baseline->CAVLC, non-High->no 8x8); the values used are returned through the controls.
  nal_ref_idc is patched after encode to the requested non-zero value.
- Header splice: SPS/PPS written by the CPU, HW stream base = 8-byte aligned end of headers,
  leftover header bytes in `STR_HDR_REM_MSB/LSB`, bit offset in `STREAM_START_OFFSET`.
  Verified on HW: the HW slice NAL `00 00 00 01 65 ...` follows the PPS exactly.
- Constant QP per picture, frame-level RC from the core using the HW stream size; QP_SUM
  (bits 31:11, x2) read back — **verified equal to the programmed QP** (debug log).
  The HW macroblock RC (checkpoints/MAD) is not used.
- All 184 encoder registers programmed per run (unused ones zeroed).
- CABAC init: hantro's decoder table re-used (checked identical to ChromeOS's encoder
  tables), expanded per QP/idc (3 x 48256 bytes).

Provenance: register programming and mode-decision tables ported from ChromeOS
`chromeos-4.4/drivers/media/platform/rockchip-vpu/rk3399_vpu_hw_h264e.c` (GPL-2.0, Rockchip);
controls follow Paul's VC8000E patch; MPP (`hal_h264e_vepu2_v2.c`, `hal_h264e_stream_amend.c`,
`h264e_api_v2.c`) and the BSP rk3588s.dtsi read for register/HW meaning only.

## Build / checks

- `videodev`, `v4l2-h264`, `v4l2-h264-enc{,-rbsp,-rc}`, `hantro-vpu`: 0 warnings (W=1).
- checkpatch --strict: our commits clean except "MAINTAINERS" for the new file; Paul's
  patches keep their original checks. dtbs_check: no warnings for the VPU node.
- sparse not installed. `tools/build-modules.sh` builds, strips, signs (last) and verifies.

## ABI / deployment

- Paul's uAPI adds a member to `union v4l2_ctrl_ptr` and an enumerator to `enum
  v4l2_ctrl_type`: with gendwarfksyms this changes 86 videodev + 3 v4l2-flash-led-class CRCs.
  The deploy-only tip commit avoids both (generic pointer, `#define`): **0 CRC changes** for
  all existing exports vs `build/linux/Module.symvers`.
- Installed (by the coordinator) in `/lib/modules/7.3.0-opi5/updates/opi5-h264enc/`:
  `videodev.ko v4l2-h264.ko v4l2-h264-enc.ko v4l2-h264-enc-rbsp.ko v4l2-h264-enc-rc.ko
  hantro-vpu.ko` (signed); the board's multi-core `v4l2-mem2mem.ko` is kept (same CRCs).
  The multi-core hantro-vpu.ko was parked in `/var/tmp/parked/`. DTB: the coordinator's
  combined DTB plus the vpu121 `vepu` interrupt hunk.

## Hardware tests (testsrc2, 60 frames, GOP 30 for IPPP, test client depth 2)

v4l2-compliance 1.32 on the encoder: 44/49 OK. The 5 failures are tool limitations, not
driver bugs: v4l2-compliance has no notion of a stateless *encoder* (expects S264 only on an
OUTPUT queue, allows S_PARM/ENUM_FRAMEINTERVALS only for stateful encoders, and reports
"Requests: Not Supported" for this node). Log: `board-logs/compliance.txt`.

All streams decode with **0 ffmpeg errors**; frame types are `2 I + 58 P` for IPPP.
PSNR is Y, mean over frames (frame-aligned with `settb=1/30,setpts=N`).

| Stream | 720p kbit/s @30 | 720p PSNR-Y | 720p fps | 1080p kbit/s @30 | 1080p PSNR-Y | 1080p fps |
|---|---|---|---|---|---|---|
| I-only QP20 | 11404 | 53.92 | 124 | 22016 | 53.35 | 55.6 |
| I-only QP28 | 7632 | 46.88 | 125 | 14564 | 47.04 | 56.0 |
| I-only QP36 | 4507 | 39.42 | 126 | 8486 | 39.83 | 56.5 |
| IPPP QP20 CAVLC | 7461 | 52.66 | 115 | 15711 | 52.97 | 58.4 |
| IPPP QP28 CAVLC | 4300 | 45.59 | 116 | 9151 | 46.28 | 59.2 |
| IPPP QP36 CAVLC | 1734 | 38.71 | 117 | 3777 | 39.27 | 59.5 |
| IPPP QP20 CABAC | 6700 | 52.66 | 107 | 13884 | 52.97 | 53.4 |
| IPPP QP28 CABAC | 3790 | 45.59 | 113 | 7924 | 46.28 | 57.2 |
| IPPP QP36 CABAC | 1570 | 38.71 | 116 | 3345 | 39.27 | 59.5 |
| High + 8x8, CABAC, QP28 | 4045 | 45.63 | 112 | 8511 | 46.38 | 56.7 |
| Constrained Baseline QP28 | 4300 | 45.59 | 117 | 9151 | 46.28 | 58.9 |
| CBR 2 Mbit/s (CABAC) | 1830 (-8.5%) | 39.81 | 116 | 1838 (-8.1%) | 36.54 | 59.6 |
| CBR 8 Mbit/s (CABAC) | 7619 (-4.8%) | 54.98 | 104 | 7337 (-8.3%) | 45.64 | 57.3 |
| CQ 80 (CAVLC) | 1103 | 36.32 | 117 | 2321 | 36.81 | 59.8 |

- CBR adapts QP per frame (e.g. 29, 34, 36, 36, ... at 2 Mbit/s 720p, QP_SUM confirmed);
  accuracy within -5..-9% over 2 s clips (the core's sliding window undershoots a bit).
- Profiles reported by ffprobe: Main / High / Constrained Baseline as requested; CABAC and
  CAVLC give identical reconstruction (same PSNR), CABAC 10-15% smaller.
- Parallel contexts (1080p, QP28 CABAC) on the single encoder: 2 streams 28.8 fps each
  (57.6 total), 4 streams 14.5 fps each (58 total) — the core saturates at ~59 fps 1080p;
  all outputs bit-identical to the single-stream encode.
- Mixed workload: 1080p H.264 encode while H.264-decoding on the same VPU121: 49.2 fps,
  output bit-identical, decodes OK.
- Webcam (Aluratek UVC, YUYV 1280x720, piped live via ffmpeg into the encoder, YUYV input
  path): 90 frames, 0 decode errors, PSNR-Y 47.27 dB; 9.7 fps = camera rate.
- Regressions with the new hantro-vpu.ko: JPEG encode (gst `v4l2jpegenc`, 4-core VEPU121,
  30 frames 720p) OK; VDPU121 H.264 and VP8 decode md5-identical to ffmpeg; MPEG-2 decode
  72.7 dB vs ffmpeg (IDCT rounding); AV1 decode OK; rkvdec H.264 md5-identical.
- dmesg: no IOMMU faults, no watchdog timeouts, no oops during any test.
- Sample streams and logs: `board-logs/` (run.log, compliance.txt, smoke/p_1080_q28/cam720).

## Gaps vs Paul's spec / open items

- HW slice header limits: POC type 2 only, every picture a reference, 1 reference, no LTR,
  no B frames, single slice. Lifting them needs a software slice header and stripping /
  bit-shifting the HW one (what MPP's "stream amend" does).
- QP feedback in the request is stale (core ordering, see above); no average-QP control.
- START_CODE_NONE (AVC) unsupported; DMABUF CAPTURE buffers get CPU header writes without
  CPU-access syncs (as Paul's VC8000E).
- Single-plane NV12/I420 not exposed; encode errors leave a frame_num gap.
- CBR uses only frame-level RC; HW macroblock RC (checkpoints) unused.
- No reset lines for the VPU121 in DT: a timeout is recovered by the IOMMU restore only
  (none happened).
- v4l2-compliance needs stateless-encoder support.

## Upstream notes

- Nothing sent. The two core fixes and the stale-QP-feedback observation are feedback for
  Paul's v2. This is a second Hantro-family implementation (VC8000E + VEPU2); Nicolas wants
  a non-Hantro one too.
- The DT/driver finding (VEPU121 = JPEG only, H.264 = VPU121 VEPU2) matters for anyone
  enabling encode on RK3588 mainline.
- Michael Trimarchi's unposted PX30 H1 port (Sep 2026) overlaps conceptually.
