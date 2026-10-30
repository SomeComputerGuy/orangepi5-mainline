# Measured results (2026-10-29/30)

This is a summary of what was measured on the Orange Pi 5 test board on 2026-10-29 and in the night
to 2026-10-30, with the command that produced each number, where it ran, and the kernel it ran on.
Only numbers that were written down at the time are given here; where a source is ambiguous it says
so. The detailed notes (more tables, analysis, raw logs) are linked in each section.

How to re-run any of this: [`TESTING.md`](TESTING.md). The clips: [`TEST-MEDIA.md`](TEST-MEDIA.md).

## Test setup

- Board: Orange Pi 5 (RK3588S, 8 GB), booting from an M.2 SATA SSD (`rk3588s-orangepi-5-sata` DTB).
  Gigabit Ethernet to the host.
- Displays: a TCL TV on HDMI0 (3840x2160 at 60 Hz TMDS/FRL and 120 Hz FRL) and a Dell P2415Q on the
  USB-C port through a USB-C hub with a DP-to-HDMI converter (2 lanes HBR2, 3840x2160 at 30 Hz).
- Software: Ubuntu 26.10 arm64 server image built from this repository, GStreamer 1.28.x
  (v4l2codecs, kmssink, waylandsink under weston), the board's Ubuntu FFmpeg as the software
  reference decoder.

### Kernels

| Name | What | Used for |
|---|---|---|
| **build 3** | `7.3.0-opi5 #3 SMP PREEMPT_DYNAMIC Thu Oct 29 20:03:17 UTC 2026`, package `7.3.0-3`, `patches/linux` at 292 patches. Installed and validated by `tests/k3-validation/run-k3.sh`. Its DTB predates 1005 (DP alt mode), so the board ran it with the DTB built from the integration branch with 1005 | almost everything below |
| build 3 + drop-in modules | build 3 with signed modules from a topic branch in `/lib/modules/7.3.0-opi5/updates/opi5-<topic>/` (and, for audio and CCU, a DTB built from that branch) | the per-topic verifications (VOP2, DP, audio, codec fixes, CCU) |
| build 2 | `7.3.0-opi5 #2`, the build with the GPU/NPU patches 0501-0514 (Oct 29 17:38 UTC) | GPU/NPU and suspend |
| build 4 | `patches/linux` at 309 patches (everything above except the CCU work). Built on the host on 2026-10-29/30, **not installed or tested on the board yet** | - |

The image kernel built from today's `patches/linux` contains every fix listed below as verified,
except the rkvdec CCU work, which is not in `patches/linux`.

## 1. Codec sweep: decoders

- Command (board): `nohup sudo bash ~/codecsweep/codecsweep.sh > ~/codecsweep/run.log 2>&1 &`
  ([`tests/codec-sweep/`](../tests/codec-sweep/)). Report: `~/codecsweep/report.txt`.
- Kernel: build 3. Run 2026-10-29 20:50:44, directly after the mode sweep.
- This run used the first version of `codecsweep.sh`. Its decoder part is the same as the
  published, corrected script (which only adds a PSNR column when a test isn't bit-exact); its
  encoder and JPEG PSNR numbers had measurement bugs, see section 2.
- Method: per codec, resolution and frame rate, a reference encode made on the board with FFmpeg
  (240 frames of UVG YachtRide, see TEST-MEDIA.md), decoded by every capable hardware decoder through
  GStreamer v4l2codecs. **Bit-exact** = the first 30 frames (I420) identical to FFmpeg's software
  decode. **fps** = 240 frames through `fakevideosink sync=false`, wall clock including pipeline
  start-up. Each clip was also shown for 6 s on HDMI and on DP (Esmart planes 59/65):
  `display_underflow` was 0 for every line.

Result: **every H.264, HEVC, VP9, AV1 and VP8 test is 30/30 bit-exact** at every resolution and
frame rate. MPEG-2 is 0/30 bit-exact at every size, which is allowed (see below).

| Codec | Decoder | 640x360 | 1280x720 | 1920x1080 | 2560x1440 | 3840x2160 |
|---|---|---|---|---|---|---|
| H.264 | rkvdec (VDPU381) | 1100.9 / 1066.8 / 1089.8 | 451.66 / 451.12 / 441.02 | 219.77 / 234.95 / 231.54 | 136.43 / 135.04 / 134.34 | 66.938 / 65.584 / 65.130 |
| H.264 | Hantro G1 (VPU121) | 552.17 / 559.01 / 556.67 | 181.14 / 180.44 / 180.67 | 85.305 / 84.930 / 84.717 | - | - |
| HEVC | rkvdec | 1280.3 / 1307.4 / 1336.3 | 628.41 / 632.41 / 632.63 | 347.46 / 342.58 / 347.85 | 208.12 / 210.16 / 177.08 | 101.65 / 102.29 / 102.60 |
| VP9 | rkvdec | 676.74 / 927.72 / 1073.4 | 500.47 / 572.74 / 606.92 | 348.77 / 363.82 / 384.61 | 224.02 / 227.20 / 230.96 | 123.64 / 125.29 / 129.22 |
| AV1 | AV1 VPU (VPU981) | 359.02 / 519.86 / 645.64 | 273.09 / 357.78 / 426.95 | 198.30 / 242.34 / 271.68 | 145.49 / 168.89 / 180.39 | 82.720 / 89.205 / 88.723 |
| VP8 | Hantro G1 | 517.70 / 604.88 / 619.67 | 209.69 / 193.61 / 186.79 | 87.822 / 84.796 / 83.359 | - | - |
| MPEG-2 | Hantro G1 | 521.77 / 520.30 (0/30) | 171.98 / 171.74 (0/30) | 83.128 / 83.102 (0/30) | - | - |

Cells are decode fps for the 30 / 60 / 120 fps clips of that size (MPEG-2: 30 / 60 only; MPEG-2
has no 120 fps frame-rate code). All cells except MPEG-2 are 30/30 bit-exact. "-" = above the
decoder's limit (Hantro G1: 1920x1088), not tested.

**MPEG-2 is not a bug.** MPEG-2 only requires IEEE 1180 IDCT accuracy, and FFmpeg's own IDCTs
aren't bit-exact with each other. On the sweep's 640x360 clip, hardware vs FFmpeg: 240/240 frames,
alignment shift 0 = 64.96 dB (shift +-1 = 29.7 dB), PSNR Y 63.7 / U 67.2 / V 69.0 dB, worst frame
62.2 dB, I-frame differences only +-1. The notes' verdict line gives this as "64.7 dB vs FFmpeg";
the detailed figures are the ones above. The corrected sweep counts MPEG-2 against 55 dB.

Conformance testing (ISO/IEC 13818-4 vectors from fluster `MPEG2_VIDEO-MAIN`, `mpeg2-conf.sh`)
found two real MPEG-2 bugs: field-coded streams were rejected, and second fields used the wrong
reference. Fixed by stack patches 0715 and 0716 (`topics/codec-quality`); with them, e.g. sony-ct1/
ct2/ct3/ct4 reach 52.9 / 54.5 / 67.5 / 66.7 dB and tcela-8/9/10 reach 63.6 / 56.3 / 63.9 dB average
PSNR vs FFmpeg (they were rejected before).

Same day, the k3 validation run (`tests/k3-validation/run-k3.sh` on the host, build 3,
2026-10-29 20:31) checked the `~/demo` YachtRide encodes: rkvdec HEVC 4K120, AV1 1080p120, G1 H.264
1080p120 and G1 VP8 1080p120 30/30 bit-exact, G1 MPEG-2 0/30 (as above).

rkvdec H.264 4K is at about 65-68 fps on one core: the hardware is 99 % busy (B-frames 16 ms each).
Patches 0610/0611 (co-located MV compression, as the vendor does) raised it from 65.4 to 68.4 fps
with identical output; final modules 67.96 fps H.264 4K and 103.6 fps HEVC 4K, 30/30 bit-exact
(`verify2.sh`). More than that from one stream needs both cores (section 6).

Details: [`topics/codec-quality/notes/RESULTS.md`](../topics/codec-quality/notes/RESULTS.md).

## 2. Codec sweep: encoders (corrected)

The first sweep reported VEPU580 HEVC at ~32 dB, empty PSNR for H.264 and 12.3 dB for JPEG. Those
were **measurement bugs** in the sweep (1 ms timestamps from a `-r 60 -c copy` remux paired every
third frame with the wrong source frame; FFmpeg can't probe raw H.264 named `.es`; JPEG buffers
written out at their padded size). The corrected numbers, decoded to raw frames and compared by
frame index with `vqcmp.sh` (`vqcmp.sh psnr <stream.es> <src.nv12> <WxH>`, board, build 3 with the
codec-quality modules), 240 frames at 60 fps, QP 26:

| Encoder | 360p avg PSNR | 720p avg PSNR | 1080p avg PSNR |
|---|---|---|---|
| VEPU580 HEVC (`rkvenc-enc -e hevc`) | **39.24** dB (Y 38.23, worst Y 37.9; 1890196 bytes) | **40.97** dB (Y 40.17; 5611140 bytes) | **42.12** dB (Y 41.48; 9698207 bytes) |
| VEPU580 H.264 (`rkvenc-enc -e h264`) | **38.60** dB (Y 37.45, worst Y 37.2; 2051737 bytes) | 39.61 dB (Y 38.50) | 41.06 dB (Y 40.11) |
| VEPU2 / VPU121 H.264 (`v4l2-h264-slenc`) | **38.09** dB (Y 37.00, worst Y 36.6; 1983255 bytes) | 39.53 dB (Y 38.55) | 40.56 dB (Y 39.71) |
| VEPU121 JPEG -> rkjpegd | 36.54 dB | 39.04 dB | 40.85 dB |

For comparison at 360p: x265 medium QP26 without B-frames 39.67 dB (1992994 bytes), x264 medium
QP26 without B-frames 39.74 dB (2133039 bytes). So the hardware encoders are within 0.4 dB (HEVC)
and about 1 dB (H.264) of the software encoders: **38-42 dB, normal hardware-encoder quality.** The
JPEG decoder output matches FFmpeg's decode of the same JPEGs at 63.3 dB. 4K encode speed (k3
validation, `demo.sh enc-hevc` / `enc-h264`): VEPU580 HEVC 600 frames 3840x2160 in 15.273 s = 39.29
fps at 60 Mbit/s CBR; VEPU580 H.264 54.09 fps; VEPU2 H.264 1080p 58.3 fps.

Other codec fixes found by the sweep and verified on the board: rkjpegd hang on undecodable frames
(0904; v4l2-compliance now 57/57), JPEG encoder frame-rate ioctls (0827), rkvdec HEVC SPS default
(0612). VDPU2 VP8 limited to 1080p (0828) is installed but its board verification needed a reboot
that hadn't happened when the notes were written. Fluster for the codec-quality modules did not
complete. Details: [`topics/codec-quality/notes/RESULTS.md`](../topics/codec-quality/notes/RESULTS.md).

## 3. Display mode sweep

- Command (board): `nohup sudo bash ~/modesweep/modesweep.sh > ~/modesweep/run.log 2>&1 &`
  ([`tests/modesweep/`](../tests/modesweep/)). Report: `~/modesweep/report.txt`.
- Kernel: build 3, before the VOP2 fix. Run 2026-10-29 20:39:50 to 20:50:35.
- Every mode of each connector, 4 s with a `modetest` pattern, then the same mode with a
  full-screen NV12 overlay on an Esmart plane; counts VOP `POST_BUF_EMPTY` (underflow) and failures.
  HDMI-A-1 offered 39 modes, DP-1 35 modes.

Result (the report's summary line): **`tests: 150  with underflow: 1  rc!=0: 0`**. Every mode set
and displayed; the one failure was `HDMI-A-1 3840x2160-120.00 +overlay59 NV12 ... underflow=10`
(4K120 with a full-screen NV12 overlay). That case is the VOP2 AXI-port bug fixed by patches
1301-1302 (section 5), which brought exactly this configuration to 0 bad frames. The mode sweep
itself has not been re-run on a kernel with 1301-1302.

Note on the count: in the script as it ran, the per-plane format loop read its input from
`/dev/null` (`done < /dev/null` after the pipe), so it ran no tests. 150 = 39 x 2 + 35 x 2 = 148 mode
tests plus the 2 dual-display tests. Per-plane formats were therefore not covered by this run. The
published `tests/modesweep/modesweep.sh` has this fixed (2026-10-30), so a re-run also covers every
format on every plane and reports more than 150 tests. That part has not been run on the board yet.

## 4. Network streaming (netstress)

- Commands: host `python3 -I tests/netstress/rangeserver.py "$OPI5_HOST_IP" 8099 <media dir>`;
  board `bash ~/netstress/netstress.sh http://$OPI5_HOST_IP:8099 30` (30 s per case)
  ([`tests/netstress/`](../tests/netstress/)). Report: `~/netstress/report.txt`.
- Kernel: build 3 (from the report header; the report doesn't list which drop-in modules were
  installed at the time). Runs 2026-10-29 23:33 and 23:38-23:41.
  Decoding on rkvdec (`v4l2slvideo6h264dec`, `v4l2slh265dec`), shown full-screen through weston.

Raw line rate (k3 validation, `run-k3.sh`, a TCP throughput helper on host and board): board to host
941 Mbit/s, host to board 943 Mbit/s.

| Case | Frames (30 s) | Network | NIC errors | CPU (8 cores) | VOP underflows |
|---|---|---|---|---|---|
| Jellyfish 120 Mbit/s 4K H.264 -> HDMI | 894 rendered, 0 dropped | 126 Mbit/s | rx_errs +0, rx_drop +0 | 3 % | 0 |
| Jellyfish 250 Mbit/s 4K H.264 -> HDMI | 887 rendered, 0 dropped | 261 Mbit/s | 0, 0 | 6 % | 0 |
| Jellyfish 250 -> HDMI + Jellyfish 120 -> DP (both cores) | HDMI 887 / 0; DP 708 / 176 dropped | **387 Mbit/s** | 0, 0 | 17 % | 0 |
| Jellyfish 250 -> HDMI + Big Buck Bunny 4K60 -> DP | HDMI 886 / 0; DP 887 rendered, 1134 dropped | **279 Mbit/s** | 0, 0 | 6 % | 0 |
| 400 Mbit/s 4K HEVC Main10, decode only (`fakevideosink`) | **900 rendered, 0 dropped** | 419 Mbit/s | 0, 0 | 6 % | 0 |

- The Jellyfish 250 + 120 pair is from an earlier version of `netstress.sh` (the published one runs
  Jellyfish 250 + Big Buck Bunny instead). Its 176 DP drops were not explained in the notes; the
  clip is 29.97 fps and the DP output runs at 30 Hz, and weston's DP pacing was suspected but not
  confirmed.
- With Big Buck Bunny, DP shows ~30 fps, the full 30 Hz refresh of that display. The 1134 "dropped"
  are the extra frames of 60 fps content on a 30 Hz screen.
- The 400 Mbit/s HEVC Main10 clip decodes in real time (900/900 frames). An earlier run gave 762
  frames at 376 Mbit/s while the file was still being downloaded to the host.
- The Tears of Steel + Big Buck Bunny pair was not run (the transcode wasn't finished).

## 5. VOP2 underflow (HDMI 4K120 + overlay, dual display)

Root cause: RK3588 VOP2 fetches through two AXI read ports and mainline put every active window on
AXI0, which saturates at about 4.5-5 GB/s. Fix: stack patches 1301 (balance window fetches across
both ports) and 1302 (report `POST_BUF_EMPTY` at most once per frame).

- Tools (board): `tests/vop2-underflow/` (`planetest.c`, `rc.sh <label> <planetest args>` for the
  atomic plane tests, `vm.sh <label> <hdmi mode> <dp mode|-> <load 0|1> <secs>` for the kmssink
  matrix). The per-row arguments were not recorded beyond the case descriptions below.
- Kernel: build 3 with the fixed module in `updates/opi5-vop2` (it also contained 1101). Boots of
  22:33, 22:45 and 23:17 on 2026-10-29.

planetest, 4K120, 6 s (720 frames), bad frames:

| Case | Before (IRQ/s) | After (bad frames / 720) |
|---|---|---|
| C0 XR24 + E0 NV12 (the kmssink case), DP Cluster1 on | ~90k/s | **0** |
| C0 + E2 NV12 | 0 | 0 |
| C0 XR24 + E0 XR24, DP off | ~120k/s | **0** |
| C2 + E3 XR24, DP off | ~100k/s | **0** |
| E0 + E1 XR24, DP off | ~90k/s | **0** |
| C0 XR24 + E0 XR24 + DP C1 XR24 4K30 | ~120k/s | 279 (over the hardware limit: three full-screen RGB layers) |
| C2+E2 / C2+E3 / E0+E1 XR24 + DP C1 | - | 108-253 (same) |

kmssink with `skip-vsync=true`, `v4l2slh265dec`, 9 s window ("decode" = a concurrent 4K120 HEVC
decode as load):

| Case | Load | Bad frames | Rendered / dropped |
|---|---|---|---|
| HDMI 4K120 + NV12 overlay | idle / decode | **0** / **0** | 208 / 0, 202 / 2 |
| HDMI 4K60 + overlay | idle / decode | **0** / **0** | 196 / 2, 189 / 5 |
| HDMI 4K120 + DP 4K30, overlay on DP | idle / decode | **0** | DP 189 / 1 |
| HDMI 4K120 + DP 4K30, overlay on HDMI | decode | **0** | 209 / 1 |
| Dual-display weston demo (HDMI 4K60 + DP 4K30, two BBB players), 10+ min | real | **0** | - |
| BBB 4K60 H.264 on HDMI over the console, ~4 min | real | **0** | - |
| 60 s YachtRide HEVC loop at 4K120 + overlay | idle | **0** | - |

The few drops come at pipeline start. Open: kmssink renders ~60-63 fps of 120 fps content at
4K120 because of its blocking legacy SetPlane path (decode alone reaches 125 fps; planetest atomic
flips run 120/120). Details:
[`topics/vop2-underflow-int/notes/RESULTS.md`](../topics/vop2-underflow-int/notes/RESULTS.md).

## 6. Dual display and smooth DP playback (dp-smooth)

- Tools (board): `tests/dp-smooth/` (`opi5-play`, `flipmeasure.sh <tag> <conn> <plane> <clip> 8 [props]`
  + `cadence.py`), clips `~/codecsweep/work/ref_h265_*`, 8 s per run, fps from fpsdisplaysink.
- Kernel: build 3 (+ `updates/opi5-dp-smooth` for the retrain fix, boot of 22:23).

| Case | DP (30 Hz) | HDMI (60 Hz) |
|---|---|---|
| kmssink default, 1080p60 clip | 9.4 fps | 30 fps |
| kmssink default, 1080p30 clip | 12 fps | 30 fps |
| `skip-vsync=true` + console cursor hidden, 1080p30 | **30.1 fps, 0 dropped** | - |
| `skip-vsync=true` + cursor hidden, 1080p60 | 29.3 fps (half the frames, as expected at 30 Hz) | **60.0 fps, 0 dropped** |
| `skip-vsync=true` + cursor hidden, 2160p60 | 21.7 fps | **60 fps, 0 dropped** |

The choppiness was kmssink's double vblank wait and the fbcon cursor blink, not the DP link
(vblank intervals 16.666 ms and 33.431 ms, sigma 0.02-0.04 ms). `opi5-play` sets both. DP retrain
after a pin-assignment change (patches 0267-0269): D->C->D retrains in about 0.36 s with no black
screen and no modeset (DPCD 0x202 reads `77 00` after each switch). 4K60 on the Dell is not possible
through this 2-lane DP-to-HDMI dongle (HDMI 1.4 input, 300 MHz TMDS). Details:
[`topics/dp-smooth/notes/RESULTS.md`](../topics/dp-smooth/notes/RESULTS.md).

## 7. rkvdec CCU: one stream on both decoder cores (in progress, not in the image kernel)

**Status: in progress.** This is not in `patches/linux` and not in the image kernel; it was tested
as drop-in modules (`updates/opi5-rkvdec-ccu`) plus a DTB overlay for the CCU node on build 3.

- Command (board): `bash ~/ccu/ccu-verify.sh` ([`tests/rkvdec-ccu/`](../tests/rkvdec-ccu/)).
  Results: `~/ccu/run-<time>/summary.txt`. Baseline before the CCU driver: `baseline.sh`.
- Clips: the 600-frame `~/demo/yacht_*_2160p120` files, `filesrc ! demux ! parse ! <rkvdec element> !
  fakevideosink sync=false`; bit-exact = every frame's framemd5 vs FFmpeg software.

| Clip | Before (1 core) | With the CCU | Bit-exact |
|---|---|---|---|
| HEVC 4K (yacht_hevc_2160p120.mp4) | 130.4 fps (baseline run: 130.6) | **227.8 fps** | 600/600 |
| H.264 4K (yacht_h264_2160p120.mp4) | 67.6 fps (baseline run: 67.8) | **121.4 fps** | 600/600 |
| VP9 4K, CCU mode on | 138.5 fps baseline | 15.9 fps | **0/600** |

VP9 is therefore **kept off the CCU** (it runs serially on one core, 136.4 fps with `ccu_hw=0`).
Fluster on the CCU module: HEVC 146/147 (same as the baseline) but **JVT-AVC_V1 30/135**: interlaced
H.264 streams left the cores waiting on references (the POC high bits weren't programmed), and a
later JVT-FR-EXT run ended in decode timeouts and an SError panic. A fix (program the POC high bits;
run interlaced H.264 and VP9 serially, outside the CCU) is written and built for build 4, but **not
yet verified on the board**. Baseline fluster on the stock driver (rkvdec only, -j2): JCT-VC-HEVC_V1
146/147, JVT-AVC_V1 129/135, JVT-FR-EXT 65/69, VP9-TEST-VECTORS 230/305. Details:
[`topics/rkvdec-ccu/notes/RESULTS.md`](../topics/rkvdec-ccu/notes/RESULTS.md).

## 8. Audio

- Kernel: build 3 with the DTB and `dw-hdmi-qp.ko` from the audio branch (stack patches 1201-1202).
- Scripts (board): [`tests/audio/`](../tests/audio/): `sudo bash modeswitch-listen.sh` (440 Hz tone on
  HDMI while switching modes), `bash listen-test.sh hdmi|dp|hp|all`, `seq.sh`.

| Output | Result |
|---|---|
| HDMI0 | **Audible** (the user listened) through 4K60 (FRL) -> 4K120 (FRL) -> 4K60 -> 1080p60 (TMDS) -> 4K60 mode changes. Each modeset reprogrammed N/CTS (patch 1202); the PCM kept running at 48 kHz with no xruns |
| USB-C DP (dp0 card, patch 1201) | **Signal level only**: `speaker-test` on `plughw:dp0` ran with "audio prepare with 2 channels using DAI=1", audio SDP sent, hw_ptr advancing 48k frames/s, no xrun. Not heard: the Dell has no speakers |
| 3.5 mm jack (ES8388) | UCM defaults applied at boot and the path plays as the normal user (rc 0), but **not checked by ear** (no headphones). The automatic switch on plug-in is unconfirmed |

Details: [`topics/audio/notes/RESULTS.md`](../topics/audio/notes/RESULTS.md).

## 9. GPU and NPU

- Kernel: build 2 (`#2`, Oct 29 17:38 UTC, patches 0501-0514 and the combined DTB), 18:40-18:55.
- Commands (board): weston headless + `glmark2-es2-wayland --off-screen`, `vkmark --winsys headless`,
  NPU `classify.py` with and without `--delegate /usr/lib/teflon/libteflon.so` (MobileNet v1/v2
  224 quant, 30 invokes per image, 3 images). See
  [`topics/gpu-npu/notes/TESTING.md`](../topics/gpu-npu/notes/TESTING.md).

| Item | Before (CRU clock, GPU capped at 850 MHz) | After (0501-0514) |
|---|---|---|
| GPU clock under load | 850 MHz | 995-1024 MHz (SCMI PVTPLL) |
| vkmark (800x600) | 4146 | **4425** (+6.7 %) |
| glmark2 terrain / refract / jellyfish / desktop-blur | 111 / 262 / 1450 / 601 fps | 118 / 274 / 1519 / 627 fps |
| GPU runtime suspend/resume | - | 200 jobs, 0 failures |
| Thermal, 3 min sustained | 75 °C at 850 MHz | 85 °C peak, throttles cleanly to 900/800 MHz OPPs |
| NPU MobileNet v1 per inference | 16.6 ms at 200 MHz | **8.8 ms** at 1 GHz (CPU 4 threads 19.6 ms) |
| NPU MobileNet v2 per inference | 19.6 ms at 200 MHz | **11.2 ms** at 1 GHz (CPU 4 threads 12.2 ms) |

glmark2 overall score (ES2, 800x600 off-screen) before the fix: 1717. Top-1 matches the CPU on 6/6
image-model pairs; outputs are bit-exact between NPU clock settings. Details:
[`topics/gpu-npu/notes/RESULTS.md`](../topics/gpu-npu/notes/RESULTS.md).

## 10. VA-API driver for browsers

No board results are recorded yet. The board test queue (`tests/queue/queue.sh`) was to run the VA
driver's `probe correct perf gst` and fluster steps after the CCU fluster, but the queue stopped at
the CCU fluster (the panic in section 7), so those steps did not run. An earlier board run hung in
`vaprobe` (a self-deadlock, fixed in the driver's patch 0016; reproduced and fixed on the host).

Host-side result: the HEVC header rewriter (which lets the VA driver feed VDPU381 without SPS RPS
tables) gives identical frames for **146/147 streams of the JCT-VC HEVC_V1 suite (139 of them with
rewritten headers)**, decoded with FFmpeg; the one exception is TSUNEQBD_A_MAIN10, which FFmpeg
can't decode. The board pass bar is decode-only `ffmpeg -hwaccel vaapi` at >= 90 % of the GStreamer
v4l2codecs `fakevideosink` fps on the same clip. Run it with `tests/va-driver/run-tests.sh`.

## 11. Suspend

- Kernel: build 2, TF-A v2.15.0 with the suspend fix (in SPI NOR), 2026-10-29 19:04-20:40.
- Freezer, devices, platform and processors test levels pass. Real s2idle **passes 3/3 with a slow
  (verbose 115200 baud) console and hangs on resume 10/10 with a fast console**: the interconnect
  wedges and the watchdog resets the board about 44 s after wake. This is **open**; a bisect module
  and plan are ready. Deep sleep isn't usable yet: a kernel BUG in `cpufreq_online()` on resume
  (fixed in 1102, build-tested only) and a dead DP link after resume (fixed in 1101, not yet
  verified on hardware).
- Details: [`topics/suspend/notes/RESULTS.md`](../topics/suspend/notes/RESULTS.md),
  [`topics/suspend-k3/`](../topics/suspend-k3/README.md).

## Not verified / open

- **Desktop image**: the scripts are written, but the image has not been built or booted yet.
  Everything above ran on the server image.
- **Kernel build 4** (309 patches) is built but not installed; nothing above ran on it.
- **rkvdec CCU**: in progress, not in the image kernel. The H.264 interlaced/POC fix is under test
  (not yet run on the board); VP9 stays off the CCU.
- **Suspend**: the s2idle resume hang with a fast console is open; 1101 is untested on hardware with
  the fix, 1102 is build-tested only.
- **Headphone jack**: not checked by ear.
- **DP audio**: verified at signal level only.
- **GStreamer patches** (`patches/gstreamer`, v4l2codecs per-device caps and kmssink fixes):
  build-tested only, not run on the board.
- **VA-API driver**: no board results recorded (section 10); browsers not tested.
- **Max-out test** (`tests/maxout`): written, **never run**.
- **Mode sweep**: not re-run after 1301-1302, and its per-plane format part ran no tests (section 3).
- **Codec-quality fluster** (`run-fluster.sh`) did not complete; 0828 (VDPU2 VP8 1080p limit) awaits
  board verification.
- Known, not reproduced since 0715: a VPU121 decoder/IOMMU wedge under concurrent use.
