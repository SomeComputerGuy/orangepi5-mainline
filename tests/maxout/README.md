# maxout: Everything at once: two HTTP streams on two displays with NPU analysis, VEPU580 encode, 4K webcam recording to rotating segments, three-disk checksummed copy aggregator, GPU load, thermal/DDR/IRQ monitoring; plus open/close torture and hot-unplug tests

- Runs on: **board** (copy this directory to the board, e.g. with `scp -r`)
- How it was run: `bash ~/maxout/maxout.sh 900`
- Reference numbers: [`docs/RESULTS.md`](../../docs/RESULTS.md); how to re-run everything: [`docs/TESTING.md`](../../docs/TESTING.md); clips: [`docs/TEST-MEDIA.md`](../../docs/TEST-MEDIA.md)

These are the scripts exactly as they were run on the test board, except that the lab's own values are now defaults you can override: `OPI5_PI` (board login, default `ubuntu@orangepi5`), `OPI5_PI_IP` / `OPI5_HOST_IP` (board and host addresses, default the `scripts/nat-on.sh` subnet 172.31.55.0/24) and `$HOME` for the board user's home directory. Paths such as `~/demo` or `~/codecsweep` are on the board. Test media is not included (see TEST-MEDIA.md). C files are built on the board with `gcc -O2 -o <name> <name>.c` (plus `-ldrm` for DRM tools: see the file's header).

## Files

### [`maxout.sh`](maxout.sh)

```
"Max out everything at once" on the Orange Pi 5. Runs ON the board, unattended (uses sudo -n).
maxout.sh [SECS=900] [URL_A] [URL_B]       report: ~/maxout/report.txt, logs ~/maxout/run-MMDD-HHMM/
All at the same time, for SECS:
HDMI: stream A (HTTP, default Jellyfish 250 Mbit/s H.264) -> rkvdec -> waylandsink fullscreen, looping in ONE pipeline
(stream.py, segment seeks), tee -> RGA3 -> RGA2 -> 224x224 RGB -> NPU (Teflon MobileNet v1), CPU cross-check
DP:   stream B (HTTP, default Tears of Steel 4K HEVC) -> rkvdec -> waylandsink fullscreen + HDMI audio,
tee -> RGA (hardware copy, dma-buf) -> fd over a unix socket -> VEPU580 HEVC encode (tools/rkvenc-enc -s, zero CPU copy)
webcam 4K30 MJPEG -> rkjpegd -> RGA -> VEPU580 HEVC QP19 -> 150-s segments on the SD card (dock) + NPU on the camera
(cam-record.sh), each closed segment decode-checked and copied SD <-> USB stick with sha256
storage: copy-agg.sh (sha256-verified copies SD <-> USB stick both ways), unless one is already running
GPU:  glmark2-es2-wayland windowed, restarted if it exits
monitor every 5 s; abort if any thermal zone > 100 C (ABORT_MC; trips: passive 85, critical 115). Side branches are leaky so they can't stall playback.
```

### [`stream.py`](stream.py)


### [`rkvenc-enc.c`](rkvenc-enc.c)

```

rkvenc-enc: minimal V4L2 stateless H.264 / HEVC encoder client

Drives the rockchip-venc (VEPU580) driver through the request API using
the H.264 stateless encode uAPI proposed by Paul Kocialkowski
(V4L2_CID_STATELESS_H264_ENCODE_PARAMS) or the proposed HEVC stateless
encode uAPI (V4L2_CID_STATELESS_HEVC_ENCODE_PARAMS, -e hevc). Reads raw
NV12 frames, writes an Annex-B H.264 or H.265 elementary stream.

Build: aarch64-linux-gnu-gcc -O2 -Wall -I<kernel uapi headers> -o rkvenc-enc rkvenc-enc.c

```

### [`ddrbw.c`](ddrbw.c)

```
ddrbw SECS: read/write DDR bandwidth via the rockchip_ddr PMU (MB/s per second) */
include <linux/perf_event.h>
include <stdint.h>
include <stdio.h>
include <stdlib.h>
include <string.h>
include <sys/syscall.h>
include <unistd.h>
```

### [`npu_analyze.py`](npu_analyze.py)


### [`copy-agg.sh`](copy-agg.sh)

```
Storage copy aggregator over three scratch disks, sha256-verified, survives yanks. Mounted by LABEL, never sdX:
OPI5SCRATCH-SD  /mnt/scratch-sd   Transcend SD reader on the dock hub (8-1.1)
OPI5SCRATCH-USB /mnt/scratch-usb  SanDisk Ultra Fit, now on the dock hub (8-1.2)
OPI5SCRATCH-EXT /mnt/scratch-ext  SanDisk Extreme 0781:5580 on the board's top USB3 port (6-1)
copy-agg.sh <secs> [nfiles=4] [GiB per file=4]       log: ~/copyagg/copies.log, summary ~/copyagg/summary.txt
Setup (once): nfiles random files per disk with their sha256 (sd/f*.bin, usb/g*.bin, ext/h*.bin).
Four workers at the same time: a ring sd->usb (f), usb->ext (g), ext->sd (h), plus ext->usb (h), so ext<->usb
runs in both directions. If EXT isn't mounted, it falls back to sd<->usb (f, g). Each copy: dd with
conv=fsync (O_DIRECT reads), then sha256 of the destination read back with O_DIRECT (from the media, not the page
cache), then compare with the reference. A mismatch is DATA CORRUPTION (logged as CORRUPT, kept for analysis).
An I/O error is logged; the worker then waits for the filesystem label to reappear, runs e2fsck -fy, remounts it,
re-verifies every reference file there and continues. Every line: epoch dir file bytes secs MB/s result.
```

### [`cam-record.sh`](cam-record.sh)

```
Live 4K webcam -> rkjpegd -> (RGA to NV12) -> VEPU580 HEVC at fixed QP -> 150-s .mkv segments on the SD card,
with each closed segment decode-checked (rkvdec), copied SD -> Ultra Fit and back, and SD -> Extreme (sha256-verified).
cam-record.sh <secs> [qp=19]          logs: ~/camrec/
Camera: the UVC device whose formats include MJPG 3840x2160 (Aluratek UHD), mode MJPEG 3840x2160@30.
```

### [`scratch-setup.sh`](scratch-setup.sh)

```
ONE-TIME, DESTRUCTIVE: wipe the two user-approved scratch disks and make one ext4 partition on each.
DONE 2026-10-30 05:37; do not re-run. Current scratch disks (mount by LABEL only, sdX names change on every replug):
LABEL            mount             device                                   port
OPI5SCRATCH-SD   /mnt/scratch-sd   Transcend SD reader + 119.3 GiB SD card   dock hub 8-1.1 (USB3)
OPI5SCRATCH-USB  /mnt/scratch-usb  SanDisk Ultra Fit 114.6 GiB (0781:5583)   dock hub 8-1.2 (USB3, moved there by the user)
OPI5SCRATCH-EXT  /mnt/scratch-ext  SanDisk Extreme 58 GB (0781:5580)         board top USB3 port 6-1 (wiped by the user, not this script)
The identity patterns below are the ones used for the 05:37 run (Ultra Fit then on a board port).
scratch-setup.sh            (approved by the user 2026-10-30: Transcend SD 119.3 GB on the dongle hub 8-1.1,
SanDisk Ultra Fit 114.6 GB on the board USB3 port)
The disks are found by transport path + model + size, NOT by sdX name, and the script refuses anything else
(root disk, mounted partitions, unexpected size). Mounts at /mnt/scratch-sd and /mnt/scratch-usb.
```

### [`toggle-torture.sh`](toggle-torture.sh)

```
Abusive start/stop of every media device on the Orange Pi 5. Runs ON the board, unattended.
toggle-torture.sh [N=50] [device ...]      (default: all devices)  report: ~/torture/report.txt
Each cycle: start the device's workload (1 instance, or 2 concurrently every 5th cycle), let it run a random
0.2-3 s (0.2 s often lands mid-preroll / mid-setup), then kill it with a random SIGINT/SIGTERM/SIGKILL.
Then check: the process exits within 5 s (else: stuck -> evidence), no process still holds the /dev node,
no new kernel errors (timeout, IOMMU fault, Oops, SError, BUG, WARNING, busy, hung task), and a short known-good
job (md5 vs. the cycle-0 reference) completes; its open-to-first-output time must be < 2 s (logged).
Devices: rkvdec-h264 rkvdec-hevc rkvdec-vp9 (+ rkvdec-*-noccu when the CCU module with ccu_hw/pipeline params is loaded), g1-h264 g1-vp8 g1-mpeg2, av1,
venc-h264 venc-hevc (VEPU580), jpegenc (VEPU121), jpegdec (rkjpegd), iep, rga3, rga2, npu,
disp-hdmi disp-dp (waylandsink under weston; weston is started if not running).
Never rmmods, never reads regmap debugfs. The CCU module parameters are restored at the end.
```

### [`hotplug.sh`](hotplug.sh)

```
Display hot-unplug / replug during playback. Runs ON the board; a human pulls the cables.
hotplug.sh [step ...]     steps: dp hdmi dp-modeset hdmi-modeset (default: dp hdmi dp-modeset)
For each step the script prints "ACTION: ..." (also in ~/hotplug/PROMPT) and waits up to 10 min for the
connector status to change, so the timing of the human doesn't matter.
dp/hdmi: weston + one looping 4K player per display (stream.py, local clips). Unplug one display, wait 20 s,
replug, wait 20 s. Pass = no kernel errors/oops/hangs; the player on the pulled output keeps running or exits
cleanly; weston survives and re-enables the output; the other display's player never stutters (per-second fps
stays >= 90% of nominal); USB devices behind the dongle come back (lsusb count).
*-modeset: weston stopped; modetest alternates 2 modes on the connector every 0.5 s while the cable is pulled.
```

### [`hotplug-sim.sh`](hotplug-sim.sh)

```
Software-simulated display/dongle yanking during playback (weston + one looping 4K player per display).
hotplug-sim.sh [cycles=20] [kinds]     kinds: drm-dp drm-hdmi altmode pin usb all   (default: all of them)
Each cycle picks a kind (or "all" = several at once with random delays), applies it, restores, then checks:
no Oops/SError/hung task/IOMMU fault/decoder timeout/flip_done timeout in dmesg; weston alive;
the affected connector is connected again and its CRTC active (weston re-enabled the output);
the other display's player didn't drop (per-second fps >= 90% nominal); USB re-enumerates (lsusb count);
end0 (our SSH) loses no pings to ${OPI5_HOST_IP:-172.31.55.1}.
Kinds: drm-dp / drm-hdmi: /sys/class/drm/card0-<conn>/status off -> on -> detect
altmode: typec partner altmode active 0 -> 1      pin: pin_assignment C <-> D (and back)
usb: unbind/bind the dongle hubs (8-1 SuperSpeed, 7-1 high-speed) -> AX88179/cdc_ncm netdev vanishes
busy variants run while a third CCU decode (fakevideosink) is active; "modeset" variant restarts the
DP player at the same moment (weston modeset of the output) — included in "all".
```

### [`repro-restart.sh`](repro-restart.sh)

```
Start/stop the stream-A pipeline N times in a row and catch a start hang (no frame rendered in 15 s).
repro-restart.sh <variant: full|nonpu|nofifo|fakesink> [N=20] [secs per run=10] [end: int|eos]
Needs weston on wayland-9. On a hang: thread stacks, open /dev/video* fds, dmesg tail -> ~/maxout/repro/hang-*.
```

### [`soup-race.sh`](soup-race.sh)

```
Reproducer for the souphttpsrc HEAD-probe race: start the stream-B pipeline N times and count instant
"Internal data stream error" (flow -5) failures.   soup-race.sh <stock|patched> [N=30]
```
