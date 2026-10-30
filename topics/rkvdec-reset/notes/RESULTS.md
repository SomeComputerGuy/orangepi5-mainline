# rkvdec (VDPU381) core reset vs IOMMU: memory corruption after a timeout

Status: IN PROGRESS (host work done, board runs pending).

## 1. Sources (read, not copied)
- Rockchip BSP, develop-6.1: drivers/video/rockchip/mpp/
  [mpp_rkvdec2.c](https://github.com/rockchip-linux/kernel/blob/develop-6.1/drivers/video/rockchip/mpp/mpp_rkvdec2.c)
  (`rkvdec2_reset()`: PMU idle request, CRU assert of a/h/core/cabac/hevc_cabac, 5 us, deassert;
  RK3588 uses `rkvdec2_sip_reset()` = the same in TF-A),
  [mpp_rkvdec2_link.c](https://github.com/rockchip-linux/kernel/blob/develop-6.1/drivers/video/rockchip/mpp/mpp_rkvdec2_link.c)
  (`rkvdec2_soft_ccu_reset()`: disable_hardirq, CCU force idle, SOFTREST_EN, check SOFT_RESET_READY,
  check BUS_IDLE, CRU/SIP reset, clear CCU error, reconnect, `mpp_iommu_refresh()`, enable_irq;
  only when no core is working), [mpp_iommu.c](https://github.com/rockchip-linux/kernel/blob/develop-6.1/drivers/video/rockchip/mpp/mpp_iommu.c)
  (`mpp_iommu_refresh()` = `rockchip_iommu_disable()` + `rockchip_iommu_enable()`, i.e. stall, force reset,
  DTE, paging), and the BSP [rockchip-iommu.c](https://github.com/rockchip-linux/kernel/blob/develop-6.1/drivers/iommu/rockchip-iommu.c)
  (exports enable/disable/force_reset/mask_irq; mainline exports none of them).
- Mainline drivers/iommu/rockchip-iommu.c (v7.3): every attach goes `rk_iommu_identity_attach()` ->
  `rk_iommu_disable()` (enable stall, disable paging, DTE=0) -> `rk_iommu_enable()` (stall, force reset, DTE,
  zap, paging). A failed stall is only logged; paging is disabled anyway. A failed enable leaves the identity
  (bypass) domain. The iommu API exposes no stall/force-reset; the only way to reprogram an IOMMU from a
  consumer is a domain change (rkvdec: empty domain, then the shared domain).

## 2. Mechanism (from the code and the logs; to be confirmed by the measurements in §3)
- A page fault holds the faulting bus transaction of the core in its IOMMU (STATUS 0x4b: PAGING_ENABLED |
  PAGE_FAULT_ACTIVE | IDLE on one bank). The core then times out (hardware TIMEOUT irq or the watchdog).
- In-tree (stock) driver: on an error irq it calls `rkvdec_iommu_restore()` with the core NOT reset: empty-domain
  attach -> `rk_iommu_disable()` -> stall request times out (fault pending) -> paging disabled anyway -> the held
  transaction completes untranslated, to physical address = IOVA (DRAM is at 0..4 GiB on RK3588): kernel memory
  corruption; later faults are logged as "Page fault while iommu not attached to domain?" (domain = identity).
  On a watchdog timeout it writes the RK3399 IRQ_DIS bit to the wrong register, leaves the core running, completes
  the job and drops its PM reference: 100 ms later the IOMMU runtime-suspends (`rk_iommu_disable()`, bypass)
  under a core that still accesses memory. And a late irq after the timeout dereferences `core->curr_ctx == NULL`
  (the 10:28:33 panic, NULL+0x2f8 = `ctx->dev` in `rkvdec_irq_handler()`).
- CCU series (01ed182a): failed dependent frames were completed (buffers returned, PM references dropped, core
  marked free) while their cores were still decoding/waiting in the CCU, and the reset ran only later; and
  `rkvdec_iommu_restore()` ran after a CRU pulse whose effect on the IOMMU was not known.

## 3. Measurements (board, KASAN kernel 7.3.0-opi5-kasan, idle cores; rstprobe.txt)
rkvdec_rstprobe.ko powers a core up (runtime PM, which resumes its IOMMU), dumps both IOMMU banks and the core
status, resets, dumps again, and puts back what rk_iommu programmed. Before: DTE 0x12b0b100 (both banks),
STATUS 0x19 (paging enabled, idle, replay buffer empty), INT_MASK 3, AUTO_GATING 0x80000003.

| reset (core 0 / core 1)                      | IOMMU after                                        | core regs |
|----------------------------------------------|----------------------------------------------------|-----------|
| VDPU381 soft reset (SOFT_RESET_EN, RDY seen) | DTE 0, STATUS 0x18 (paging off), INT_MASK 0: bypass | IMPORTANT_EN cleared |
| all 5 DT lines (A,H,CA,HEVC_CA,CORE)          | DTE 0, paging off, INT_MASK 0: bypass              | kept |
| SRST_A_RKVDECn alone                         | bypass (same)                                      | kept |
| SRST_H_RKVDECn alone                         | unchanged                                          | kept |
| CA + HEVC_CA + CORE                          | unchanged                                          | kept |
| A_BIU + H_BIU asserted                        | any read of core/IOMMU MMIO while asserted: SError -> panic (first probe run, 17:3x) | - |

So: the AXI reset line (in the DT) and the core's own soft reset both reset its IOMMU into bypass; rk_iommu
still believes the domain is attached. Nothing may touch core/IOMMU MMIO while a reset line is asserted, and the
IOMMU must be reprogrammed after either reset before the core runs again (recover does; the DEBUG build's
"in-reset" dump was removed). The AUTO_GATING bit 31 survives.

## 3b. Upstream (stock in-tree driver, no 1801/1802), KASAN kernel
- FM1_BT_B + FM1_FT_E at once x120 and fluster JVT-AVC_V1 -j2 (129/135): 0 timeouts, 0 IOMMU faults, 0 KASAN.
  This trigger needs the CCU builds (timeouts sta 0x23); it does not reach the stock timeout path.
- Timeouts forced with a short watchdog (stock + `dbg_wd_us` only, 4-16 ms, 4K HEVC): at 4 ms 598 timeouts,
  survived; at 5-7 ms: "Enable stall request timed out 0x11", "Disable paging request timed out", "failed to set
  idle on domain 'rkvdec1'", then SError in rk_iommu_enable_stall() <- rk_iommu_resume() <- runtime resume:
  kernel panic (17:47, logs/p2-stockwd-serial-panic.txt). The stock watchdog leaves the core running (wrong
  register) and drops the PM reference: the IOMMU is disabled and the power domain switched off under a busy
  core. So the bug class exists upstream; 1802 fixes it (core reset before completion and before the PM put).

## 4. Design (one reset helper for both paths)
`rkvdec_core_recover()` (1802), called with the core's irq masked (threaded handler, or disable_irq() in the
watchdog/reset work), before the job is completed and before its PM reference is dropped:
1. stop new work: (CCU) force the core idle in the CCU; irq masked; in CCU mode no job starts while a reset is
   pending, and a frame that predicts from a failed one is failed with it;
2. quiesce: variant soft reset (VDPU381 SOFT_RESET_EN, wait SOFTRESET_RDY <=100 us, wait BUS_IDLE <=1 ms);
3. hard reset: pulse all reset lines of the core (always, as the BSP), which also resets its IOMMU and drops a
   transaction a fault holds;
4. reprogram the IOMMU (empty domain, then the shared domain: force reset, DTE, paging) - only now, with nothing
   pending; check the result;
5. (CCU) clear the CCU error bit, reconnect; a core that failed 2-4 is marked broken, stays disconnected and never
   runs again (its jobs fail);
6. only then complete the job(s); the irq handler takes the job only after winning cancel_delayed_work() of the
   watchdog (1801), so a late irq never sees a cleared/new job; watchdogs are cancel_delayed_work_sync()'d at unbind.
CCU (1614): the failed job and the dependent frames keep their cores and PM references until the reset work has
reset all cores (once each core is idle or failed-and-started); then they are completed with an error.

## 5. Branches / builds (host, done)
- in-tree: `opi5/rkvdec-reset-7.3` (worktree work/rkvdec-reset-7.3) = v7.3 + patches/linux (314) + 1801' + 1802'.
- CCU: `opi5/rkvdec-reset-ccu-7.3` (work/rkvdec-reset-ccu) = the above + the CCU series rebased (old 1616
  "quiesce a core before reinitializing its IOMMU" dropped: subsumed by 1802; 1609 and 1614 reworked to use
  `rkvdec_core_recover()`); every commit builds W=1 clean; checkpatch --strict clean (only the known MAINTAINERS
  note on the CCU-device patch).
- DEBUG-only test branches (never landed): `opi5/rkvdec-reset-dbg-7.3`, `opi5/rkvdec-reset-ccu-dbg-7.3` (register
  dumps per recovery step, `inject_fault=N`, `dbg_wd_us` watchdog override), `opi5/rkvdec-reset-stockdbg-7.3`
  (stock driver + `dbg_wd_us` only).
- Test kernel: 7.3.0-opi5-kasan (build/wt-rkvdec-reset-kasan from work/rkvdec-reset-kbase, build-5 config +
  KASAN generic inline + vmalloc, DEBUG_OBJECTS(_WORK/_TIMERS/_FREE), DEBUG_LIST, PROVE_LOCKING,
  DEBUG_ATOMIC_SLEEP): debs/; modules signed with its key: mods/{stockdbg,intree,ccu}, mods/rkvdec_rstprobe.ko.
- Board scripts: board/{rr.sh,install.sh,corrupt.py,canary(.c)} (canary = 1.5 GiB pattern checked every 15 s,
  catches DMA that bypassed an IOMMU into user pages).

## 6. Third bug found in P3: rockchip-iommu log_iova() and a reset IOMMU (upstream)
- First P3 run (KREV=2) panicked at 18:24 during fault injection: KASAN wild-memory-access, Oops in
  `rk_iommu_irq+0x490` = `log_iova()` (addr2line: rockchip-iommu.c:569/628). log_iova() reads MMU_DTE_ADDR back
  and dereferences it via phys_to_virt(); the core's soft reset (which VDPU381 also does by itself on a hardware
  timeout, STA_INT 0x23) resets the IOMMU, so a fault pending across it is handled with DTE_ADDR = 0 -> reads
  physical 0x130. Independent of rkvdec's own recovery; the iommu irq can't be masked through the API.
- Fix (new patch, after 1802): "iommu/rockchip: Don't walk a page table that a reset took away": no walk unless
  DTE_ADDR points to RAM; logs "fault while page table lost to reset"; the fault is still acked (zap,
  PAGE_FAULT_DONE, INT_CLEAR). In the KREV=3 P3 run this path was hit twice during injection, handled cleanly.
- Measured in P3: every error irq (STA_INT 0x23, hardware timeout) arrives with the IOMMU already in bypass
  (DTE 0, STATUS 0x18): the core reset itself and its IOMMU. A core that is reused before the IOMMU is
  reprogrammed DMAs untranslated: the most likely root cause of the CCU-build corruption (k5e/01ed182a reused
  or completed cores before/without a reliable reprogram); recover() always reprograms before reuse.

## 7. P3 proof runs: in-tree driver (1801 + 1802 + iommu fix, DEBUG instrumentation), KASAN kernel 7.3.0-5kasan3
Logs: logs/p3-intree/ (summary.txt, dmesg.txt, progress), fluster logs/fluster-rr-p3-intree/.
Totals over the whole boot (~80 min): 3178 recoveries, 2241 rkvdec timeouts, 96 injected faults, 109 IOMMU page
faults (all on injected IOVAs, 0 "not attached"), 14 "fault while page table lost to reset" (handled), 0 stall
timeouts, 0 KASAN, 0 ODEBUG, 0 lockdep/sleep, 0 list corruption, 0 BUG/Oops, 0 WARNING, 0 hung tasks, 0 cores
disabled, 0 physical-canary hits (decoder writes aimed at a 4 MiB canary's physical address), 0 user-canary hits.
| test | result |
|---|---|
| FM1_BT_B + FM1_FT_E at once x50 | 350 recoveries (error irq sta 0x23, IOMMU already in bypass at entry), all recovered |
| bit-exact after it (HEVC/H.264/VP9 4K, 600 frames each, second stream keeping both cores busy) | 600/600 x3; ~3500-4400 jobs per core per run |
| fault injection: decoder write address -> unmapped IOVA (canary PA), every 25th job | 24-48 faults/run, all recovered; then 600/600 x3 |
| fault injection: stream read address | 24 faults/run, recovered; then 600/600 x3 |
| corrupted streams (6 H.264 + 6 HEVC, random slice-byte damage) | 8-48 error irqs each, no timeouts; then 600/600 x3 |
| timeouts racing the interrupt (dbg_wd_us 4000/6000/8000 us; stock panicked here) | 858/395/2 and 569/413 timeouts, no crash; then 600/600 x3 |
| 30 min two 4K streams (H.264 + HEVC) paced at display rate | 161 + 293 passes, 0 failures |
| fluster -j2, all 4 suites | HEVC 146/147, AVC_V1 129/135, FR-EXT 65/69, VP9 230/305; failing vectors identical to the single-core reference |
| 200 close/reopen cycles x {normal, SIGKILL mid-stream, SIGKILL at start} with a 4K HEVC stream running | 0 hangs, 0 timeouts, 0 hung/D-state tasks |
(Harness note: the first exact runs after injection/corruption in this boot compared a stale md5 file because
ffmpeg -nostdin doesn't overwrite; rr.sh now deletes it first and those steps were re-run; the table has the re-runs.)

## 8. P4 proof runs: CCU series (1601-1616 on 1801/1802/1804, DEBUG instrumentation) + CCU DT overlay
Boot: "rkvdec rockchip,rk3588-vdec: 2 cores, decoding with the CCU". Logs: logs/p4-ccu/.
- ccu-repro (stream that passes alone, decoded next to one that makes the hardware fail), 5 runs each:
  HCBP1_HHI_A alone 5/5, + FM2_SVA_C 5/5, + FM1_FT_E 5/5 (the "victim next to a broken stream" case that once
  needed the unconditional CRU pulse), HCHP3_HHI_A + Hi422FREXT17 5/5, VP9 sharpness-7 + size-08x08 5/5.
- FMO pair x50: 680 recoveries, 0 IOMMU faults, 0 timeouts, 0 KASAN/ODEBUG/lockdep/oops.

### P4 hang (21:13) and the fix: lost wake-up in 1614
- hung_task: kworker in `rkvdec_ccu_reset_work+0x2e8` (addr2line: rkvdec.c, the
  `wait_event(rkvdec->reset_wq, rkvdec_cores_settled())`), gst-launch in `v4l2_m2m_cancel_job` <- STREAMOFF
  (SIGTERM of the 120 s timeout). sysrq-w (logs/p4-sysrq-w.txt): only those two rkvdec-related tasks blocked.
- Cause: core0's watchdog failed its job -> reset work started and waited for core1; core1 then failed (injected
  fault, irq 0x23) and was marked held (`needs_reset`) by rkvdec_core_failed(), which didn't wake reset_wq; only
  rkvdec_job_hw_done() did, and held cores don't call it. The deferred m2m job stayed deferred, so cancel_job
  waited forever.
- Fix (folded into 1614): rkvdec_core_failed() wakes reset_wq after marking the core and its dependents.

### Audit: every wait_event in the series and what wakes it (rebased tip)
| wait | condition | state it reads | where it changes -> wake |
|---|---|---|---|
| rkvdec_ctx_wait_jobs() (stop_streaming / release) on ctx->jobs_wq | !num_jobs && !num_completers | num_jobs, num_completers | num_jobs-- in rkvdec_ctx_complete_jobs() loop, num_completers-- at its end; wake_up(jobs_wq) under cores_lock right after num_completers-- (covers both) |
| rkvdec_job_wait_poc_alias() on ctx->jobs_wq | no earlier unfinished job aliases, or an earlier job failed (-EIO) | prev->hw_done, prev->core->needs_reset | hw_done=true in rkvdec_job_hw_done() + wake_up(jobs_wq) under the lock; needs_reset of the failed core in rkvdec_core_failed() + wake_up(jobs_wq); dependents are always later than the failed job, so its wake already ends every waiter (-EIO) |
| rkvdec_ccu_reset_work() on rkvdec->reset_wq | every core idle, or held (needs_reset) with its job started | core->job, core->needs_reset, job->started | core->job=NULL in rkvdec_job_hw_done() + wake_up(reset_wq); needs_reset=true in rkvdec_core_failed() + wake_up(reset_wq) (NEW); started=true in device_run() + wake_up(reset_wq) |
| v4l2_m2m (finished) | m2m core | TRANS_RUNNING | unchanged m2m code; the deferred m2m job is run by the reset work once pending is cleared (deferred_ctx set and read under cores_lock with ccu_reset_pending) |
No other wait_event/wait_for_completion in rkvdec or the series' v4l2-mem2mem changes.
