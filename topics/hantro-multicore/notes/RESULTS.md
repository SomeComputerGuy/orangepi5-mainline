# Hantro multi-core (RK3588 VEPU121 x4) - results

Branch `opi5/hantro-multicore` (on `opi5/multicore-7.3`), 4 commits, patches in `patches/`:

1. `media: verisilicon: Split probe into hardware init and device registration` (no functional change)
2. `media: verisilicon: Pick the hardware core for each job` (no functional change for single-core)
3. `media: verisilicon: Add multi-core support`
4. `media: verisilicon: Don't hold a VPU behind an IOMMU in reset after remove` (fixes an SError panic on module reload; the bug is in stock too)

## Design

- **Per-instance hardware vs. user-facing device.** `hantro_hw_init()` sets up the clocks, resets, registers, IRQs and runtime PM of each instance. `hantro_register_devices()` creates the m2m, video and media devices.
- **Job → core.** `hantro_dev` has a `cores[]` list (its first entry is the device itself) and a per-core `curr_ctx`. `device_run()` picks an idle core under `cores_lock` and stores it in `ctx->core`. The core's IRQ handler and watchdog find their job through `core->curr_ctx`, so `v4l2_m2m_get_curr_priv()` is no longer used. The core is released before `v4l2_m2m_buf_done_and_job_finish()`. The VEPU2 JPEG encoder's run, done and reset paths access `ctx->core`'s registers. Decoders and every other variant always have `ctx->core == ctx->dev`.
- **Multi-core (only variants with `.multi_core = 1`, which is just the new `rk3588_vepu121_variant`).** The first available node with the same compatible is the main core. It is also the component master, so there is no virtual platform device and the bus_info and sysfs paths don't change. It matches the other available nodes as components. Each secondary core runs `hantro_hw_init()` and then `component_add()`.
  - Master bind: binds all cores, then registers the devices. `v4l2_m2m_set_max_parallel_jobs(num_cores)` is set before the video node appears.
  - Master unbind: `v4l2_m2m_suspend()` first (waits for running jobs and stops new ones), then unregisters the devices, then unbinds the cores.
- **IOMMU.** Buffers are allocated through the main core. Each secondary core is attached to the main core's IOMMU domain with `iommu_attach_device()`, like RGA and rkvdec do, and **detached on unbind** so it can bind again. Reloads log no "cannot attach" errors.
  - A core whose IOMMU setup can't share mappings (attach fails, or only one side has an IOMMU) is logged and left unused instead of failing the device.
- **Other variants.** Without `multi_core`, the old behaviour stays: only the first instance probes and the others log "missing multi-core support". The AV1 (vpu981) and G1 (rk3568-vpu) instances use the single path unchanged.
- **One stream still runs one job at a time.** This is an m2m limit, so a single stream is no faster. N streams can use up to N cores.

## Results (Orange Pi 5, 7.3.0-opi5, drop-in modules)

Throughput: 1080p NV12 from a RAM file, `filesrc ! rawvideoparse ! v4l2jpegenc ! fakesink sync=false`, N parallel gst-launch processes, 600 frames per stream. Wall clock includes pipeline start-up.

| Streams | Stock (1 core) fps | Multi-core fps | Speed-up | IRQs per core in the run (fdba0000/4000/8000/c000) |
|---|---|---|---|---|
| 1 | 62.1 | 62.1–65.7 | 1.0x | 600/0/0/0 |
| 2 | 65.1 | 119.6 | 1.8x | 614/586/0/0 |
| 4 | 67.5 | 216.0 | 3.2x | 624/612/583/583 |
| 8 | 67.9 | 223.1 | 3.3x | 1263/1212/1177/1148 |

- **Stock IRQs.** All on fdba0000. The other cores weren't probed and their power domains showed "sync_state() pending".
- **What limits 4–8 streams.** At 8 streams the CPU is about 88% idle. Each core then does about 56 fps (~66 fps alone), so the limit looks like memory bandwidth or the hardware, not scheduling. With 4 streams each context waits for userspace between jobs, which explains the gap to 8 streams.
- **An earlier "91 fps" single-stream stock figure** came from a 2×100-frame run and didn't reproduce. 600-frame runs give 62 fps on both drivers.

Correctness and regression checks:

| Test | Stock | Multi-core |
|---|---|---|
| dmesg | 1 encoder, 3× "missing multi-core support", PD sync_state pending | "bound fdba4000/8000/c000 … using 4 cores", single `/dev/video4` (rockchip,rk3588-vepu121-enc), one `v4l2jpegenc` element, no sync_state warnings |
| md5, 1080p NV12 (60 frames) | 397c7d90… | identical |
| md5, 1080p I420 (30 frames) | c0e9da1d… | identical |
| md5, 1080p YUY2 (30 frames) | b5cfaf41… | identical |
| md5, 4K NV12 (10 frames) | e4f3cc0b… | identical |
| 4 and 8 parallel encodes of the NV12 input (every core used) | – | all 4/8 outputs = 397c7d90… |
| v4l2-compliance /dev/video4 | 48/49 (colorspace fail) | 48/49 (same colorspace fail) |
| G1 VP8 decode (v4l2slvp8dec, 640x480, 60 frames) | 4fcf4a8f… (= ffmpeg SW) | identical, 60 IRQs on fdb50000 |
| AV1 decode (v4l2slav1dec, 640x480, 30 frames) | 36c586cc… | identical, 31 IRQs on fdc70000 |
| `modprobe -r` / `modprobe`, twice, 1 s gap | **kernel panic** (see below; seen with the 3-commit build, and the cause is in stock too) | clean with commit 4: all cores rebind, no IOMMU attach errors, no warnings. Encode parity, decoders and compliance re-checked after the reload |

## The reload panic (fixed by commit 4)

With the 3-commit build, `modprobe -r hantro_vpu && modprobe hantro_vpu` panicked:

```
SError Interrupt … Workqueue: pm pm_runtime_work
clk_disable ← clk_bulk_disable ← vsi_iommu_suspend [vsi_iommu] ← genpd_runtime_suspend ← pm_runtime_work
```

- **Cause.** Unbinding runtime-resumes the AV1 device and, through the `DL_FLAG_PM_RUNTIME` link, its vsi IOMMU. `hantro_remove()` then asserts the AV1 resets, which include `SRST_A_AV1_BIU`/`SRST_P_AV1_BIU`, the bus interface of the IOMMU at fdca0000. When the IOMMU autosuspends 100 ms later, `vsi_iommu_disable()` writes to registers that are held in reset, which gives an asynchronous SError.
- **Why stock usually survives.** The bug is in stock too. It only escapes when the AV1 instance is re-probed (and the reset deasserted) within that 100 ms. The longer multi-core teardown and probe pushed it past the window.
- **Fix.** Don't assert the resets on remove (or in the probe error path) for a VPU behind an IOMMU. VPUs without an IOMMU (imx8m, sunxi, stm32, sama5d4) are still put into reset.
- **Verified.** Two reloads with a 1 s gap, which is well past the window, were clean.

## Build

- Built against `~/orangepi5/build/linux` config/symvers as drop-in modules (`kernelrelease` = 7.3.0-opi5) and signed. A clean rebuild of `drivers/media/platform/verisilicon` with `W=1` gives no warnings.
- sparse isn't installed on the host, so it wasn't run.
- `checkpatch.pl --strict` on all 4 patches: clean apart from the expected missing Signed-off-by.
- `hantro_v4l2.c` is not touched, to avoid conflicts with the format-validation branch.

## Board state at the end

- `/lib/modules/7.3.0-opi5/updates/opi5-multicore/hantro-vpu.ko` is the 4-commit build (md5 2a07dde0…, srcversion BB44A39283BE9F206E75E3B). It is loaded, all VPUs are healthy, and dmesg shows no faults.
- After the coordinator's IEP2 DTB reboot (12:37) it came up cleanly again with 4 cores. The encoder is now `/dev/video5` and AV1 `/dev/video6`, because the IEP node shifted the numbering.
- The previous (stock) module is in `/var/tmp/hantro-vpu.ko.prev` (md5 68f6d365…).
- Test scripts are in `/var/tmp/hmcs/` (copies in `scripts/` here).

## Known issues and risks

- **No partial device.** If a secondary core fails to probe (for example its power domain), the component aggregate never binds and there is no encoder node at all, where stock would still offer one core. RGA and rkvdec behave the same way. An IOMMU attach failure only leaves that core unused.
- **Encoder faults still wedge a core.** A wedged core (IOMMU page fault / stall timeout, e.g. from the known 96x32 CAPTURE-format reproducer) now takes 1 of 4 job slots. Every job scheduled on that core will time out. There is still no IOMMU or core recovery path. That is the sibling format-validation work; this series doesn't change it.
- **Pre-existing lifetime hazard.** Unbinding through sysfs while file handles are open is still unsafe (the m2m device is freed under open contexts). Master unbind now suspends the m2m queue first, so no job runs on a core that is being unbound.
- **H1 JPEG encoder.** `hantro_h1_jpeg_enc.c` (rk3288 etc.) still uses `ctx->dev` for register access. That's correct because it is single-core, but it would need `ctx->core` if an H1 variant were ever marked `multi_core`.
- **Untested.** Other SoCs (imx8m with its G1/G2 `shared_devices`, sunxi, stm32, sama5d4) were not tested on hardware. Their path is unchanged apart from the `curr_ctx` and core bookkeeping, and the skipped reset assert on remove only applies to IOMMU-backed devices.
- **Harness note.** systemd-logind (RemoveIPC) clears `/dev/shm` when the SSH session ends, so the RAM input is regenerated on each run.
