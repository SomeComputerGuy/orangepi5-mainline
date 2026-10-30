# dp-smooth: Smooth KMS playback on HDMI and USB-C DP (opi5-play) and the frame-cadence measurement tools

- Runs on: **board** (copy this directory to the board, e.g. with `scp -r`)
- How it was run: `opi5-play <video> dp`
- Notes and detailed results: [`topics/dp-smooth/`](../../topics/dp-smooth/README.md)
- Reference numbers: [`docs/RESULTS.md`](../../docs/RESULTS.md); how to re-run everything: [`docs/TESTING.md`](../../docs/TESTING.md); clips: [`docs/TEST-MEDIA.md`](../../docs/TEST-MEDIA.md)

These are the scripts exactly as they were run on the test board, except that the lab's own values are now defaults you can override: `OPI5_PI` (board login, default `ubuntu@orangepi5`), `OPI5_PI_IP` / `OPI5_HOST_IP` (board and host addresses, default the `scripts/nat-on.sh` subnet 172.31.55.0/24) and `$HOME` for the board user's home directory. Paths such as `~/demo` or `~/codecsweep` are on the board. Test media is not included (see TEST-MEDIA.md). C files are built on the board with `gcc -O2 -o <name> <name>.c` (plus `-ldrm` for DRM tools: see the file's header).

## Files

### [`opi5-play`](opi5-play)

```
opi5-play <video file> [dp|hdmi] - full-screen hardware-decoded playback on a KMS display
from the text console, without frame-rate loss:
- kmssink skip-vsync=true: on atomic drivers (rockchip) drmModeSetPlane already blocks until
the frame is on screen; kmssink's own extra vblank wait halves the frame rate otherwise
(60 fps -> 30 fps on HDMI, ~10-15 fps on the 30 Hz DP monitor).
- hides the fbcon cursor on the foreground VT while playing: its blink redraws the console
framebuffer and commits on every CRTC that shows it every 200 ms, which delays the video's
plane update by a refresh and drops a frame each time.
PLANE=<id> overrides the plane (defaults keep DP and HDMI on separate Esmart planes, so both
can play at the same time). Extra args after the output name go to gst-launch-1.0.
```

### [`flipmeasure.sh`](flipmeasure.sh)

```
flipmeasure.sh <tag> <connector-id> <plane-id> <clip> [seconds] [extra kmssink props]
Plays <clip> with v4l2codecs + kmssink on one connector for N seconds while recording
drm vblank trace events in a private tracefs instance; writes $OUT/<tag>.{trace,gst}.
```

### [`idlecommits.sh`](idlecommits.sh)

```
idlecommits.sh <tag> <secs>: count kernel-internal (fbdev) commit-done events per CRTC with no client
```

### [`jitter.sh`](jitter.sh)

```
jitter.sh <tag> <frames-on-crtc0> -- <gst-launch args...>: vblank interval stats on crtc0/1 while a pipeline runs
```

### [`cadence.py`](cadence.py)

```
cadence.py <trace>...: from drm trace events, per CRTC: vblank interval stats, and for
userspace-requested vblank events (file!=0) and kernel commit events (file=0) the histogram
of vblank-sequence deltas between consecutive events (1 = one new frame every refresh).
```

### [`vblwait.c`](vblwait.c)

```
vblwait: wait N consecutive vblanks on a CRTC index (no DRM master needed) and print the
kernel's vblank timestamp and the CLOCK_MONOTONIC wake-up time for each.
usage: vblwait <crtc-index> <count>      build: gcc -O2 -o vblwait vblwait.c (uapi headers only)
include <stdio.h>
include <stdlib.h>
include <fcntl.h>
include <time.h>
include <sys/ioctl.h>
include <drm/drm.h>
```
