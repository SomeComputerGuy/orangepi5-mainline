# Re-running the tests

The scripts under [`tests/`](../tests/) are the ones that produced the numbers in
[`RESULTS.md`](RESULTS.md), with the lab's addresses and paths turned into overridable defaults.
Each directory has a README with the header of every file. This page says what you need, in what
order to run them, and what to expect.

Most tests run **on the board**: copy the test directory there (`scp -r tests/<name> "$OPI5_PI":`)
and run it in an SSH session. Paths like `~/demo` are in the board user's home directory. A few
parts run on the host; each section says where.

## Prerequisites

1. **The board runs the image built from this repository** (server image is fine; see the top-level
   README for building and flashing). The reference results ran on kernel build 3 of
   `patches/linux`, partly with drop-in modules from topic branches (see RESULTS.md, "Kernels"). A
   kernel built from the current `patches/linux` contains all of those fixes except the rkvdec CCU.
   Check what is running with `uname -v` and `modinfo -n rockchip_vdec`.
2. **SSH login with the project key:** `scripts/pi-add-key.sh [user@host]` creates the key (if
   needed) and installs it on the board once (it asks for the board password).
3. **Environment** (on the host; set them in `local.env` or export them):
   - `OPI5_PI`: the board's SSH login (default `ubuntu@orangepi5`);
   - `OPI5_HOST_IP`: the host address the board can reach, used for the HTTP clip server
     (default: the host's address on the `scripts/nat-on.sh` subnet, see `scripts/env.sh`).
     `tests/maxout/maxout.sh` reads it on the board, so export it there too when it differs.
4. **Displays:** HDMI-A-1 for most tests; the dual-display, DP and some audio tests also need a
   USB-C DP display (DP-1). The reference runs used a 4K120-capable TV on HDMI and a 4K30 monitor
   through a USB-C DP-to-HDMI dongle; with other displays the mode lists, refresh rates and drop
   counts will differ.
5. **Test media**, as listed in [`TEST-MEDIA.md`](TEST-MEDIA.md):
   - on the board in `~/demo/`: the UVG YachtRide encodes and `yacht_{2160p,1080p}.nv12`, the
     Big Buck Bunny MP4s, and the encoder test clients `rkvenc-enc`
     (`topics/rkvenc-hevc/notes/tools/rkvenc-enc.c`) and `v4l2-h264-slenc`
     (`topics/vepu121-h264enc/notes/tools/v4l2-h264-slenc.c`), built for arm64 against the uapi
     headers of the kernel with the stateless encoder uAPI (see each file's header);
   - on the host, one directory with the Jellyfish, Big Buck Bunny and Tears of Steel files for
     the HTTP tests;
   - `~/vp9perf/` clips for the VA driver test (generated on the board).
6. **Conformance vectors:** install [fluster](https://github.com/fluendo/fluster) on the board and
   run `fluster download` for the suites in TEST-MEDIA.md section 7 (into
   `~/.local/share/fluster/resources/`).
7. **Board packages** used by the scripts: `gstreamer1.0-tools` and the v4l2codecs plugin (from the
   image), `ffmpeg`, `libdrm-tests` (`modetest`), `v4l-utils` (`v4l2-compliance`), `weston`,
   `alsa-utils`, `gstreamer1.0-alsa`, `gcc` for the C tools, `bc`, `curl`. The tests use
   `sudo -n`, so the board user needs passwordless sudo for unattended runs.

Nothing in the tests installs packages or kernel modules, except where a section says so.

## 1. Smoke test and demo (`tests/demo`)

Board. Copy `demo.sh` into `~/demo` next to the clips.

```sh
bash ~/demo/demo.sh list        # connectors, the decoder element per codec and device, encoder nodes
bash ~/demo/demo.sh dec-hevc    # then dec-vp9 dec-h264 dec-av1 g1-h264 g1-vp8 g1-mpeg2
bash ~/demo/demo.sh enc-hevc    # then enc-h264 enc-vepu2 jpeg
bash ~/demo/demo.sh dual        # HEVC 4K120 on HDMI + VP9 4K on DP at the same time (needs DP)
```

Run it with nothing else holding DRM master (no compositor on the displays). `list` should show an
rkvdec element for h265/h264/vp9, a Hantro element for h264/vp8/mpeg2, the AV1 element, and the
`rockchip-venc`, `vpu121-enc`, `vepu121-enc` and `rockchip-jpegd` nodes. Each play step prints
fpsdisplaysink's last `rendered/dropped` line plus any kernel decoder errors (there should be none).
`tests/k3-validation/run-k3.sh` is the host-driven run that did this unattended after a kernel
install, together with a bit-exactness check and an Ethernet throughput test; it is kept as a
reference and needs adapting to your paths (`TOP`). (Its throughput step uses a small TCP helper,
`tcpt.py`, that is not part of this repository; the step is skipped if the file is missing.)

## 2. Codec sweep (`tests/codec-sweep`)

Board, unattended, about an hour or more (the reference encodes are made on the first run). Copy the
directory to `~/codecsweep` (the script expects `vqcmp.sh` next to it).

```sh
nohup sudo bash ~/codecsweep/codecsweep.sh > ~/codecsweep/run.log 2>&1 &
```

Report: `~/codecsweep/report.txt`, one line per test:
`<codec> <WxH>@<fps> <device>  bitexact=30/30  fps=...  display_underflow=0`. Expected (RESULTS.md
sections 1-2): 30/30 for every H.264, HEVC, VP9, AV1 and VP8 line; MPEG-2 not bit-exact but with
`psnr_vs_ffmpeg` above 55 dB; encoder PSNR about 38-42 dB; `display_underflow=0`. The end of the
report counts the non-bit-exact decodes (MPEG-2 excluded) and the MPEG-2 tests below 55 dB: both
should be 0. The fluster part at the end writes `sweep-<suite>.md`.

Other tools in the directory (run from a copy in `~/cq`):
- `run-fluster.sh`: fluster per device (rkvdec and Hantro separately), results in
  `fluster-results.txt`. It needs a private fluster copy in `~/cq/flpkg` with the extra
  `-RKVDEC`/`-HANTRO` decoders (see the script header; the CCU directory's `fluster.sh` uses the
  fixed copy in `~/ccu/flpkg`). This run did not complete in the reference session.
- `mpeg2-conf.sh`: MPEG-2 conformance, hardware vs FFmpeg per vector (needs `MPEG2_VIDEO-MAIN`).
- `vqcmp.sh psnr|exact|align`: the timestamp-free comparison used for the corrected encoder numbers.
- `verify2.sh`, `after-reboot.sh`, `trace-dec.sh` + `parse.py`, `elem.sh`: verification and
  per-frame decoder timelines.

## 3. Display mode sweep (`tests/modesweep`)

Board, unattended, about 11 minutes with two displays. Nothing may hold DRM master.

```sh
nohup sudo bash ~/modesweep/modesweep.sh > ~/modesweep/run.log 2>&1 &
```

Report: `~/modesweep/report.txt`, one line per mode (`rc=` and `underflow=` per test, `scdc40=` for
HDMI), ending in `tests: N  with underflow: U  rc!=0: F`. Reference (build 3, before the VOP2 fix):
`tests: 150  with underflow: 1  rc!=0: 0`, the one being 4K120 with an NV12 overlay. On a kernel
with 1301-1302 expect `with underflow: 0`. The per-plane format section was skipped in the
reference run (a stdin bug, fixed in the published script), so a re-run reports more than 150 tests
(see RESULTS.md section 3). `dpslow.sh` repeats the DP-1 part only, holding each mode for 12 s instead of 4 s (report `~/modesweep/report-dp-slow.txt`).

## 4. Network streaming (`tests/netstress`)

Host and board. On the host, serve the clip directory (TEST-MEDIA.md section 5):

```sh
python3 -I tests/netstress/rangeserver.py "$OPI5_HOST_IP" 8099 <media dir>
```

On the board (it starts weston on both displays if none is running):

```sh
bash ~/netstress/netstress.sh "http://$OPI5_HOST_IP:8099" 30
```

Report: `~/netstress/report.txt`: per case the rendered/dropped frames of each stream, the average
network rate with `rx_errs`/`rx_drop` deltas, CPU and irq+softirq load, and VOP underflows. Expected
(RESULTS.md section 4): 0 dropped on HDMI, 0 NIC errors, 0 underflows; the 400 Mbit/s HEVC Main10
clip 900/900 frames in 30 s. On a 30 Hz DP display, 60 fps content shows about half its frames as
dropped, which is expected.

## 5. Dual display and smooth playback (`tests/dp-smooth`)

Board. Needs `~/codecsweep/work/ref_h265_*` from the codec sweep. `opi5-play` is also installed in
the image as `/usr/local/bin/opi5-play`.

```sh
opi5-play ~/codecsweep/work/ref_h265_1920x1080_30.mkv dp     # smooth 30 fps on the DP display
opi5-play ~/codecsweep/work/ref_h265_3840x2160_60.mkv hdmi
sudo bash flipmeasure.sh x <dp connector id> 65 <clip> 8 skip-vsync=true
python3 cadence.py ~/dpsmooth/out/x.trace                    # vblank-sequence deltas mostly 1 (OUT= overrides the directory)
```

Expected: 30.1 fps with 0 dropped for a 30 fps clip on a 30 Hz DP display, 60 fps with 0 dropped
for 60 fps clips on HDMI at 60 Hz. The DP pin-assignment retrain check (needs a dongle that supports
pin assignments C and D) is in [`topics/dp-smooth/notes/TESTING.md`](../topics/dp-smooth/notes/TESTING.md):
after each `echo C|D > .../displayport/pin_assignment` the DPCD lane status should read `77 00` again
within about 1 s, with no black screen. `jitter.sh`, `idlecommits.sh` and `vblwait.c` measure
vblank timing and kernel-internal commits.

## 6. VOP2 underflow matrix (`tests/vop2-underflow`)

Board, as root, nothing holding DRM master. Build the tools first:

```sh
gcc -O2 -o planetest planetest.c && gcc -O2 -o ddrbw ddrbw.c && gcc -O2 -o memhog memhog.c -lpthread
sudo bash rc.sh c0e0 <planetest args>     # bad frames (POST_BUF_EMPTY printed + suppressed) and AXI ports
sudo bash vm.sh a 3840x2160-120 - 0 9     # kmssink overlay matrix: label, HDMI mode, DP mode or -, load 0/1, seconds
```

`planetest` usage is in its header (`planetest [-c crtc] [-o conn] [-m WxH@R] [-t secs] [-s] P[:FMT[:WxH[:FBH]]]...`).
`vm.sh` needs `~/demo/yacht_hevc_2160p120.mp4` (load) and `~/codecsweep/work/ref_h265_3840x2160_{60,30}.mkv`.
With patch 1302 an underflowing port raises at most one IRQ per frame, so count bad frames
(`rc.sh`, `vm.sh`, `watch.sh`) rather than IRQ/s. Expected on a kernel with 1301-1302: 0 bad frames
for every case with an NV12 overlay, including 4K120 + overlay and dual display; three full-screen
RGB layers at 4K120 + 4K30 exceed the two ports and still underflow (RESULTS.md section 5).
`devmem.c`, `qos.sh` and `portload.py` are debug tools (they need `/dev/mem` and debugfs).

## 7. Audio (`tests/audio`)

Board, by ear; run as the normal user (in the `audio` group) unless noted.

```sh
bash listen-test.sh all            # or hdmi | dp | hp: "Front Left/Right" then tones per output
sudo bash modeswitch-listen.sh     # 440 Hz on HDMI for ~30 s while the mode switches 4K60 -> 4K120 -> 4K60 -> 1080p -> 4K60
bash seq.sh                        # HDMI 440 Hz, pause, DP 880 Hz
```

Expected: `cat /proc/asound/cards` lists `hdmi0`, `dp0` and `rockchipes8388`; the tone continues
after each of the 4 screen blinks of `modeswitch-listen.sh`; voice on the correct side on each
output. `modeswitch-listen.sh` needs nothing else holding DRM master. The headphone check (`hp`)
needs headphones plugged in; it has not been done yet.

## 8. VA-API driver (`tests/va-driver`)

Board. The script loads the driver from `./dri/v4l2_request_drv_video.so` next to it
(`LIBVA_DRIVERS_PATH`), so it installs nothing: put the `.so` from the
`v4l2-request-va-driver` deb (`scripts/build-va-driver.sh`) into `dri/` in the test directory.
Needs FFmpeg with VA-API, `vainfo`/GStreamer `va` elements for the `gst` step, and the `~/vp9perf`
clips (or `CLIPS=<dir>`).

```sh
./run-tests.sh probe correct perf gst     # default: all but av1; add fluster (JCT-VC-HEVC_V1 etc.)
```

Results: `./results/<timestamp>/SUMMARY.txt`. Pass bar: `correct` PASS for every clip (frames
downloaded from VA surfaces, framemd5 vs FFmpeg software); `perf` decode-only fps at >= 90 % of the
GStreamer v4l2codecs `fakevideosink` fps on the same clip; fluster HEVC with the RPS/LTRPSPS/POC
vectors passing. No board reference results exist yet (RESULTS.md section 10). A hang is reported
as `HANG:` with thread backtraces instead of blocking the run.

`tests/queue/queue.sh` is the unattended chain used in the reference session (CCU verify, CCU
fluster, codec-quality fluster, VA driver tests); it writes `~/queue/summary.txt` ending in `DONE`
and expects the other test directories in `~/ccu`, `~/cq` and `~/browser-hwdec`.

## 9. rkvdec CCU (`tests/rkvdec-ccu`, development kernel only)

This needs the **in-progress** CCU driver from `topics/rkvdec-ccu` (modules built from that branch
in `updates/opi5-rkvdec-ccu/` and the CCU DT overlay applied to the DTB), not the image kernel. On
the image kernel `ccu-verify.sh` only shows that the CCU isn't there. Copy the directory to `~/ccu`.

```sh
bash ~/ccu/baseline.sh            # optional, before installing the CCU driver: fps and bit-exactness
bash ~/ccu/ccu-verify.sh          # driver/DT state, every-frame bit-exactness, fps A/B, two streams
bash ~/ccu/fluster.sh ccu         # fluster on rkvdec only (needs ~/ccu/flpkg and the vectors)
```

Results: `~/ccu/run-<time>/summary.txt` and `~/ccu/fluster-ccu/summary.txt`. Pass criteria: "decoding
with the CCU" in dmesg, 600/600 frames bit-exact in every mode, fluster equal to the baseline
(HEVC 146/147, AVC_V1 129/135, FR-EXT 65/69, VP9 230/305), both cores' IRQ counts advancing for
one stream, no timeouts or IOMMU faults. Reference: HEVC 4K 130.4 -> 227.8 fps, H.264 4K 67.6 ->
121.4 fps. The interlaced H.264 fix is not verified yet; the earlier module hung the decoder in
JVT-FR-EXT and the board panicked, so run fluster attended.

## 10. Max-out test (`tests/maxout`, never run)

Board, both displays, about 6 minutes, attended (a bare board may hit the 85 °C trip; the script
aborts above 95 °C). Needs the HTTP server from section 4, `~/demo/rkvenc-enc`, the NPU venv
(`~/npu-venv` with ai-edge-litert) and models (`~/npu/models/mobilenet_v1_1.0_224_quant.tflite`,
`imagenet_labels.txt`), `glmark2-es2-wayland` and weston.

```sh
mkdir -p ~/maxout   # copy maxout.sh, npu_analyze.py and ddrbw.c into it
OPI5_HOST_IP=<host address> bash ~/maxout/maxout.sh 300 [URL_A] [URL_B]
```

Defaults: stream A Jellyfish 250 Mbit/s H.264 on HDMI (plus RGA downscale and NPU inference),
stream B Tears of Steel 4K HEVC on DP (plus HDMI audio and a VEPU580 HEVC encode), glmark2 in a
window. Report: `~/maxout/report.txt`, raw logs in `~/maxout/run-<MMDD-HHMM>/`. There are no
reference numbers: this test has not been run yet. Things to check on a first run: that the two-stage
RGA caps negotiate (`A.log`), whether the tee in front of the encoder branch makes rkvdec copy frames
("copying frames" in `B.log`), and the thermal trip.
