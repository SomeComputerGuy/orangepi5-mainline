# Codec quality findings from the unattended sweep (kernel build 3)

Board: Orange Pi 5, kernel 7.3.0-opi5 #3 (`patches/linux` = `opi5/integration-7.3`). Fixes are tested as
signed external modules in `/lib/modules/7.3.0-opi5/updates/opi5-codec-quality/` (rockchip-jpegd,
hantro-vpu, rockchip-vdec). Undo: `sudo rm -r` that directory, `sudo depmod -a`, reboot.

Branch `opi5/codec-quality` (worktree `work/codec-quality`, on `opi5/integration-7.3`). Patches are in
`patches/` (branch order) and `patches/stack/` (renamed for `patches/linux`; checked to apply in that
order with an identical result). checkpatch --strict on each: only the intentionally missing
Signed-off-by. Each carries `Assisted-by: Claude:claude-opus-5-5`.

| stack slot | commit | what |
|---|---|---|
| 0610 | media: rkvdec: vdpu381: Compress the co-located motion vectors of H.264 | +4.7% 4K, +9% 1080p H.264 |
| 0611 | media: rkvdec: vdpu381: Compress the co-located motion vectors of HEVC | +2-6% 4K HEVC |
| 0612 | media: rkvdec: Give the HEVC SPS control a default the driver accepts | v4l2-compliance: 2 fails fixed |
| 0715 | media: verisilicon: Support holding the CAPTURE buffer for MPEG-2 | field-coded MPEG-2 decodes at all |
| 0716 | media: verisilicon: Find the second MPEG-2 field without top_field_first | field-coded MPEG-2 decodes correctly |
| 0827 | media: verisilicon: Don't report frame rate ioctls when encoding JPEG | fixes carried 0823; v4l2-compliance |
| 0828 | media: verisilicon: Don't offer VP8 above 1080p on the Rockchip VDPU2 | 4K VP8 accepted then mis-decoded (not yet verified on board) |
| 0904 | media: rockchip: rkjpegd: Return a CAPTURE buffer for undecodable frames | v4l2-compliance hang / corrupt MJPEG |

(0827 carries `Fixes:` for Paul Kocialkowski's posted, not yet merged patch 0823. Upstream it would be a
review comment on, or a follow-up to, his series.)

Tools: `vqcmp.sh` (the corrected PSNR / bit-exact / alignment helper: decodes everything to raw frames
and compares by index, with no container timestamps), `codecsweep.sh` (the sweep with its measurement
bugs fixed), `scripts/mpeg2-conf.sh` (MPEG-2 conformance, HW vs FFmpeg), `scripts/run-fluster.sh` (fluster
per device, with a private fluster copy that adds `GStreamer-<codec>-V4L2SL-RKVDEC/-HANTRO`),
`scripts/elem.sh` (GStreamer element for a codec on a device; the names change with /dev/video
numbering on every boot), `scripts/trace-dec.sh` + `parse.py` (per-frame decoder timeline),
`scripts/verify2.sh` (final verification), `tools/v4l2-jpeg-dump.c` (dumps a whole rkjpegd CAPTURE
plane, padding included, from a poisoned buffer), `rkvdec-colmv-debug-instrumentation.diff` (the debug
module used for the colmv experiment, not for merging).

## Verdicts

| # | Sweep finding | Verdict | Fix |
|---|---|---|---|
| 1 | Hantro MPEG-2 0/30 bit-exact | Not a bug: the IDCT doesn't have to be bit-exact (aligned, 64.7 dB vs FFmpeg). But conformance testing found 2 **real bugs**: field-coded MPEG-2 doesn't decode (rejected), and once accepted, second fields used the wrong reference | 0715, 0716 |
| 2 | VEPU580 HEVC ~32 dB | **Measurement bug** (1 ms mkv timestamps, so every 3rd frame was compared with the wrong source frame). Real: 39.2/41.0/42.1 dB at 360p/720p/1080p, within 0.4 dB of x265 at the same QP and size | script |
| 3 | VEPU580/VEPU2 H.264 PSNR empty | **Measurement bug** (FFmpeg can't probe raw H.264 named `.es`). Real: 38.6/38.1 dB at 360p, within ~1 dB of x264 | script |
| 4 | JPEG 12.3 dB at 360p (and 1080p) | **Measurement bug** (v4l2jpegdec buffers are sizeimage-sized, 368 lines for 360, and filesink writes them out whole). Real: 36.5 dB, the same as FFmpeg decoding the same JPEGs (63 dB HW vs SW). Found a **real bug**: v4l2-compliance hangs on rkjpegd | 0904 |
| 5 | rkvdec H.264 4K ~65 fps | The hardware is the limit (99% busy, B-frames 16 ms each). Enabling colmv compression as the vendor does: **65.4 → 68.4 fps**, output identical | 0610, 0611 |
| - | VPU121 decoder wedged during the sweep | Real, but **not reproduced** with the patched modules (4 runs of v4l2-compliance overlapping decoding and encoding). Open, see below | - |
| - | v4l2-compliance fails (vpu121-dec 6, rkvdec 8, vepu121-enc 5, vpu121-enc 5, rockchip-venc 5) | rkvdec 2 and vepu121-enc 5 were driver bugs (fixed). The rest are tool limitations (explained below) | 0612, 0827 |

## 1. MPEG-2 on the Hantro G1/VPU2 (RK3588 VPU121)

**Sweep clip (not a bug).** `ref_mpeg2_640x360_30.mkv`, GStreamer vs FFmpeg, raw I420:
- 240/240 frames. Alignment scan: shift 0 = 64.96 dB, shift ±1 = 29.7 dB. So there's no B-frame or
  order offset.
- PSNR Y 63.7 / U 67.2 / V 69.0 dB. The worst frame is 62.2 dB, and the error doesn't grow over the
  GOP.
- I-frame difference histogram: {-1: 96, 0: 340981, +1: 4523}. Only rounding.
- MPEG-2 only requires IEEE 1180 IDCT accuracy, and FFmpeg's own IDCTs aren't bit-exact with each other
  either (`-idct simple` 75.2 dB, `int` 62.6, `faani` 64.9 vs the default; the hardware is closest to
  `faani`, at 72.1 dB).
- The sweep's bit-exact criterion was wrong for MPEG-2. `codecsweep.sh` now reports PSNR when a test
  isn't bit-exact and counts MPEG-2 against 55 dB.

**Conformance** (ISO/IEC 13818-4 vectors from fluster MPEG2_VIDEO-MAIN. The suite ships no checksums,
so FFmpeg is the reference: `scripts/mpeg2-conf.sh`, which runs FFmpeg with `-fps_mode passthrough`
because its default CFR output duplicates 3:2-pulldown frames). Avg/min PSNR vs FFmpeg:

| stream | stock build 3 | + 0715 (hold) | + 0716 (second field) |
|---|---|---|---|
| sony-ct1 / ct2 / ct3 / ct4 | rejected (0 frames) | 34.8 / 34.5 / 67.5 / 32.6 | **52.9 / 54.5 / 67.5 / 66.7** |
| tcela-8 / 9 / 10 | rejected | 11.3 / 10.1 / 24.8 | **63.6 / 56.3 / 63.9** |
| hhi_burst_short / long | rejected (1 frame) | 66.6 / 65.6 | 66.6 / 65.6 |
| all 26 frame-picture streams | 61-67 dB (2 bit-exact) | unchanged | unchanged |

- **Bug A (0715):** GStreamer sets `V4L2_BUF_FLAG_M2M_HOLD_CAPTURE_BUF` on the first field of a
  field-coded frame. hantro allowed holding only for H.264, so the request was refused ("Driver does
  not support holding capture buffer") and every field-coded stream stopped. Interlaced DVD and
  broadcast MPEG-2 didn't play at all.
- **Bug B (0716):** to tell the second field of a frame (which predicts from the first field in the
  same buffer), the G1 and VPU2 back-ends used `V4L2_MPEG2_PIC_FLAG_TOP_FIELD_FIRST`. But
  top_field_first is always 0 in field pictures (13818-2 §6.3.10), so in a top-first frame the top
  field was treated as the second field and the bottom field as the first. The fix tracks
  "opposite-parity field with the same OUTPUT timestamp as the previous field" in the context. The
  uAPI has no flag for this. It also removes the VPU2 code's test of `V4L2_MPEG2_PIC_TOP_FIELD` (a
  picture_structure value) against the flags.
- **Remaining, not fixed:**
  - *sony-ct1/2* (frames 36-43 and 48-55 at 42-51 dB, recovering at each I-frame). This is a specific
    GOP in these mixed frame/field streams; not analysed further.
  - *tcela-9* (one I-frame, then 60 field P-frames, with a monotonic drift from 65 to 54 dB). This is
    consistent with IDCT-mismatch accumulation over a long GOP.
  - *teracom_vlc4* (I-frame bit-exact, chroma exact, luma 37 dB). The errors are isolated ±255
    pixels in a few macroblocks of this extreme-VLC/coefficient stream, and they don't propagate.
    Hardware vs FFmpeg saturation; deciding who's right needs the ISO reference output.
  - *att* (32x32): below the decoder's 48x48 minimum, so the output is blank. The driver should
    refuse the size rather than accept it.
  - *MEI, MEI.stream16, ccm1, tcela-16/19*: MPEG-1. `v4l2slmpeg2dec` only accepts mpegversion=2
    (a GStreamer limit).
  - *tcela-18*: FFmpeg decodes 0 frames as well.

## 2-3. VEPU580 HEVC / H.264 and VEPU2 H.264 PSNR

Measurement bugs: see the PART 1 analysis, unchanged. `ffmpeg -r 60 -i out.es -c copy out.mkv` writes
1 ms timestamps, and the psnr filter's framesync pairs them with the source's exact 1/60 s. Per-frame
luma of the sweep's own command: 40.0, 38.9, **28.8**, 38.7, 38.7, **28.8**, ... For H.264, FFmpeg
doesn't probe `.es`, so no mkv was written. Corrected (vqcmp: the raw ES decoded and matched by frame
index; the alignment scan shows no dropped or duplicated frames):

| 240 frames @60 | bytes | Y | avg | worst Y |
|---|---|---|---|---|
| VEPU580 HEVC 360p QP26 | 1890196 | 38.23 | **39.24** | 37.9 |
| x265 medium QP26, bframes 0 | 1992994 | 38.59 | 39.67 | 39.3 |
| x265 medium, same bit rate | 1968859 | 38.48 | 39.58 | 37.3 |
| VEPU580 HEVC 720p / 1080p | 5611140 / 9698207 | 40.17 / 41.48 | **40.97 / 42.12** | |
| VEPU580 H.264 360p QP26 | 2051737 | 37.45 | **38.60** | 37.2 |
| VEPU2 H.264 360p | 1983255 | 37.00 | **38.09** | 36.6 |
| x264 medium QP26, bf 0 | 2133039 | 38.66 | 39.74 | |
| VEPU580 H.264 720p / 1080p | | 38.50 / 40.11 | 39.61 / 41.06 | |
| VEPU2 H.264 720p / 1080p | | 38.55 / 39.71 | 39.53 / 40.56 | |

That's normal hardware-encoder quality. The earlier 46 dB was on synthetic content.

## 4. VEPU121 JPEG → rkjpegd

Isolation:
- The encoder is fine: FFmpeg decodes its JPEGs at 36.7 / 39.2 / 41.0 dB vs the source.
- rkjpegd's layout is as advertised: a poisoned-buffer dump of NV12 640x368 (bpl 640, compose 640x360)
  shows rows 360-367 fill-down replicated, and chroma at row 368.
- GStreamer re-lays the frame into the default layout inside a sizeimage-sized (353280-byte) buffer,
  and `filesink` writes it out whole, so the reader drifts.
- Corrected: HW 36.54 / 39.04 / 40.85 dB vs source, 63.3 dB vs FFmpeg's decode of the same files.
  FFmpeg-made 640x360 JPEGs through rkjpegd: 66.6 dB vs FFmpeg.

**Bug (0904):** an undecodable OUTPUT buffer (an invalid header) completed with ERROR from buf_queue(),
and no CAPTURE buffer was ever returned for it. v4l2-compliance -s blocked forever in
DQBUF(CAPTURE): the sweep's video1 line is empty (900 s timeout). A corrupt camera MJPEG frame does the
same to a real client. Such buffers now go through a job and return a CAPTURE buffer flagged ERROR
(payload 0, LAST kept on drain), as mxc-jpeg does. **Verified:** v4l2-compliance -s -f now passes
57/57, and the 640x360 JPEG decode is unchanged (63.28 dB vs FFmpeg).

## 5. rkvdec H.264 4K speed

Trace (`ref_h264_3840x2160_60.mkv`: x264 veryfast CRF 20, High, B-frames, 48 Mbit/s; fakevideosink):
the hardware is busy 99% (DEC_E→IRQ 14.25 ms mean), kernel per frame IRQ→handler 72 us + handler→next
DEC_E 144 us, and 235 of 240 frames start from the m2m kworker (the queue never runs dry). By frame
type: I 7.0 ms, P 10.8 ms, **B 16 ms**. Neither the kernel nor GStreamer queueing is the bottleneck.
One stream can't use the second core (one m2m job per context, and the frames depend on each other).
Vendor spec: 8K@30 H.264 (= 4K@120) for both cores together.

The only B-frame-relevant difference from MPP (`hal_h264d_vdpu34x.c`): `reg012.colmv_compress_en`
(H.264 frame_mbs_only, and HEVC always). Experiment with a debug module (all toggles default off, no
display used):
- Bytes the hardware wrote into a poisoned colmv area: H.264 4K uncompressed exactly 4147200 (=128
  B/MB, mainline's size), compressed up to 4146800. HEVC 4K uncompressed 522240, compressed
  **556064-556128 (content-dependent, larger)**. So the compressed layout gets the vendor's bound
  (64x16 segments, 1 KiB payload + header): 8.3 MB instead of 4.1 MB per 4K buffer.
- All 240 frames give the same checksum with compression off and on (H.264 4K, H.264 1080p, HEVC 4K),
  and the first 30 frames are bit-exact with FFmpeg.

| fakevideosink, 240 frames | off | on |
|---|---|---|
| H.264 3840x2160 | 65.9 / 64.8 fps | **68.9 / 68.0** |
| H.264 1920x1080 | 212 / 216 | **225 / 244** |
| HEVC 3840x2160 | 102.8 / 94.5 | **104.6 / 104.7** |

Final module (0610+0611): H.264 4K 67.96 fps, HEVC 4K 103.6 fps, 30/30 bit-exact for both
(`verify2.txt`). 4K120 H.264 from one stream is still beyond one core. That's the hardware limit, not
the kernel's.

## VPU121 decoder wedge (sweep, 22:02 on boot 1)

What happened: while the sweep ran `v4l2-compliance -s -f` on the VPU121 nodes, with my MPEG-2 runs on
the same device (the then-stock module refused field-picture requests, so GStreamer aborted mid-stream
repeatedly), `rk_iommu fdb50800: Disable paging request timed out`, then `Enable stall request timed
out` on every runtime-PM cycle. Every decode failed until the reboot, and there was no hantro timeout
message. The VPU121 encoder and decoder are one device (fdb50000) behind one IOMMU; m2m serialises
them (max_parallel_jobs = 1).

Reproduction on the patched modules, 4 attempts: compliance on dec alone; dec compliance + MPEG-2
decode loop; 2x (enc + dec compliance) + decode loop. Clean: 0 IOMMU messages, all decodes rc=0. The
original trigger involved the request-refusal and abort path that 0715 removes, so it's either fixed
by 0715 or needs that path. Hypothesis: a job stopped or torn down while the core still had AXI
transactions outstanding, after which the IOMMU couldn't stall. Not proven; open. Suggested check:
the stock module + a field-coded stream (refused request) in a loop, alongside v4l2-compliance.

## decodebin3 picks the 1080p Hantro decoder for 4K H.264 (reported by the coordinator)

Reproduced: `uridecodebin3` on `ref_h264_3840x2160_60.mkv` instantiates `v4l2slh264dec` (VPU121) and fails
("Failed to configure H264 decoder"). With `GST_PLUGIN_FEATURE_RANK=v4l2slh264dec:NONE` it takes the
rkvdec element and plays to the end. The kernel reports VPU121's limits correctly: ENUM_FRAMESIZES on
S264 and MG2S is stepwise 48x48 to 1920x1088. GStreamer v4l2codecs registers every device with the
codec's static sink template (no width/height) at the same rank, so decodebin3 can't tell the elements
apart and doesn't fall back. That's a GStreamer fix: per-device sink caps from ENUM_FRAMESIZES. Written up
as item 8 in `work/_out/GSTREAMER-FOLLOWUPS.md`.

While checking this, I found a kernel bug: VPU121's VP8 OUTPUT range was 3840x2160, but its NV12 CAPTURE
format is clamped to 1920x1088 (`v4l2-ctl` S_FMT VP8F 3840x2160 then G_FMT CAPTURE gives 1920x1088). A 4K
VP8 stream was accepted and then mis-decoded (GStreamer `info->width <= meta->width` assertions, 0/10
frames match). **0828** limits VP8 to 1080p in the VDPU2 and RK3399 tables, the only size their CAPTURE
format allows. (Module installed, verification pending a reboot.) Also: rkvdec's VDPU381 ranges
(1x1-65520) are far above the hardware's real limits (not changed).

## v4l2-compliance -s -f (final modules)

| node | build 3 | now | remaining failures |
|---|---|---|---|
| rockchip-jpegd | hung (timeout) | **57/57** | - |
| rkvdec | 50/58 | **52/58** | 6x QBUF EBADR (see below) |
| vpu121-dec | 52/58 | 52/58 | 6x QBUF EBADR |
| vepu121-enc (JPEG) | 61/66 | **65/66 → 66/66 expected** (the device-level part of 0827 is installed but needs a reboot) | (G/S_PARM with invalid type: the core returns EINVAL before the driver's ENOTTY) |
| vpu121-enc (H.264+JPEG) | 61/66 | 61/66 | tool: stateless encoder |
| rockchip-venc (VEPU580) | 97/102 | 97/102 | tool: stateless encoder |

- **EBADR** (both stateless decoders): `VIDIOC_QBUF(OUTPUT) = -1 EBADR` (strace). The queue
  requires the Request API, and v4l2-compliance's streaming tests don't build requests. That's
  expected for every stateless decoder.
- **rkvdec try_ext_ctrls/STREAMON** (0612): the default (all-zero) HEVC SPS has chroma_format_idc 0,
  which `rkvdec_hevc_validate_sps()` refuses. This is a mainline issue.
- **JPEG encoder** (0827): the carried patch 0823 gave all hantro encoders ENUM_FRAMEINTERVALS and
  G/S_PARM. v4l2-compliance requires -ENOTTY for them on m2m devices that aren't stateful video
  encoders (JPEG encoders included). The failure cascades into ENUM_FMT/G_FMT/TRY_FMT/S_FMT ("not
  reported by ENUM_FMT"), because the format test aborts early.
- **Stateless H.264/HEVC encoders** (vpu121-enc S264, VEPU580): the same 5 tests, because
  v4l2-compliance 1.32 doesn't know the proposed stateless encode uAPI (patches 0802/0812, not
  upstream). It classifies the nodes as "not a stateful encoder" and forbids the frame-rate ioctls,
  which that uAPI requires for rate control. So v4l2-compliance needs updating alongside the uAPI.
  Not a driver bug.

## Fluster

Stock `GStreamer-H.264-V4L2SL` runs `v4l2slh264dec`, which is the Hantro G1 here: **rkvdec H.264
was never tested by the sweep's fluster**. `run-fluster.sh` tests each device.

Not completed: the run was stopped (user credits). The first attempt ran nothing (`timeout` can't
call a shell function, now fixed in `run-fluster.sh`). The rerun was still verifying vectors. To
finish: `~/cq/run-fluster.sh` on the board, then read `~/cq/fluster-results.txt` (VP8 Hantro, VP9 rkvdec,
H.264 JVT-AVC_V1 on rkvdec and Hantro, JVT-FR-EXT rkvdec, HEVC rkvdec, AV1). Pay particular attention to
the H.264/HEVC results with the colmv patches 0610/0611 (field/MBAFF vectors stay uncompressed by
design).

## Status at stop (2026-10-29 ~23:15)
- Board: the hantro-vpu.ko with 0827 (device-level part) and 0828 is installed in updates/opi5-codec-quality
  but hasn't been loaded yet (it needs a reboot). Verified on the board: 0904, 0715, 0716, 0610-0612, and
  the runtime part of 0827 (vepu121-enc 65/66).
- The CCU agent's rockchip-vdec includes 0610-0612 and replaced mine in updates/.
- Open: the VPU121 wedge (not reproduced), the residual MPEG-2 deviations (sony-ct1/2 GOP, tcela-9 drift,
  teracom, att size), fluster, and v4l2-compliance updates for the stateless-encoder uAPI.
