# codec-sweep: Codec sweep: every codec x resolution x frame rate on every hardware decoder (bit-exact vs FFmpeg), every encoder (PSNR), v4l2-compliance, fluster

- Runs on: **board** (copy this directory to the board, e.g. with `scp -r`)
- How it was run: `nohup sudo bash ~/codecsweep/codecsweep.sh > ~/codecsweep/run.log 2>&1 &`
- Notes and detailed results: [`topics/codec-quality/`](../../topics/codec-quality/README.md)
- Reference numbers: [`docs/RESULTS.md`](../../docs/RESULTS.md); how to re-run everything: [`docs/TESTING.md`](../../docs/TESTING.md); clips: [`docs/TEST-MEDIA.md`](../../docs/TEST-MEDIA.md)

These are the scripts exactly as they were run on the test board, except that the lab's own values are now defaults you can override: `OPI5_PI` (board login, default `ubuntu@orangepi5`), `OPI5_PI_IP` / `OPI5_HOST_IP` (board and host addresses, default the `scripts/nat-on.sh` subnet 172.31.55.0/24) and `$HOME` for the board user's home directory. Paths such as `~/demo` or `~/codecsweep` are on the board. Test media is not included (see TEST-MEDIA.md). C files are built on the board with `gcc -O2 -o <name> <name>.c` (plus `-ldrm` for DRM tools: see the file's header).

## Files

### [`codecsweep.sh`](codecsweep.sh)

```
Runs ON the board, unattended, after modesweep.sh: every codec x resolution x frame rate through every
capable hardware decoder (bit-exact vs ffmpeg, fps, shown on HDMI and DP), every hardware encoder
(PSNR, decoded back, shown), v4l2-compliance streaming of every format on every node, and fluster.
Report: ~/codecsweep/report.txt
```

### [`vqcmp.sh`](vqcmp.sh)

```
vqcmp.sh - timestamp-free PSNR / bit-exact comparison of video against a raw reference.

Every input is first decoded to a raw file (no container timestamps, no frame-rate
conversion), then compared frame by frame by index.  This avoids the two traps of
"ffmpeg -i a.mkv -i b.nv12 -lavfi psnr": framesync pairing frames by (rounded) PTS,
and raw elementary streams whose demuxer is not auto-detected from a ".es" suffix.

vqcmp.sh psnr  <test> <ref.nv12|ref-video> <WxH> [frames]   per-frame stats -> ./<basename test>.psnr
vqcmp.sh exact <test.yuv> <ref.yuv> <WxH> [frames] [fmt]    count identical frames (fmt default yuv420p)
vqcmp.sh align <test> <ref> <WxH> [frames] [maxshift]       best frame offset by PSNR (shift test vs ref)

<test>/<ref> may be raw (.nv12/.yuv/.i420, taken as nv12 / yuv420p) or anything ffmpeg can
decode; raw H.264/HEVC elementary streams (.es/.264/.h264/.265/.hevc) are probed by content.
```

### [`scripts/after-reboot.sh`](scripts/after-reboot.sh)

```
Verification after booting with updates/opi5-codec-quality (run on the board from ~/cq, idle board).
```

### [`scripts/elem.sh`](scripts/elem.sh)

```
elem.sh <codec> <device-name-substring>: the GStreamer v4l2codecs decoder element for a codec on
a given device (element names depend on /dev/video numbering, which changes between boots).
```

### [`scripts/mpeg2-conf.sh`](scripts/mpeg2-conf.sh)

```
MPEG-2 conformance (ISO/IEC 13818-4 vectors from fluster MPEG2_VIDEO-MAIN, which ships no
reference checksums): hardware (v4l2slmpeg2dec) vs FFmpeg per vector - frame counts, bit-exact
frames, PSNR. MPEG-2 only requires IEEE 1180 IDCT accuracy, so decoders are not bit-exact.
FFmpeg runs with -fps_mode passthrough: its default CFR output duplicates frames for 3:2 pulldown
(repeat_first_field), which GStreamer signals with buffer flags instead.
```

### [`scripts/run-fluster.sh`](scripts/run-fluster.sh)

```
Fluster on every OPi5 stateless decoder, per device. Stock fluster's GStreamer-H.264-V4L2SL runs
"v4l2slh264dec", which is whichever H.264 device registered first (the Hantro G1 on this board),
so rkvdec's H.264 decoder was never tested. This uses a private copy of fluster (~/cq/flpkg) with
extra GStreamer-<codec>-V4L2SL-RKVDEC/-HANTRO decoders whose element names are looked up per boot.
```

### [`scripts/trace-dec.sh`](scripts/trace-dec.sh)

```
usage: sudo trace-dec.sh clip out [nstreams] [sink] [parser] [decoder]  (from vp9-perf trace.sh)
```

### [`scripts/verify2.sh`](scripts/verify2.sh)

```
Verification of the final opi5-codec-quality modules (run on the board from ~/cq, detached).
```

### [`scripts/parse.py`](scripts/parse.py)

```
Per-frame timeline from trace.sh output (function_graph + irq events).
Single-stream analysis: each rkvdec_device_run is followed by one rkvdec IRQ.
```
