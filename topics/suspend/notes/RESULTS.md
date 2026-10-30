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
(the full deb build for #2 was stopped: superseded by build 3; see Update below).

## Board state left behind
- Cmdline restored to the coordinator's version (`... console=tty1 video=HDMI-A-1:3840x2160@120`; my
  irqchip.gicv3_pseudo_nmi=1 removed, u-boot-update run). My backup of the earlier file: /var/tmp/u-boot.default.pre-suspendtest.
- pm_test=none, mem_sleep deep (default), pm_async back to 1 after the reboots, no /etc/modprobe.d/zz-suspend-test.conf
  (removed by the coordinator; its copy is /var/tmp/zz-suspend-test.conf.agent). No modules or DTB installed by me.
- Leftovers in /var/tmp (harmless): resume_wd.ko, susp-run.sh, susp-check.sh, susp-logs/.
- **RTC: the hym8563 has no backup battery.** After the power cycle at ~20:16 it read "no valid clock". I set it from
  NTP time with RTC_SET_TIME at 20:17. It will be lost again on the next power loss; rtcwake fails until it is set.
- Webcam and DP dongle are unplugged (user).

## Update 2026-10-29 (after build 3)
- Both fixes are rebased onto build 3 (`opi5/integration-7.3` @ 1afa8d268) in `~/orangepi5/work/suspend-test-7.3`,
  branch `opi5/suspend-test-7.3-k3`: d9fc41cb1 (dw_dp sleep ops) and 741e2e2df (cpufreq). They cherry-picked cleanly;
  the touched files are identical to build 3's source. The trailer is now `Assisted-by: Claude:claude-opus-5-5`.
  `patches/0001-*dw_dp*` and `patches/0002-*cpufreq*` are regenerated from that branch.
- `modules/rockchipdrm-dwdp-sleep-k3.ko`: signed, no BTF, vermagic 7.3.0-opi5, built against build/linux (build 3).
  Not installed. To test it: put it in /lib/modules/7.3.0-opi5/updates/opi5-suspend/, run depmod -a, back up the
  initrd and run update-initramfs -u (rockchipdrm is in the initramfs), then reboot. Then S3 (pm_test=platform,
  s2idle) with DP on: expect no AUX timeouts and a DPCD read OK. S3 doesn't hit bug 3.
- The cpufreq fix needs a full kernel package (built-in code); not built for build 3.

## Bug 3 bisect plan (prepared host-side, for one batched suspend window)
**Tool:** `modules/resume_delay-k3.ko` (source `tools/resume-delay/resume_delay.c`; signed for build 3, W=1 and
checkpatch clean). It hooks the `device_pm_callback_start` tracepoint and busy-waits `delay_ms` (default 20, about
the pm_print_times console cost per device) before each matching callback. Params, writable at runtime:
`events` (1 suspend, 2 resume, 3 both), `phases` (0 normal phase only, 1 incl. late/early/noirq), `match`
(comma-separated substrings of the device name **or any ancestor**, so `fcd00000` = the whole USB3-host2 subtree;
it also matches the driver name; empty = all), `invert`. It logs `resume_delay: armed ...` and `done, delayed N
suspend and M resume callbacks`.
**Runner:** `tools/bisect-attempt.sh <tag> <events> <phases> <invert> "<match>"` → loads the module once per boot and
runs `susp-run.sh <tag> s2idle none 120` with PRINT_TIMES=0 (the fast console that reproduces 10/10).
**Setup once per boot:** copy `resume_delay-k3.ko`, `bisect-attempt.sh`, `susp-run.sh` to /var/tmp; check
`/proc/driver/rtc` has a valid date (otherwise `python3 -I rtc-set.py`); `sysrq=1`. Webcam/dongle state doesn't matter (Y1).

**Signatures**
- PASS: `rc=0` in `/var/tmp/susp-logs/<tag>.log`, `resume_delay: done ...`, susp-check OK.
- FAIL: serial stops after `xhci-hcd.N.auto: xHC error in resume ... Reinit` / `usb5/6 root hub lost power`
  (sometimes `ata1 ... configured`), optionally `soft lockup ... rcu_exp_gp_kthr` ~26 s later, then the DDR blob ~44 s
  after wake. The board is back about 1.5 min later.

**Sequence** (stop at the first conclusive point):
| # | events phases invert match | Expect | Meaning |
|---|---|---|---|
| A1 | 3 0 0 "" | PASS | the delay reproduces the slow-console effect (if FAIL: A1b `3 1 0 ""`; if that also fails, timing isn't the trigger → go to pstore/ramoops, next steps 3) |
| A2 | 2 0 0 "" | PASS → resume side; FAIL → suspend side (then A2b `1 0 0 ""` to confirm, and bisect the suspend side with the same sets) |
| A3 | 2 0 0 "fcd00000,fe210000,fee00000,fee20000" (USB3 host2 subtree, AHCI, both combphys) | PASS → culprit in this set | FAIL → A3i `2 0 1` same set (everything else) |
| A4 | 2 0 0 "fcd00000" | PASS → the USB3-host2 resume (dwc3 + combphy2 + xHCI reinit) needs a settle gap | FAIL → A4b "fe210000,fee00000" (SATA path) |
| A5 | 2 0 0 "xhci-hcd" (driver match: only xHCI + root hubs of both hosts) vs "dwc3" | split dwc3/PHY bring-up from xHCI reinit |
| A3i branch | 2 0 0 "regulator,spi2.0,0-004,2-0042" then "fc8,fc000000,fed80000" (PD_USB ehci/ohci/dwc3 + USBDP) | bisect the rest |
Then confirm: 2 attempts with only the final set delayed (PASS) and 1 with the final set excluded (`invert=1`, FAIL).
After that, find where the missing wait belongs in that driver (PLL/PIPE lock, power-domain or regulator settle)
and write the fix.

**Estimate:** PASS ≈ 3 min (60-120 s sleep, since the hym8563 alarm rounds down, plus ~12 s of injected delays),
FAIL ≈ 4 min (wake + 44 s watchdog + ~60 s boot + reload). A typical path is A1, A2, A3, A4, A5 plus 3 confirmations,
8 attempts at about half FAIL: **≈ 30 min; plan a 40 min window.** Each FAIL is a watchdog reset that interrupts every other
agent on the board.

## Bug 3 on kernel 5 (2026-10-30 slot, 15:30-16:10)
Setup: RTC set and read back with weekday (tools/rtc-set.py, fixed), awake alarm self-test OK, freezer OK.
| # | change | result |
|---|---|---|
| B0b | none (fast: PRINT_TIMES=0) | WEDGE: `xHC error in resume, USBSTS 0x401, Reinit` (xhci-hcd.1 = fcd00000), root hub lost power, soft lockup rcu_exp_gp 26 s later |
| A1 | 20 ms busy-wait before every normal-phase callback, suspend+resume | WEDGE |
| A1b | same, all phases incl. late/early/noirq | WEDGE |
| T1 | kprobe 20 ms at `xhci_halt` entry (inside xhci_resume, right before the reinit) | WEDGE |
| V1 | verbose (pm_print_times on console) with fbcon unbound: serial-only | PASS |
| M1/M2 | per-CPU markers in DRAM (dma_alloc_coherent, low DRAM and CMA) | WEDGE; markers did not survive the reset/boot |
| F1 | dwc3 drop-in that reports `power_lost` to xhci-plat | WEDGE: the SRE is gone, but the xHC never completes a command: `Error while assigning device slot ID: Command Aborted` 11.8 s after resume, re-init, again 12 s later, `usb 6-1: device not accepting address`, then the wedge |
Findings:
- It is not a settle delay between or inside device callbacks: no injected delay hides it. Printing the PM trace to the serial console does (V1).
- After a fast resume, the fcd00000 (USB3OTG2, combphy2) xHC is non-functional: the command ring never runs (Enable Slot times out), even after a clean reset. A register access on that block later stalls the interconnect.
- `patches/candidate/0001-usb-dwc3-Tell-xhci-plat-when-the-core-lost-its-state.patch` (branch `opi5/suspend-fix-7.3-k5`, 82667eae3): correct handling for a power-lost core (as cdns3 does) and removes the bogus CRS/SRE, but **does not fix the wedge**. Not added to patches/linux.
- My pm_marker v1 panicked the board (SError: the top 16 KiB of the 0xfd600000 SRAM window isn't backed). v2 used DRAM.
Next (host-side first):
1. Find what blocks the xHC's command ring/DMA after resume. Leading hypothesis: USB3OTG2 sits in the PHP block (with PCIe/SATA/combphys); its bus path or PHP-GRF/QoS state depends on the genpd "pcie" domain (or PHP NIU idle), which genpd powers off in suspend_noirq because its only modelled device is the fc900000 SMMU, while fcd00000 has no power-domains property in the DT. Check the TRM / vendor DT (BSP puts usbhost3_0 in a domain?) and PD_PCIE/PHP idle and QoS restore. A matching fix would be a DT power-domains link for usb_host2_xhci or a correct genpd hierarchy.
2. Second hypothesis: the combphy2 PIPE clock or USB3 port state (reset released before the clocks in dwc3_core_init_for_resume; combphy exit gates the clocks before asserting reset).
3. Persistent markers need a real reserved region: a DT reserved-memory ramoops node, with CONFIG_PSTORE_PMSG/CONSOLE or my marker module pointed at it.
4. Then the 50-cycle proof (`tools/s2idle-cycles.sh`, now also fails on "xHC error in resume") plus 5 cycles with a copy to the Extreme (6-1).
Board left: plain #5, updates/ empty (drop-in removed, depmod), initrd restored from /var/tmp/initrd.img-7.3.0-opi5.pre-suspendfix,
no test modules loaded, vtcon1 rebound, pm_test none, RTC set correctly (weekday OK). Files left in /var/tmp (tools, modules, susp-logs).

## Power-domain test slot (2026-10-30 16:20-16:32), plain kernel 5
Verified with `pm_test=platform` and the genpd debugfs counters (`/sys/kernel/debug/pm_genpd/<pd>/idle_states` usage):
without help, `pcie`, `usb` and `gmac` each power off once per s2idle (suspend_noirq). `tools/pd-keep` (wakeup path on
fc900000.iommu → PD_PCIE; pd_keep2 on fc800000.usb → PD_USB) and `tools/pd-keep3` (PM syscore device fe1c0000.ethernet → PD_GMAC)
hold them on (usage unchanged).
| # | domains held on during s2idle | result |
|---|---|---|
| P1 | pcie | WEDGE (`xHC error ... 0x401`, Command Aborted 11 s later, soft lockup) |
| P2 | pcie + usb | WEDGE (same) |
| P3 | pcie + usb + gmac | WEDGE (same) |
**Power-domain transitions are not the trigger**; the 0131 / PD_PCIE lead is dropped, and test 2 (DTB without 0131's PD link) was skipped as moot.
TF-A's PHP CRU gate save/restore (our tf-a/0001) is only in the SYSTEM_SUSPEND (deep) path, which s2idle never enters.
Still standing: after a fast s2idle resume the fcd00000 (USB3OTG2 + combphy2) xHC never executes a command, even after a clean
reset (F1), and later an access wedges the interconnect. Only console printing of the PM trace hides it.
Next (one slot, ~30 min, ≤3 resets, no reboot):
- S1: `pd_keep3 devname=fcd00000.usb` (dwc3 host2 excluded from system suspend: no dwc3_core_exit/init, no combphy2 phy_exit/init;
  its xhci child still suspends/resumes normally). PASS → the culprit is the dwc3/combphy2 teardown and re-init. FAIL → look outside host2.
- S2 (if S1 passes): exclude only the combphy (keep dwc3 suspend) is not possible separately; instead check the reset/clock order
  in dwc3_core_init_for_resume (reset deasserted before clocks) and combphy2 exit (clocks gated before reset asserted) with a patched dwc3/combphy module.
- With a DTB slot: the ramoops overlay + pm_marker v3 (phys=0x30200000) to name the hanging access.

## USB-controller exclusion slot (2026-10-30 16:33-16:43), plain kernel 5
`tools/pd-keep3`/`pd-keep4` mark a device as a PM syscore device (the PM core skips it entirely in system suspend/resume).
| # | excluded from system suspend | result |
|---|---|---|
| S1p | fcd00000.usb (pm_test=platform) | OK; xhci-hcd.1 no longer reports SRE (xhci-hcd.8 still does) |
| S1 | fcd00000.usb (dwc3 host2) | WEDGE, no host2 xHC message at all |
| S2 | fc000000.usb (dwc3 Type-C, USBDP, dock) | WEDGE (host2 SRE/Reinit, then lockup) |
| S3 | both fcd00000.usb and fc000000.usb | WEDGE: serial stops right after `PM: early resume of devices complete`, before any normal-phase output |
**The USB controllers are not the trigger**; the xHC lines were only the first (async) prints of the normal resume phase.
The wedge is in the very first part of the normal resume phase, or in an interrupt handler that runs as soon as
`resume_device_irqs()` re-enables device IRQs at the end of noirq resume (e.g. a handler touching a device whose
normal-phase resume hasn't run yet).
Next: bisect by exclusion (syscore), not delay. Extend pd-keep3 to a comma-separated device list and halve the early
normal-phase set: usb2phy (fd5d*), naneng combphys (fee00000, fee20000), hdptx phy (fed60000), clk/qos/dfi, efuse,
tsadc, pwm, saradc, i2s, pinctrl/gpio, rk806 regulators, SATA (fe210000). In parallel, check the threaded handlers that
run first after wake (hym8563 alarm on i2c6/GPIO0_B0, fusb302, rk806) for accesses to not-yet-resumed hardware.

## Exclusion bisect (2026-10-30 16:45-17:27, plain kernel 5) → **culprit: OHCI (ohci-platform) system suspend/resume**
Tool: `tools/pm-exclude` (`modules/pm_exclude-k5.ko`): makes a list of platform/AMBA devices PM syscore devices (skipped by
the PM core in system sleep); `prefix=1` matches name prefixes, `skip=` exempts (the watchdog must stay excluded-from-exclusion).
IRQ trace of a passing verbose run (`susp-logs/V2.trace` on the board, irq_handler_entry + device_pm_callback_start): first device IRQs after
resume_device_irqs are hym8563 (wake) and i2c6 transfers; display IRQs start only after their own resume — no early-IRQ hazard seen.
| # | excluded | result |
|---|---|---|
| E1 | dw-dp, dfi, hdptx phy, tsadc, pwm, i2s, rng, connector-usb3 | WEDGE |
| E2 | 3× pl330 (AMBA), 3× i2c, 2× spi, SATA | WEDGE |
| E3 | all 151 MMIO platform devices (fb/fc/fd/fe/ff) except watchdog | **PASS** (first clean fast resume: devices 200 ms) |
| E4 | media + NPU + their IOMMUs (fda/fdb/fdc, 35) | WEDGE (not rkvdec) |
| E5 | display + GPU (fdd/fde/fb) | WEDGE |
| E6 | fe* + fc* (31) | **PASS** |
| E7 | console UART feb50000 | WEDGE |
| E8 | 4× ehci/ohci, SMMU, USBDP phy, sdmmc | **PASS** |
| E9 | 4× ehci/ohci | **PASS** |
| E10 | both OHCI (fc840000, fc8c0000) | **PASS** |
| E11 | OHCI host0 only | WEDGE |
| E12 | OHCI host1 only | WEDGE |
→ Either OHCI instance suspending/resuming is enough to wedge the SoC after a fast s2idle; with both OHCIs kept out of system sleep,
fast s2idle resumes cleanly (SATA, GbE, USB3 links, DP and HDMI fine; the fcd00000 "xHC error ... Reinit" still appears and is harmless).
Note: the OHCIs are runtime-suspended at idle (no runtime PM callbacks; genpd PM_CLK handles their clocks), while their EHCI
companions (same HCLK_HOST*/HCLK_HOST_ARB*/ACLK_USB, same u2phy host port and 480M clock) have no runtime PM. Clock enable counts
stayed balanced across a pm_test=platform cycle.
Next (host-side): walk ohci_platform_suspend/resume + ohci_suspend/ohci_resume for a runtime-suspended, PD_USB-power-cycled
OHCI on RK3588 (register access with the controller/PHY not clocked, reset ordering, the EHCI companion handshake), write the fix,
test with fast s2idle, then the 50-cycle proof.

## Root cause found and fixed in source (2026-10-30 17:50-18:11, kernel 5 + debug drop-ins)
Debug drop-ins (branch `opi5/suspend-debug-ohci`, not for upstream): `ohci-platform` with `dbg_skip_resume_hw` /
`dbg_skip_hw` / `dbg_keep_power`, `phy-rockchip-inno-usb2` with `dbg_no_reset` (all dev_dbg-only).
| # | knob | result |
|---|---|---|
| Ka | inno-usb2 `dbg_no_reset=1` (no RK3588 PHY reset on port power-up) | WEDGE → PHY reset is not the cause |
| Kb | ohci-platform `dbg_skip_resume_hw=1` (skip `ohci_resume()`) | PASS |
| cyc5b | same, `s2idle-cycles.sh 5` (USB3 links, DP status+AUX, HDMI, SATA read, network, dmesg) | **5/5 OK** (+Kb and an earlier cycle: 7 consecutive clean fast resumes; ~25/25 wedges without) |
After Kb the OHCI root hubs log "root hub lost power or was reset" during their own resume, i.e. the deferred restart works.
**Root cause:** for a controller that lost power (PD_USB is cycled by genpd in every s2idle), `ohci_resume()` → `ohci_rh_resume()` →
`ohci_restart()` runs `ohci_init()+ohci_run()` (USBOPERATIONAL, schedule DMA) from the controller's system resume callback,
while the root hub PHY is still powered off — the USB core powers it only in `hcd_bus_resume()` (system resume, before
`->bus_resume()`). On RK3588 that wedges the USB interconnect (xHCI commands abort, CPUs stop taking IPIs/NMIs).
EHCI's lost-power path only resets and leaves the controller halted, which is why EHCI alone is fine.
Runtime PM is unaffected: root hub PHYs are powered off only for system suspend (`!PMSG_IS_AUTO`).
**Fix:** `patches/k5/0002-usb-ohci-Don-t-restart-a-controller-that-lost-power-.patch` (branch `opi5/suspend-fix-7.3-k5`,
e9af7c77c4ad): in `ohci_resume()`, only `ohci_usb_reset()` when the controller lost its state; the root hub resume
(`usb_hcd_resume_root_hub()`) then finds HCFS==USBRESET and restarts it from `hcd_bus_resume()` after the PHYs are up.
ohci-hcd is built in (CONFIG_USB_OHCI_HCD=y) → needs a full kernel package to install. Builds clean with W=1; checkpatch: only the missing SoB.
**Also:** `patches/k5/0001-usb-dwc3-Tell-xhci-plat-when-the-core-lost-its-state.patch` (82667eae3): independent; dwc3 reports
power loss to xhci-plat (as cdns3 does) so xhci_resume skips the doomed CRS restore (`xHC error in resume, USBSTS 0x401, Reinit`)
— correct on its own, not needed for the wedge. dwc3 is a module.
Both apply on top of patches/linux (314) on clean v7.3 (316 total).
Why the slow console hid it: not established. Injected delays (anywhere, incl. inside xhci_resume) never did; heavy serial
printing did. The commit message says so instead of guessing.
Proof still to do: 50 fast cycles + 5 with a copy to the Extreme (`COPY_DIR=` in s2idle-cycles.sh) on a kernel with the fix.

## Proof attempt 1 (2026-10-30 20:15-20:25): FAILED
Test kernel 7.3.0-opi5-susp (v7.3 + patches/linux 314 + ohci 0002 + dwc3 0001, branch `opi5/suspend-fix-7.3-susp`),
installed side by side (`board/susp-install.sh`, own "lsusp" label + susp-bootonce, no dpkg/u-boot-update).
Wedged on fast cycle 1 (journal ends at suspend entry; dw_wdt reset ~50 s after the alarm wake; kernel.printk=4 hid
the PM lines on serial). 0/50, 0/5, 0/20 RPM. Board restored (test kernel removed).
Differences from the passing Kb runs: (1) the patch still reads/writes OHCI registers in ohci_resume() (Kb skipped
it entirely) → possibly ANY early OHCI register access wedges; (2) on the test kernel the Extreme did not link
SuperSpeed at boot and came up at 480M via EHCI host1 (the blue port's USB2 lines go to fc880000/u2phy3, its SS
lines to host2), so a USB2 device was active on host1 during suspend; (3) the dwc3 power_lost patch.
The ohci patch is therefore NOT proven; it is not to be added to patches/linux yet.

## Follow-up slot (2026-10-30 20:25-20:41, kernel 5 + drop-ins: debug ohci-platform + dwc3 power_lost)
| # | setup | result |
|---|---|---|
| boot | dwc3 power_lost drop-in | Extreme SuperSpeed 6-1 at boot → dwc3 patch is not the 480M regression |
| C1 | Kb (skip ohci_resume) + dwc3 power_lost | PASS; "xHC error in resume, USBSTS 0x401" gone (only "root hub lost power") → dwc3 patch works and is harmless |
| A1x | emulate patch 0002 (read HcControl, write reset value, kick root hub) | WEDGE |
| A2x | only read HcControl, kick root hub | WEDGE |
| B1x | Kb with the Extreme forced onto OHCI host1 (host2 SS port disabled, device at 12M on fc8c0000) | PASS (device re-enumerated on EHCI host1 at 480M after resume) |
**Conclusion:** any OHCI register access from the controller's system resume callback (before the root hub's
hcd_bus_resume() powers the USB2 PHY) wedges RK3588 after PD_USB was power-cycled; a single HcControl read is enough.
EHCI register access in the same state is fine. Patch 0002 (which still reads/writes HcControl there) is wrong and is
withdrawn. Next: `dbg_phy_first` (built, `modules/ohci-platform-dbg2-k5.ko`: usb_phy_roothub_resume() before
ohci_resume(), unmodified ohci_resume) to prove "OHCI registers need the PHY up"; then v2 fix accordingly
(e.g. power the root hub PHYs before touching the controller on resume in ohci-platform, or defer the controller
resume work to the root hub resume without any register access).
Extreme at 480M on the test kernel: on plain #5 the drive always enumerates first at HS via EHCI host1 (usb 4-1,
3.16 s) and switches to SS on host2 (usb 6-1, 3.76 s); on the test kernel the SS link on host2 never came up. The dwc3
patch is cleared (SS on #5 with it), so it is a difference between build 5's stack and the current patches/linux
(e.g. 0270 / tcpm 0271-0274 / dwc3-rockchip changes) — to bisect separately.

## dbg_phy_first and v2 (2026-10-30 20:44-20:55, kernel 5 + debug ohci-platform)
PF1, PF2: root hub PHYs powered (usb_phy_roothub_resume) before the UNMODIFIED ohci_resume() → **PASS 2/2** (all four USB2
root hubs re-init, USB3/DP/HDMI/net fine). Mechanism proven: on RK3588 OHCI registers are only accessible with the USB2 PHY up.
**v2 fix** (`patches/v2/0002-usb-ohci-platform-Power-the-root-hub-PHYs-up-before-.patch`, branch `opi5/suspend-fix-7.3-v2`
477426cccf2d / on the 321 stack `opi5/suspend-fix-7.3-susp2` 46a5fdf42aca): ohci_platform_resume_common() brackets
ohci_resume() with usb_phy_roothub_resume()/usb_phy_roothub_suspend(). No double power-on: phy_init/exit and
phy_power_on/off are refcounted and only act on 0↔1, so the bracket is balanced and leaves the counts as hcd_bus_resume()
expects; a no-op on hardware if the EHCI companion already powered the shared PHY. `patches/v2/0001` = dwc3 power_lost (1104).
Other HCDs: xhci-plat on RK3588 is a dwc3 child without its own phys (dwc3_core_init powers the PHYs in the parent's
resume, before the child) → not affected. ehci-platform has the same structure but its registers are accessible with the
PHY down on RK3588 (E10, all Kb runs) → no change without evidence. v2 covers every generic-ohci + inno-usb2 SoC.
Test kernel 7.3.0-opi5-susp (pkg 7.3.0-susp2) = patches/linux (321) + 1104 + v2: building.
