# suspend: Suspend/resume: RTC-alarm s2idle cycles with post-resume checks (USB3, DP, HDMI, SATA, network), resume watchdog and per-device resume-delay bisect modules

- Runs on: **board** (copy this directory to the board, e.g. with `scp -r`)
- How it was run: `sudo bash s2idle-cycles.sh 50`
- Notes and detailed results: [`topics/suspend/`](../../topics/suspend/README.md)
- Reference numbers: [`docs/RESULTS.md`](../../docs/RESULTS.md); how to re-run everything: [`docs/TESTING.md`](../../docs/TESTING.md); clips: [`docs/TEST-MEDIA.md`](../../docs/TEST-MEDIA.md)

These are the scripts exactly as they were run on the test board, except that the lab's own values are now defaults you can override: `OPI5_PI` (board login, default `ubuntu@orangepi5`), `OPI5_PI_IP` / `OPI5_HOST_IP` (board and host addresses, default the `scripts/nat-on.sh` subnet 172.31.55.0/24) and `$HOME` for the board user's home directory. Paths such as `~/demo` or `~/codecsweep` are on the board. Test media is not included (see TEST-MEDIA.md). C files are built on the board with `gcc -O2 -o <name> <name>.c` (plus `-ldrm` for DRM tools: see the file's header).

## Files

### [`s2idle-cycles.sh`](s2idle-cycles.sh)

```
Fast s2idle cycling proof: N cycles of real s2idle (default console, no
pm_print_times), RTC wake, and device checks after every resume.
usage: sudo [COPY_DIR=/mnt/extreme] s2idle-cycles.sh <N> [logdir]
COPY_DIR: a directory on a mounted filesystem of the USB3 drive; each cycle
starts a 256 MiB file copy into it just before suspend and checks the copy
after resume (never writes the raw block device).
Stops at the first failed check. A wedge shows up as a watchdog reboot (the
log then ends without "cycle k: OK").
```

### [`susp-run.sh`](susp-run.sh)

```
usage: susp-run.sh <tag> <s2idle|deep> <pm_test> [rtcwake_seconds]
```

### [`susp-check.sh`](susp-check.sh)

```
post-step checks for suspend testing
```

### [`bisect-attempt.sh`](bisect-attempt.sh)

```
One bisect attempt for the fast-s2idle resume wedge (bug 3).
usage: sudo bisect-attempt.sh <tag> <events> <phases> <invert> "<match>" [delay_ms]
events 1=suspend 2=resume 3=both; phases 0=normal only 1=all; match "" = all devices
PASS: /var/tmp/susp-logs/<tag>.log ends with rc=0 and "resume_delay: done ...".
FAIL: board wedges after wake; dw_wdt resets it ~44 s later (look at the serial log).
```

### [`rtc-set.py`](rtc-set.py)

```
Set /dev/rtc0 from the (NTP-synced) system clock and read it back:
python3 -I rtc-set.py          set + read back (as root)
python3 -I rtc-set.py --read   read back only
struct rtc_time: sec, min, hour, mday, mon (0-11), year-1900, wday (0=Sunday), yday (0-365), isdst.
The weekday matters: the hym8563 alarm matches minute, hour, day AND weekday.
```

### [`resume_wd.c`](resume_wd.c)

```

Debug-only "resume watchdog": a dummy platform device whose noirq
resume callback arms a timer.  If PM_POST_SUSPEND has not been seen
@timeout seconds later, dump the tail of the kernel log (so that
pm_print_times can be collected with a quiet console), NMI
backtraces of all CPUs and the blocked tasks.

include <linux/module.h>
include <linux/platform_device.h>
include <linux/suspend.h>
include <linux/timer.h>
include <linux/percpu.h>
include <linux/atomic.h>
include <linux/sysrq.h>
include <linux/printk.h>
include <linux/kmsg_dump.h>
include <linux/slab.h>
```

### [`resume_delay.c`](resume_delay.c)

```

Debug-only: busy-wait @delay_ms before selected device PM callbacks, to
reproduce the "slow serial console" timing (~20 ms per device with
pm_print_times at 115200 baud) without a console, and bisect which
device(s) need the gap.

Parameters (all writable at runtime under /sys/module/resume_delay/parameters):
events   bitmask: 1 = suspend side (PM_EVENT_SUSPEND), 2 = resume side
(PM_EVENT_RESUME); 0 disables
phases   0 = normal phase only (skip "late"/"early"/"noirq" callbacks),
1 = all phases
match    comma-separated substrings of dev_name() of the device or any
of its ancestors (selects a subtree), or of the driver name;
empty = every device
invert   1 = delay devices that do NOT match
delay_ms busy-wait per matching callback (tracepoint probes run with
preemption disabled, so this cannot sleep)

include <linux/module.h>
include <linux/tracepoint.h>
include <linux/device.h>
include <linux/delay.h>
include <linux/pm.h>
include <linux/suspend.h>
include <linux/string.h>
```
