# Suspend test plan (not run; needs the user present for anything that may need a power cycle)

Serial is logged on /dev/ttyUSB0 @115200 by the coordinator. Board has panic=10, panic_on_oops=1, systemd RuntimeWatchdogSec=30s (the watchdog is frozen while dw_wdt is suspended).

**P0 test boot:** block experimental modules (`/etc/modprobe.d/zz-suspend-test.conf` with `install <mod> /bin/false` for rockchip_jpegd rocket hantro_vpu rockchip_vdec rockchip_rga rockchip_iep), reboot. Logging: `dmesg -n 8`; `sysrq=1`; `console_suspend=N`; `pm_print_times=1`, `pm_debug_messages=1`. Baselines: suspend_stats, pm_genpd_summary, `/proc/interrupts` hym8563/rk806.
**P1 RTC alarm awake (no risk):** `echo 0 > wakealarm; echo +120 > wakealarm`; check `/proc/driver/rtc`, IRQ 60 count rises after ~125 s. Fail → stop.
**P2 CPU hotplug (low–medium, <5%):** offline CPUs 7..1, online again; check cpufreq.
**S1 freezer (~1%):** `mem_sleep=s2idle; pm_test=freezer; echo mem > /sys/power/state`.
**S2 devices, s2idle (~10%):** `pm_test=devices`; then check SATA read (dd 200 MB direct), network, lsusb, dmesg.
**S3 platform, s2idle (~10%):** `pm_test=platform`.
**S4 deep pm_test (~15% each):** `mem_sleep=deep`; `pm_test=platform`, `processors`, `core`.
**S5 real s2idle (~25%):** `pm_test=none; mem_sleep=s2idle; rtcwake -m freeze -s 120`; check pm_wakeup_irq=60. Repeat 3x, then with media modules loaded.
**S6 real deep (~50%):** `mem_sleep=deep; rtcwake -m mem -s 120`. Variants: S6b offline CPUs 4-7 first; S6c patched BL31 (tf-a/0001); S6d rkbin BL31 fallback.
After each step: `dmesg | tail -300`, suspend_stats, pm_wakeup_irq, genpd summary, cpufreq, SATA read test, network.
Rollback: `pm_test=none; mem_sleep=deep; rm /etc/modprobe.d/zz-suspend-test.conf`.

Needed from the user: presence for S2+; approval for the test boot, P1, P2; confirm the RTC battery is fitted; whether the OPi5 has a power button; whether to reflash with the patched BL31 for S6 and whether to send the TF-A patch upstream.
