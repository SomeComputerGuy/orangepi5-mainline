# rkvdec-ccu: rkvdec CCU (one stream on both decoder cores): bit-exactness, fps A/B, two-stream and fluster runs. Needs the in-progress rkvdec-ccu kernel, not the image kernel

- Runs on: **board** (copy this directory to the board, e.g. with `scp -r`)
- How it was run: `bash ~/ccu/ccu-verify.sh`
- Notes and detailed results: [`topics/rkvdec-ccu/`](../../topics/rkvdec-ccu/README.md)
- Reference numbers: [`docs/RESULTS.md`](../../docs/RESULTS.md); how to re-run everything: [`docs/TESTING.md`](../../docs/TESTING.md); clips: [`docs/TEST-MEDIA.md`](../../docs/TEST-MEDIA.md)

These are the scripts exactly as they were run on the test board, except that the lab's own values are now defaults you can override: `OPI5_PI` (board login, default `ubuntu@orangepi5`), `OPI5_PI_IP` / `OPI5_HOST_IP` (board and host addresses, default the `scripts/nat-on.sh` subnet 172.31.55.0/24) and `$HOME` for the board user's home directory. Paths such as `~/demo` or `~/codecsweep` are on the board. Test media is not included (see TEST-MEDIA.md). C files are built on the board with `gcc -O2 -o <name> <name>.c` (plus `-ldrm` for DRM tools: see the file's header).

## Files

### [`ccu-verify.sh`](ccu-verify.sh)

```
ccu-verify.sh: board checks for the rkvdec CCU (frame-parallel) driver, after the reboot.
1. driver/DT state  2. bit-exactness (every frame, framemd5 vs FFmpeg software)
3. single-stream fps A/B (pipeline / cache / ccu_hw module parameters)  4. two streams
Usage: ccu-verify.sh [quick]   (quick: HEVC only)
Results in ~/ccu/run-<time>/summary.txt
```

### [`ccu-lib.sh`](ccu-lib.sh)

```
ccu-lib.sh: helpers shared by ccu-verify.sh and baseline.sh (sourced)
```

### [`fluster.sh`](fluster.sh)

```
fluster.sh <tag> [suite...]: fluster on rkvdec only (GStreamer v4l2codecs elements of the rkvdec
device, looked up per boot), -j2. Uses a private fluster copy ~/ccu/flpkg (codec-quality's ~/cq/flpkg with its decoder classes made picklable; adds
GStreamer-<codec>-V4L2SL-RKVDEC decoders) and the vectors in ~/.local/share/fluster.
Results: ~/ccu/fluster-<tag>/<decoder>-<suite>.{log,md}, summary in ~/ccu/fluster-<tag>/summary.txt
```

### [`baseline.sh`](baseline.sh)

```
baseline.sh: fps and bit-exactness of the currently loaded rkvdec (before the CCU driver).
```
