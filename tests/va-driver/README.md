# va-driver: VA-API driver (libva-v4l2_request) board test: probe, correctness vs FFmpeg, fluster, performance, GStreamer va

- Runs on: **board** (copy this directory to the board, e.g. with `scp -r`)
- How it was run: `./run-tests.sh probe correct perf gst`
- Reference numbers: [`docs/RESULTS.md`](../../docs/RESULTS.md); how to re-run everything: [`docs/TESTING.md`](../../docs/TESTING.md); clips: [`docs/TEST-MEDIA.md`](../../docs/TEST-MEDIA.md)

These are the scripts exactly as they were run on the test board, except that the lab's own values are now defaults you can override: `OPI5_PI` (board login, default `ubuntu@orangepi5`), `OPI5_PI_IP` / `OPI5_HOST_IP` (board and host addresses, default the `scripts/nat-on.sh` subnet 172.31.55.0/24) and `$HOME` for the board user's home directory. Paths such as `~/demo` or `~/codecsweep` are on the board. Test media is not included (see TEST-MEDIA.md). C files are built on the board with `gcc -O2 -o <name> <name>.c` (plus `-ldrm` for DRM tools: see the file's header).

## Files

### [`run-tests.sh`](run-tests.sh)

```
Board test for the V4L2 stateless VA-API driver. Runs from the unpacked bundle directory
(e.g. ~/browser-hwdec) and installs nothing: the driver is loaded from ./dri through
LIBVA_DRIVERS_PATH. Results go to ./results/<timestamp>/.

./run-tests.sh [probe] [correct] [fluster] [perf] [gst] [av1]     (default: all but av1)

Environment: CLIPS (default ~/vp9perf: 4k8.h264.mkv 4k8.hevc.mkv 4k8.webm 4k10.webm 1080p.webm),
JOBS for fluster (default 2), RENDER (default /dev/dri/renderD128).
```
