# vop2-underflow: VOP2 underflow test matrix: planetest (planes x formats x modes) under memory/bus load, underflow and IRQ counting

- Runs on: **board** (copy this directory to the board, e.g. with `scp -r`)
- How it was run: `sudo bash runtest.sh <label> <planetest args>`
- Notes and detailed results: [`topics/vop2-underflow-int/`](../../topics/vop2-underflow-int/README.md)
- Reference numbers: [`docs/RESULTS.md`](../../docs/RESULTS.md); how to re-run everything: [`docs/TESTING.md`](../../docs/TESTING.md); clips: [`docs/TEST-MEDIA.md`](../../docs/TEST-MEDIA.md)

These are the scripts exactly as they were run on the test board, except that the lab's own values are now defaults you can override: `OPI5_PI` (board login, default `ubuntu@orangepi5`), `OPI5_PI_IP` / `OPI5_HOST_IP` (board and host addresses, default the `scripts/nat-on.sh` subnet 172.31.55.0/24) and `$HOME` for the board user's home directory. Paths such as `~/demo` or `~/codecsweep` are on the board. Test media is not included (see TEST-MEDIA.md). C files are built on the board with `gcc -O2 -o <name> <name>.c` (plus `-ldrm` for DRM tools: see the file's header).

## Files

### [`irqrate.sh`](irqrate.sh)

```
irqrate.sh N : print VOP irq/s for N seconds
```

### [`play.sh`](play.sh)

```
play.sh <mode> <secs> <file> [decoder chain]: hold mode with modetest -d (console pattern on Cluster0),
play the file with kmssink on plane 59 (Esmart0), count POST_BUF_EMPTY frames + VOP irq/s
```

### [`qos.sh`](qos.sh)

```
qos.sh <prio_value|show>  -- set/show VOP NoC QoS priority (m0 + m1)
```

### [`rc.sh`](rc.sh)

```
rc.sh <label> <planetest args>: runs planetest, prints POST_BUF_EMPTY frames (printed+suppressed) and AXI ports used
```

### [`rt.sh`](rt.sh)

```
rt.sh <label> <planetest args>: run 4.5 s, print VOP irq/s for 3 s in the middle
```

### [`rtb.sh`](rtb.sh)


### [`rtl.sh`](rtl.sh)

```
rtl.sh <label> <hog threads> <planetest args>: like rtb.sh with a DDR hog running
```

### [`runtest.sh`](runtest.sh)

```
runtest.sh <label> <planetest args...>  -- runs one test, counts POST_BUF_EMPTY
```

### [`vm.sh`](vm.sh)

```
vm.sh <label> <hdmi mode> <dp mode|-> <load 0|1> <secs>
modetest -d holds the mode(s) with a pattern on each primary plane (console stand-in, no cursor);
kmssink skip-vsync=true plays the 4K60 clip on HDMI plane 59 and the 4K30 clip on DP plane 65.
```

### [`watch.sh`](watch.sh)

```
watch.sh <secs> <interval>: log POST_BUF_EMPTY (printed+suppressed) and per-port loads periodically
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

### [`devmem.c`](devmem.c)

```
devmem ADDR [VAL]: 32-bit MMIO read/write through /dev/mem (debug only) */
include <fcntl.h>
include <stdint.h>
include <stdio.h>
include <stdlib.h>
include <sys/mman.h>
include <unistd.h>
```

### [`memhog.c`](memhog.c)

```
memhog THREADS SECS: memcpy 64 MiB buffers in a loop to load DDR */
include <pthread.h>
include <stdlib.h>
include <string.h>
include <time.h>
```

### [`planetest.c`](planetest.c)

```

planetest - minimal atomic KMS plane bandwidth test (raw ioctls, no libdrm)

planetest [-c crtc] [-o conn] [-m WxH@R] [-t secs] [-s] P[:FMT[:WxH[:FBH]]][@X,Y,W,H] ...

Every plane listed is placed full screen on the CRTC; every other plane
currently on that CRTC is disabled. Each plane gets two framebuffers with
different content and the commit flips between them every vblank (unless
-s: static). FBH is the allocated buffer height (e.g. 2176 for rkvdec NV12),
the source rectangle is WxH. Prints the achieved flip rate.

include <errno.h>
include <fcntl.h>
include <poll.h>
include <stdint.h>
include <stdio.h>
include <stdlib.h>
include <string.h>
include <sys/ioctl.h>
include <sys/mman.h>
include <time.h>
include <unistd.h>
include <drm/drm.h>
include <drm/drm_mode.h>
include <drm/drm_fourcc.h>
```

### [`portload.py`](portload.py)

```
portload.py: active VOP2 windows, their AXI port (from the window registers) and estimated
fetch rate (src w*h*bpp*refresh), summed per port. Needs root (debugfs + /dev/mem).
```
