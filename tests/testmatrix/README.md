# testmatrix: Display and media test matrix with objective checks: every mode x bpc x colour format x plane format/modifier per output (atomic state, link budget, HDMI SCDC, DP sink CRC, kernel log, webcam picture check with periodic camera controls), GNOME greeter check, every codec x block x userspace x output

- Runs on: **board** (copy this directory to the board, e.g. with `scp -r`)
- How it was run: `sudo CAM_CONN=DP-1 /var/tmp/testmatrix/display-matrix.sh --stop-gdm --out /var/tmp/tm/display-dp`
- Reference numbers: [`docs/RESULTS.md`](../../docs/RESULTS.md); how to re-run everything: [`docs/TESTING.md`](../../docs/TESTING.md); clips: [`docs/TEST-MEDIA.md`](../../docs/TEST-MEDIA.md)

These are the scripts exactly as they were run on the test board, except that the lab's own values are now defaults you can override: `OPI5_PI` (board login, default `ubuntu@orangepi5`), `OPI5_PI_IP` / `OPI5_HOST_IP` (board and host addresses, default the `scripts/nat-on.sh` subnet 172.31.55.0/24) and `$HOME` for the board user's home directory. Paths such as `~/demo` or `~/codecsweep` are on the board. Test media is not included (see TEST-MEDIA.md). C files are built on the board with `gcc -O2 -o <name> <name>.c` (plus `-ldrm` for DRM tools: see the file's header).

## Files

### [`display-matrix.sh`](display-matrix.sh)

```
Display matrix with objective verification. Runs ON the board as root, unattended and resumable
(rerun the same command after a hang/reboot; finished cases are kept, the case that was running is
recorded as FAIL). Needs the KMS device to itself: pass --stop-gdm to stop gdm for the run (it is
started again on exit), or stop it yourself.

sudo ./display-matrix.sh [--stop-gdm] [--out DIR] [--cam CONN] [--groups LIST] [--conn LIST] [--max N]
sudo ./display-matrix.sh --list            # print the cases, run nothing
sudo ./display-matrix.sh --summary         # rebuild summary.txt / results-final.tsv
sudo ./display-matrix.sh --fresh ...       # forget a previous run in DIR

Groups: calib (webcam: white/black + known-good/known-bad modes), modes (every EDID mode, kmsctl),
modetest (every mode again through modetest -a with an explicit -P plane), props (every mode x max bpc
x color format), hdr, vrr, planes (every plane x format x modifier at the preferred mode), dual.
Env: CAM_CONN (monitor under the webcam, e.g. DP-1), CAM_DEV, CAM_NAME (default Aluratek),
CAM_CALIB_MODE (1920x1080@60), CAM_KNOWN ("1920x1080@60=GOOD 2560x1440@60=GOOD 3840x2160@30/297000=BAD"),
SETTLE (4 s after commit), CAM_SETTLE (+3 s for the camera monitor), PROPS_MODES=all|unique,
CRC_GOLDEN (crc-golden.json of a known-good run), SRC_TMDS_MAX_MHZ (600), SRC_FRL_MAX (10x4).
```

### [`gnome-check.sh`](gnome-check.sh)

```
GNOME session check (image test sheet, step 1): does the gdm greeter (or the logged-in session) light
every connected output? Checks mutter DisplayConfig GetCurrentState (monitor has a current mode and a
logical monitor), PowerSaveMode == 0, the kernel atomic state (active CRTC with a framebuffer plane,
dpms On) and, with CAM_CONN set, the webcam (screen lit, not black). Read-only unless --wake (sets
PowerSaveMode 0 if the greeter blanked) or --modes (applies every mutter mode, temporary config, and
restores the original mode). Does not stop gdm.
sudo [CAM_CONN=DP-1] ./gnome-check.sh [--wake] [--modes] [--out DIR] [--calib DIR/calib.json]
--calib: calib.json from a display-matrix.sh run with the camera in the same position (without it the
webcam frame is only saved, verdict MANUAL). Exit status 0 = every output PASS.
```

### [`media-matrix.sh`](media-matrix.sh)

```
Media matrix. Runs ON the board as root, unattended, resumable (finished test ids are skipped on rerun).
codec x decode/encode x hardware block x userspace x display output, plus concurrency, open/close while
another job runs, v4l2-compliance and fluster (conformance MD5s; not duplicated here). Every hardware
path is proven by the block's IRQ count rising (no silent software fallback). Logic from
work/_out/modesweep/codecsweep.sh.
sudo ./media-matrix.sh [--stop-gdm] [--out DIR] [--groups LIST] [--res LIST] [--calib calib.json]
Groups (default all): dec display enc jpeg rga iep concurrent openclose compliance fluster
Env: SRC_YUV (NV12 3840x2160 clip, default $HOME/demo/yacht_2160p.nv12; else videotestsrc),
DEMO (dir with rkvenc-enc / v4l2-h264-slenc, default $HOME/demo), FLUSTER_DIR, FLUSTER_SUITES,
CAM_CONN + --calib (webcam check of decoded SMPTE bars on that output), PSNR_MIN (30).
Output: DIR/results.tsv (id, verdict, detail), DIR/summary.txt, DIR/work (streams, logs).
```

### [`lib/camcheck.py`](lib/camcheck.py)


### [`lib/dmatrix.py`](lib/dmatrix.py)


### [`lib/gnomecheck.py`](lib/gnomecheck.py)


### [`lib/kmsctl.py`](lib/kmsctl.py)


### [`README.md`](README.md)

```
Display and media test matrix (Orange Pi 5 / RK3588S, mainline)
```
