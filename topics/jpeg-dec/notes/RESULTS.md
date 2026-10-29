# rkjpegd (VDPU720) results

Branch `opi5/rkjpegd-7.3` (worktree ~/orangepi5/work/rkjpegd-7.3), on 5e33b74b0:
- c2f3f1751 dt-bindings: media: Add Rockchip VDPU720 JPEG decoder
- 58800fe9d media: rockchip: Add VDPU720 JPEG decoder driver
- a2ebd1368 arm64: dts: rockchip: Add the JPEG decoder to rk3588-base

## Build / checks
| Check | Result |
|---|---|
| kernelrelease | 7.3.0-opi5 |
| module, W=1, external build against ext/v4l2 Module.symvers | 0 warnings, signed, vermagic 7.3.0-opi5; CRCs match the board |
| checkpatch --strict | code clean; only Missing Signed-off-by (intended) + 2 warnings on the `Co-Authored-By` trailer spelling (checkpatch prefers `Co-authored-by`) |
| dt_binding_check | clean |
| CHECK_DTBS orangepi-5 / -5-sata | 0 warnings |

## On-board tests (board 7.3.0-opi5, coordinator's combined DTB from opi5/board-dt, /dev/video6)
Probe: `hardware id 0xdb1f0005, registered as video6`, IOMMU group 3. Runtime PM: `suspended` when idle (checked 1.5 s after a decode).

Vectors: ffmpeg's mjpeg encoder writes 4:2:2 as Y 2x2 + C 1x2, 4:4:4 as C 1x2 and "gray" as 3 components. These are non-canonical sampling factors that
v4l2_jpeg_parse_header() (and MPP) reject, so they come back as ERROR OUTPUT buffers (correct). Canonical vectors
were made with GStreamer jpegenc (libjpeg); restart interval and default-Huffman vectors with ffmpeg 4:2:0 (DRI=120 MCUs via -slices).
Reference: ffmpeg software decode in native planar layout. md5 never identical (IDCT rounding), PSNR below:

| Vector | PSNR avg (dB) |
|---|---|
| I420 1920x1080 / 1921x1081 / 3840x2160 / 641x479 / 33x17 | 77.7 / 77.5 / 77.2 / 73.0 / 66.4 |
| Y42B (4:2:2) same sizes | 78.1 / 77.8 / 77.8 / 73.5 / 67.6 |
| Y444 same sizes | 79.2 / 79.3 / 80.8 / 74.3 / 67.2 |
| GRAY8 same sizes | 76.2 / 77.1 / 77.2 / 72.1 / 72.6 |
| Y42B quality 20/50/75/100 | 101.1 / 102.5 / 100.7 / 100.9 |
| ffmpeg 4:2:0 with DRI (restart markers) | 77.1 |
| ffmpeg 4:2:0 -huffman default, q 1/5/15/31 | 76.8 / 77.1 / 77.7 / 77.8 |
| 4:2:2 -> NV12 hardware conversion vs swscale | Y 77.0, U 56.0, V 52.6 (chroma filter differs; image correct) |

| Stream test | Result |
|---|---|
| 1080p MJPEG 300 frames (x3 loop) | 532 fps |
| 4K MJPEG 120 frames (x3 loop) | 145 fps (~1.2 Gpix/s) |
| 720p 4:2:2 MJPEG 60 frames | 1039 fps |
| resolution change 640x480 420 -> 1280x720 422 -> 640x480 | 30/30 frames, 3 source changes, LAST/EPIPE flow OK |
| DEC_CMD_STOP drain | LAST buffer + EOS event every run |
| truncated JPEG | capture + output ERROR, no hang, no IOMMU fault |
| corrupt ECS (400 random bytes) | decoded (hardware error concealment), no fault |
| garbage file | OUTPUT ERROR, no source change, hardware untouched |
| good/trunc/corrupt/garbage/good sequence | 3 decoded, 1 cap error, 2 out errors; next decode bit-identical to an earlier run |
| dmesg | no jpegd/iommu errors |

v4l2-compliance (first build): 45/48 pass. The failures were: MIN_BUFFERS_FOR_CAPTURE control present on a JPEG decoder,
CAPTURE colorspace not SRGB, and COMPOSE_PADDED not inside COMPOSE_BOUNDS. Streaming (-s --stream-from) also failed sequence
checks because the empty LAST buffers had no sequence number. All four are fixed in 14d565cb9 (control removed, colorimetry SRGB/601/full,
COMPOSE_BOUNDS = padded size, sequence set on LAST buffers), but the fix has NOT been re-run on hardware.

## Incident (12:47-12:56)
Timeline: modprobe at ~58 s uptime. Then cmp.sh (single-image decodes), the MJPEG/throughput/reschange/NV12 runs, the trunc/corrupt/garbage
error tests and v4l2-compliance (including -s streaming), all without any jpegd or IOMMU error in dmesg and with the device runtime-suspended afterwards.
Then `rmmod` at 292 s to load a fixed build oopsed (NULL deref, rkjpegd_runtime_suspend+0x1c, from devres pm_runtime_disable_action).
About 50 s later I removed the module from updates/, ran depmod and `systemctl reboot` (12:51:49). The SoC never came out of reset (no SPL); the user power-cycled it.

Root cause of the oops: `struct v4l2_device` was the first member of `struct rkjpegd_dev`, so drvdata == &v4l2_dev, and
v4l2_device_unregister() in remove() cleared the device's drvdata. The devm runtime-PM disable action then ran the
autosuspend with dev_get_drvdata() == NULL. The probe error path had the same hole. Fixed in 14d565cb9:
- v4l2_dev is no longer the first member;
- runtime PM is enabled and disabled explicitly; remove() and the probe error path call pm_runtime_dont_use_autosuspend() (which
  suspends synchronously via rpm_idle) and pm_runtime_disable() *before* v4l2_device_unregister();
- no devm runtime-PM action is left.

State at the time of the oops / reset: the hardware was idle (no job, runtime_status had been "suspended"; the oops was in the
suspend path triggered by rmmod, before clk_bulk_disable). So the decoder clocks and the VDPU power domain stayed ON, and the
IOMMU stayed attached and idle. No decoder AXI transaction was outstanding, and no IOMMU fault or watchdog timeout was ever logged.

Clocks: assigned-clocks sets only ACLK_JPEG_DECODER_ROOT (a COMPOSITE mux+div whose sole consumer chain is
aclk_jpeg_decoder_pre -> aclk_jpeg_decoder). It has no CLK_SET_RATE_PARENT, so no PLL rate changes. At most the mux may reparent
among gpll/cpll/aupll/spll; the best <= 600 MHz is gpll(1188)/2 = 594 MHz. No clock in the boot/reset path is touched, and the CRU is
reset by the global reset anyway. The rate is only applied when the driver binds; the coordinator's 12:46 reboot happened
before that and came back fine.

I can't prove what blocked the warm reset. The only abnormal state was the oopsed rmmod task, with the VDPU PD and jpegd clocks
left on (the normal boot state) and the module refcount at -1. I have no evidence that the decoder or its IOMMU blocks a global reset.

## Second session (13:08-13:40): fixed module (md5 cc2ba0f8, = 14d565cb9 driver), installed by the coordinator, /dev/video2
| Test | Result |
|---|---|
| v4l2-compliance (plain) | **48/48 pass, 0 warnings** |
| v4l2-compliance -s10 --stream-from=s720_422.mjpeg | streaming fails a sequence check. Cause: buffers queued before STREAMON were numbered, then start_streaming() reset the counter. Fixed offline in 58800fe9d (reset moved to stop_streaming); not re-run. Note v4l2-compliance streams the file in fixed sizeimage chunks rather than per-JPEG, so most of its OUTPUT buffers are (correctly) rejected. |
| GStreamer file 1080p MJPEG, 300 frames, fakesink sync=false | v4l2jpegdec 0.99 s (about 300 fps incl. startup) vs jpegdec 1.52 s (about 200 fps) |
| GStreamer file 4K MJPEG, 120 frames | v4l2jpegdec 1.00 s (about 120 fps) vs jpegdec 2.26 s (about 53 fps) |
| GStreamer single still JPEG | decoded correctly (PSNR 77.7 dB, the same as jdec), then the pipeline hangs at EOS. 2 frames and more are fine. See below. |
| Error streams re-run (trunc / corrupt / garbage / mixed) | same as before: ERROR buffers, no hang, no fault |
| Good decode after errors | bit-identical; 4K stream 146.9 fps |
| Runtime PM idle | suspended |
| ACLK_JPEG_DECODER rate | 594 MHz, parent gpll (as predicted) |
| dmesg | no jpegd / IOMMU / watchdog messages |

### Live webcam (Aluratek UHD 4K, Sunplus 1bcf:0b26, uvcvideo, USB2)
The camera's frames are canonical 4:2:2 (Y 2x1) with their own DHT and a DRI segment.
- **Out-of-box GStreamer `v4l2src ! jpegparse ! v4l2jpegdec` fails with not-negotiated.** UVC caps carry
  `colorimetry=2:4:5:1` (limited range, BT.709 transfer), but the driver forced JFIF full-range sRGB on OUTPUT. File sources carry no colorimetry, which is why they worked.
  Fixed offline in 58800fe9d: OUTPUT keeps the client's colorimetry (JFIF default), and CAPTURE copies it, as stateful decoders should. Not verified on hardware yet.
  Verified the live path meanwhile with `capssetter caps=image/jpeg,colorimetry=(string)1:4:7:1`:

| Live, 300 frames | wall | CPU (gst process) |
|---|---|---|
| 3840x2160 v4l2jpegdec | 15.6 s (about 19.3 fps, camera-limited; no errors) | 0.34 s (2% of one core) |
| 3840x2160 jpegdec (sw) | 15.5 s | 6.88 s (44%) |
| 1920x1080 v4l2jpegdec | 15.5 s (about 19.4 fps, camera-limited; no errors) | 3.74 s (24%), unexplained, needs a look |
| 1920x1080 jpegdec (sw) | 15.5 s | 2.45 s (16%) |

The camera delivered about 19–20 fps in this light, not 30, for both decoders, so sustained 30 fps could not be shown. The decoder itself does 145 fps at 4K.

60 captured frames, hardware vs ffmpeg software (jdec; its 8 fps at 4K was its own byte-wise file writer; without -o it does >100 fps on these frames):

| Capture | with DHT | DHT stripped (Annex K tables) |
|---|---|---|
| 4K, 60 frames | 60/60 decoded, Y 94.5 / U 60.8 / V 59.1 dB | 60/60, **bit-identical** to the with-DHT decode |
| 1080p, 60 frames | 60/60, Y 91.8 / U 60.3 / V 59.0 dB | 60/60, bit-identical |

### GStreamer single-image EOS hang (analysis, strace)
GStreamer sends DEC_CMD_STOP right after the OUTPUT STREAMON and sets up CAPTURE from G_FMT without first dequeuing the
initial SOURCE_CHANGE event. The decoded frame comes back flagged LAST. On EPIPE, GStreamer sees the still-pending initial
SOURCE_CHANGE event, treats it as a mid-stream resolution change, reconfigures CAPTURE, and waits forever.
The driver's behaviour follows dev-decoder.rst (initial event, LAST on the drained buffer). This looks like a GStreamer race
for one-frame streams. A driver-side workaround would be to not queue the initial event when CAPTURE is already set up with a
matching format, but that departs from the spec, so I didn't do it.

GStreamer also requests 128 MiB OUTPUT buffers; the driver honours requests up to 256 MiB.

## Not run / deferred (with risk)
- Install 58800fe9d's module (md5 01e6e7b0; sequence + colorimetry fixes) via install + reboot: low risk.
  Then re-run v4l2-compliance -s and the plain live webcam pipeline without capssetter.
- Unbind/rmmod of the fixed module: medium risk. Not to be done (reboot to unload).
