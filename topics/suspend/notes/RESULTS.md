# Suspend test results: Orange Pi 5 (RK3588S), 7.3.0-opi5 #2, TF-A v2.15.0 + PHP-CRU patch (SPI NOR)

Date: 2026-10-29, 19:04 to 20:40. Board: SATA root, GbE end0, USB-C DP dongle (USB3 hub + AX88179 in cdc_ncm
mode, DP alt mode), UVC webcam on USB2 (ehci fc880000). From 19:20 the TV was on HDMI0 (4K60/4K120 FRL) and DP-1
was disconnected. From 19:24 the media drivers were loaded (coordinator demo).
Logs on the board: `/var/tmp/susp-logs/<step>.log` (dmesg from the step marker on). Serial log:
`~/.claude/jobs/35761d63/tmp/serial-hang.log`. Runner: `/var/tmp/susp-run.sh <tag> <s2idle|deep> <pm_test> [rtcwake s]`,
checks: `/var/tmp/susp-check.sh` (copies in `tools/`).

## Summary

| Step | Result |
|---|---|
| P0 test boot (media modules blocked) | OK |
| P1 RTC alarm awake | OK (hym8563 is IRQ 60-65 depending on boot; alarm has 1-minute resolution and is rounded **down**) |
| P2 CPU hotplug 7..1 and back | OK; CPU4/6 come back at an "unlisted" SCMI rate (see bug 2) |
| S1 freezer (s2idle) | OK |
| S2 devices (s2idle) | OK: SATA, GbE, USB, DP all fine |
| S3 platform (s2idle) | OK, but **DP link dead after resume** (bug 1) |
| S4 deep platform / processors | OK (DP bug 1 again) |
| S4 deep core | **kernel BUG in cpufreq_online on CPU6 → panic** (bug 2) |
| S5 real s2idle, verbose console (pm_print_times on serial) | OK 3/3 (S5a, S5b, S5i): woke on hym8563, SATA/GbE/USB/HDMI/devfreq fine |
| S5 real s2idle, fast console (quiet, or no pm_print_times) | **hangs on resume 10/10** (S5c-S5h, S5j, X1-X3, Y1); interconnect wedged, dw_wdt resets it ~44 s after wake (bug 3) |
| S6 real deep | not run: bug 2 BUGs on every deep resume that re-onlines a big core at an unlisted rate, and bug 3 is unresolved |

Testing was stopped at 20:20 by the coordinator (user postponed). Resume time and power draw were not measurable:
every fast resume hangs, and verbose resumes are console-bound (~6 s). rk806 PWRCTRL pins are pin_fun0, so PMIC_SLEEP
is ignored and nothing is saved in s2idle beyond clock/PD gating.

## Evidence per step

- **Baselines (P0):** suspend_stats all 0; mem_sleep `s2idle [deep]`; genpd on: pcie, gmac, usb, vo0/vo1, vop; RTC
  hym8563 alarm IRQ (63/65/60..62 depending on boot), rk806 IRQ 71, pwrkey 72/73. Wake sources: hym8563 (6-0051),
  alarmtimer, rk805-pwrkey, tcpm-source-psy.
- **P1:** `echo +120 > wakealarm` at 19:06:14 → alarm 19:08:00 (rounded down to the minute), IRQ fired at 19:08:00.
- **P2:** offline 7..1, online 1..7, OK. cpufreq after: 1.8 GHz / 1.2 / 1.2 GHz, ondemand. On re-online:
  `cpufreq_policy_online: CPU4: Running at unlisted initial frequency: 1116000 kHz, changing to: 1200000 kHz`
  (also CPU6 1119 MHz) — harmless here, fatal during resume (bug 2).
- **S1 freezer:** OK, 5.36 s total.
- **S2 devices (s2idle):** OK. SATA read 387 MB/s, write 383 MB/s, ping OK, all USB devices back (same device
  numbers), DP-1 connected/enabled. "Suspend/resume of devices complete after 5.7/5.9 s" is serial-console time:
  pm_print_times writes ~57 KB per phase at 115200 baud. `xhci-hcd.{1,8}.auto: xHC error in resume, USBSTS 0x401/0x411,
  Reinit` on every resume: DWC3 is powered down in system suspend (dwc3_core_exit), so xHCI loses its state and
  xhci_resume re-initialises it — expected for this glue, devices re-enumerate fine.
- **S3 platform (s2idle):** completes; late 63 ms, noirq 598 ms; **DP: 40× `dw-dp: timeout waiting for AUX reply`,
  `failed to enable link: -110`**, /dev/drm_dp_aux0 dead until a DPMS cycle (`fb0/blank 1→0` restores it; DPCD reads
  back `12 14 c2 81 ...`). → bug 1.
- **S4 deep platform / processors:** complete (same DP failure). processors: all CPUs off/on via PSCI, "unlisted
  initial frequency" on CPU4 (1115 MHz) and CPU6 (2138 MHz → 2208 MHz).
- **S4 deep core:** syscore suspend/resume fine (`Timekeeping suspended for 5.080 seconds`), then while enabling
  CPU6: `_set_opp_voltage: failed to set voltage (987500 ...): -110` → `kernel BUG at drivers/cpufreq/cpufreq.c:1527`
  in `cpuhp/6` → panic → reboot (19:16). → bug 2.
- **S5a/S5b/S5i real s2idle, verbose console:** `PM: suspend-to-idle` … `Triggering wakeup from IRQ 61` (hym8563),
  pm_wakeup_irq=61, slept ~60-80 s (printk time stops in s2idle: `Timekeeping suspended for N s`); noirq resume
  946 ms, early 62 ms, resume devices ~6 s (console-bound). After resume: SATA 328-387 MB/s, GbE ping OK, USB all
  present (webcam, hub, AX88179), HDMI-A-1 connected/enabled 4K60, GPU/NPU devfreq alive (simple_ondemand),
  all media video nodes present (rkvdec, hantro, venc, rga, iep, jpegd), suspend_stats success incremented.
- **Real s2idle with a fast console:** see bug 3.

## Bug 1: dw-dp DP link dead after any resume that runs the noirq phase (FIXED, not yet hardware-verified)
- **Root cause:** dw-dp (Collabora series v11, our patches 0254/0255) has runtime PM ops only. device_prepare() holds
  a runtime ref, so the autosuspend queued by atomic_disable never runs. The controller stays RPM_ACTIVE while genpd
  powers PD_VO0 off in suspend_noirq (dw-dp is its only device). On resume it is still "active", so
  dw_dp_runtime_resume() → dw_dp_init_hw() (and the HPD GRF override) never runs, and atomic_enable times out on AUX.
  Seen in S3, S4 and S5i (also while DP-1 showed "disconnected": the DRM state still had DP enabled).
- **Fix:** `patches/0001-drm-rockchip-dw_dp-Add-system-sleep-PM-ops.patch` adds
  `LATE_SYSTEM_SLEEP_PM_OPS(pm_runtime_force_suspend, pm_runtime_force_resume)` in dw_dp-rockchip.c. Belongs on top of
  0255; worth sending to Sebastian Reichel as feedback on v11. Signed module built for kernel #2:
  `modules/rockchipdrm-dwdp-sleep-k2.ko`, never installed. It must be rebuilt for build 3; rockchipdrm is in the
  initramfs, so update-initramfs too. Verify with the DP dongle and the TV on DP: run S3 and check the AUX DPCD read.

## Bug 2: kernel BUG in cpufreq_online() when a CPU comes back during resume (FIXED in source, build-tested)
- **Root cause:** in suspend_enter(), non-boot CPUs come online before dpm_resume_noirq(). cpufreq_online() then reads
  the CPU clock. The SCMI clock is CLK_GET_RATE_NOCACHE, and TF-A's `clk_scmi_cpub*_get_rate()` returns the *measured*
  PVTPLL ring-oscillator rate (1115/1119/2138 MHz seen), which is never in the OPP table. So the "unlisted initial
  frequency" fix-up calls __cpufreq_driver_target(). That needs the rk8602/rk8603 regulator on I2C (i2c-rk3x is
  IRQ-driven; device IRQs are still suspended), so it gets -ETIMEDOUT and hits BUG_ON. Every deep suspend that
  re-onlines a big core will hit this.
- **Fix (kernel, right layer):** `patches/0002-cpufreq-Defer-the-unlisted-frequency-check-on-CPU-on.patch` moves the check
  into a helper, skips it while cpufreq_suspended (like cpufreq_init_governor()/cpufreq_policy_refresh() already do),
  and runs it from cpufreq_resume() (end of dpm_resume()). Compiles; it is in vmlinux, so it needs a full kernel
  package and was not installed.
- **Optional TF-A follow-up (not written):** report the programmed rate instead of the PVTPLL measurement for
  PVTPLL-sourced SCMI clocks, as the GPLL path already does ("Make the return rate is equal to the set rate").
- **Workaround for testing deep before the fix is in:** S6b (offline CPUs 4-7 before suspend).

## Bug 3: real s2idle resume wedges the SoC when resume runs fast (OPEN)
- **Symptom:** with pm_print_times on a 115200 serial console (~20 ms per device), s2idle passes 3/3. With a quiet
  console, or with PRINT_TIMES=0, it hangs 10/10 right after wake. The last lines are always
  `xhci-hcd xhci-hcd.1.auto (fcd00000, USB3 host on combphy2): xHC error in resume ... Reinit`, `usb5/usb6 root hub
  lost power`, and sometimes `ata1: SATA link up ... configured`. `xhci-hcd.8` (fc000000) and `usb 4-1` (ehci) never
  appear. dw_wdt resets the board 44 s later (auto-recovers, no power cycle needed).
- **What it is:** NMI backtraces (S5f, with irqchip.gicv3_pseudo_nmi=1 and the lockup detectors set to 10 s):
  softlockup in `rcu_exp_gp_kthread` waiting in `smp_call_function_single`. CPUs 0/3/4/6 were alive (idle). **CPUs
  1, 2 and 7 did not answer NMIs at all.** In S5d/S5g/S5h/S5j/X1 no CPU could print anything, including a per-CPU timer
  panic hook. So this is a bus/interconnect stall (an access to an unclocked or powered-off block), not a deadlock.
- **Ruled out:**
  - the PSCI cpu-sleep idle state (S5g, WFI only: still hangs);
  - async/sync ordering races (X1, pm_async=0: still hangs);
  - the webcam (X2 deauthorized; Y1 unplugged);
  - the USB-C DP dongle/tcpm (Y1, unplugged, still hangs: also rules out the dwc3-rockchip USBDP reset-hook lead);
  - leaving fcd00000's xHCI runtime-suspended (X3, it is still resumed);
  - the combphy USB3 PIPE-ready wait (present, no timeout warning).
- **Where it is:** the sync resume window from dwc3 fcd00000 + xHCI host2 through AHCI and the rk806/rk8602 regulators
  to ehci/ohci/dwc3 fc000000 (PD_USB), with a missing settle or ordering dependency that ~20 ms per callback hides.
- **Lead considered and dropped:** dwc3-rockchip's USBDP reset hook gates DWC3 register access on
  pm_runtime_active(), which is true while the core is system-suspended. That is a latent bug worth fixing, but it is
  not the cause (Y1 hangs without the dongle and tcpm, and the verbose run shows the PHY re-init inside
  dwc3_rockchip_resume with clocks on).

## Next steps to resume (bug 3)
1. Bisect by slowing only part of the resume. Extend `tools/resume-wd` to attach to the `device_pm_callback_end`
   tracepoint and mdelay(20) after selected devices (name filter as a module param). This reproduces the
   "slow console" effect without a console: first all devices (expect pass), then halve the set. Each run is ~3.5 min,
   recovery is automatic.
2. Prime suspects to delay first: `dwc3-rockchip fcd00000.usb` / `xhci-hcd.1.auto` (the hang follows its reinit every
   time), `ahci-dwc fe210000.sata` (combphy0, vcc3v3_pcie20), `rockchip-naneng-combphy fee00000/fee20000`, the
   PD_USB ehci/ohci, and the rk806 regulator resumes. Also check whether combphy2 (USB3, fcd00000) and combphy0
   (SATA) share PHP GRF / pipe-GRF bits that one init clobbers for the other.
3. Persistent logging for the wedge: DT reserved-memory ramoops (vendor BSP uses 0x110000) plus a kernel with
   CONFIG_PSTORE_CONSOLE/FTRACE, then `device_pm_callback_start` events survive the watchdog reset. Alternatively
   CONFIG_DPM_WATCHDOG and CONFIG_CSD_LOCK_WAIT_DEBUG in the next build.
4. After bug 3: install bugs 1 and 2 (rebuilt on build 3), repeat S5 3× (with media modules), then S6 deep
   (S6 plain with the cpufreq fix, S6b, S6c is the current default BL31), with no_console_suspend and pm_debug_messages.

## Debug tools (debug-only, not for upstream)
- `tools/susp-run.sh` (env: QUIET=1 quiet console, PRINT_TIMES=0, LOCKUP=1 for 10 s soft/hard-lockup + all-CPU
  backtraces, INITCALL_DEBUG=1), `tools/susp-check.sh` (post-resume checks incl. HDMI/devfreq/video nodes).
- `tools/resume-wd/resume_wd.c`: a dummy device whose noirq resume arms per-CPU timers. If PM_POST_SUSPEND hasn't
  come after `timeout` s, it re-emits the log tail (pm_print_times collected silently), runs sysrq-l/-w, then panics.
  It works when CPUs can still reach the UART; it can't help when the interconnect is wedged.

## Kernel work tree
`~/orangepi5/work/suspend-test-7.3`, branch `opi5/suspend-test-7.3-k2`: de0c4208f (= kernel #2 source,
patches/linux 0001-0514 as applied in src/linux), then 2c753bace (dw_dp sleep ops) and a41c2f3fe (cpufreq). Also
created: an empty branch `opi5/suspend-test-7.3` (from opi5/suspend-7.3). Build dir `~/orangepi5/build/wt-suspend-test/`
(the full deb build was stopped: superseded by build 3).

## Board state left behind
- Cmdline restored to the coordinator's version (`... console=tty1 video=HDMI-A-1:3840x2160@120`; my
  irqchip.gicv3_pseudo_nmi=1 removed, u-boot-update run). My backup of the earlier file: /var/tmp/u-boot.default.pre-suspendtest.
- pm_test=none, mem_sleep deep (default), pm_async back to 1 after the reboots, no /etc/modprobe.d/zz-suspend-test.conf
  (removed by the coordinator; its copy is /var/tmp/zz-suspend-test.conf.agent). No modules or DTB installed by me.
- Leftovers in /var/tmp (harmless): resume_wd.ko, susp-run.sh, susp-check.sh, susp-logs/.
- **RTC: the hym8563 has no backup battery.** After the power cycle at ~20:16 it read "no valid clock". I set it from
  NTP time with RTC_SET_TIME at 20:17. It will be lost again on the next power loss; rtcwake fails until it is set.
- Webcam and DP dongle are unplugged (user).
