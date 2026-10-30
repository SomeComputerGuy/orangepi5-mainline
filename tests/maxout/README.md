# maxout: Everything at once: two HTTP streams on two displays, RGA + NPU inference, VEPU580 encode, GPU load, with thermal/DDR/IRQ monitoring

- Runs on: **board** (copy this directory to the board, e.g. with `scp -r`)
- How it was run: `bash ~/maxout/maxout.sh 300`
- Reference numbers: [`docs/RESULTS.md`](../../docs/RESULTS.md); how to re-run everything: [`docs/TESTING.md`](../../docs/TESTING.md); clips: [`docs/TEST-MEDIA.md`](../../docs/TEST-MEDIA.md)

These are the scripts exactly as they were run on the test board, except that the lab's own values are now defaults you can override: `OPI5_PI` (board login, default `ubuntu@orangepi5`), `OPI5_PI_IP` / `OPI5_HOST_IP` (board and host addresses, default the `scripts/nat-on.sh` subnet 172.31.55.0/24) and `$HOME` for the board user's home directory. Paths such as `~/demo` or `~/codecsweep` are on the board. Test media is not included (see TEST-MEDIA.md). C files are built on the board with `gcc -O2 -o <name> <name>.c` (plus `-ldrm` for DRM tools: see the file's header).

## Files

### [`maxout.sh`](maxout.sh)

```
"Max out everything at once" on the Orange Pi 5. Runs ON the board, unattended, as the desktop user (uses sudo -n):
HDMI: stream A (HTTP) -> rkvdec -> waylandsink HDMI-A-1, tee -> RGA (2 stages) -> RGB 224x224 @15 fps -> NPU (Teflon)
DP:   stream B (HTTP) -> rkvdec -> waylandsink DP-1 (+ HDMI audio), tee -> raw NV12 -> VEPU580 HEVC encode (rkvenc-enc)
GPU:  glmark2-es2-wayland windowed, run forever
monitor every 5 s: temps, cpufreq, devfreq, CPU/irq/softirq, NIC, VOP underflows, IRQ rates, DDR bandwidth
usage: maxout.sh [SECS=300] [URL_A] [URL_B]      report: ~/maxout/report.txt
Needs: ~/maxout/{npu_analyze.py,ddrbw.c}, ~/demo/rkvenc-enc, ~/npu-venv, ~/npu/models. Abort if any zone > 95 C.
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

