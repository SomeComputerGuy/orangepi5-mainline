# GPU (panthor) and NPU (rocket) validation: Orange Pi 5, 7.3.0-opi5, Ubuntu 26.10

Baseline: stock 7.3.0-opi5. **Fixed kernel: `#2 SMP PREEMPT_DYNAMIC Thu Oct 29 17:38:27 UTC 2026` (full deb with patches 0501-0514 + combined DTB), validated 18:40-18:55 — see "Results on the fixed kernel".**

## Versions
| Component | Version |
|---|---|
| Kernel | 7.3.0-opi5 #2 (Oct 29 10:16 UTC build) |
| Mesa | 26.2.4-1ubuntu1 (panfrost GL/GLES, panvk Vulkan, libteflon in `mesa-teflon-delegate`) |
| Vulkan loader | 1.4.357 |
| CSF firmware | `arm/mali/arch10.8/mali_csffw.bin.zst`, git sha 95a25d71, interface v1.5.0 |
| TF-A | mainline v2.15 (provides SCMI clocks, including `scmi_clk_gpu`/`scmi_clk_npu` PVTPLL) |
| glmark2 | 2023.01+dfsg-3 (es2-wayland); vkmark 2025.01 |

## GPU (Mali-G610 MC4, panthor 1.9.0)

### Functional
- `vulkaninfo --summary`: `Mali-G610 MC4`, driver panvk, Vulkan 1.4.354, conformanceVersion 1.4.1.2.
- `eglinfo -B` (surfaceless and gbm): OpenGL ES 3.1 and desktop GL 3.1 on `Mali-G610 MC4 (Panfrost)`.
- dmesg clean during and after every run: no panthor fault, timeout, MMU fault or reset.
  (I accidentally ran `dmesg -c` once at the start of the session, before any workload. That cleared
  the kernel ring buffer on the shared board. Later checks use uptime timestamps instead.)

### Benchmarks (headless, no HDMI monitor)
- `glmark2-es2-drm --off-screen` **does not work** without a connected connector ("Failed to find a
  suitable connector"). glmark2 2023.01 has no surfaceless flavour. Workaround: run Weston headless with the GL
  renderer on panfrost, then `glmark2-es2-wayland --off-screen` against it:
  ```sh
  export XDG_RUNTIME_DIR=$(mktemp -d); weston --backend=headless --renderer=gl --socket=wl-bench --idle-time=0 --no-config &
  WAYLAND_DISPLAY=wl-bench timeout 360 glmark2-es2-wayland --off-screen
  ```
- **glmark2 (ES2, 800x600 off-screen) score: 1717.** Selected scenes: terrain 111 fps, refract 262, jellyfish 1450,
  desktop blur 601, shadow 1275, build vbo 2573. The terrain number matches the 112 fps that other users report on mainline RK3588 with the
  850 MHz cap (see below).
- **vkmark 2025.01 (`--winsys headless`, 800x600) score: 4146**. Range: effect2d blur 1617 fps, cube 6153 fps.
  vkmark's `-D` takes its own UUID format (`vkmark -L`), not the vulkaninfo deviceUUID.

### devfreq, thermal, runtime PM
- Governor simple_ondemand. Idle: 300 MHz OPP and runtime-suspended. Under load it moves straight to the top OPP and
  drops back when the load stops. Within about 1 s after the load the GPU is `suspended` again.
- **Bug/limitation: the top OPPs are unreachable with the CRU clock.** `cur_freq` (= `clk_get_rate`) shows:

  | OPP requested | actual clk_gpu | parent |
  |---|---|---|
  | 300 MHz | 300 | cpll/5 |
  | 400 MHz | 396 | gpll/3 |
  | 500 MHz | 500 | cpll/3 |
  | 600, 700 MHz | 594 | gpll/2 |
  | 800 MHz | 786.4 | aupll/1 (the audio PLL) |
  | 900, 1000 MHz | **850** | npll/1 |

  (Observed values: 300/500/594/786.4/850 MHz in the monitor log during glmark2. The 400 MHz value comes from the clk tree.)
  `clk_gpu_src` is an integer divider on gpll 1188 / cpll 1500 / aupll 786.432 / npll 850 / spll 702 MHz, so
  under load the GPU runs at 850 MHz while the regulator is set to the 1 GHz voltage (850 mV). That is safe, but it costs
  about 15% of peak performance and wastes some power. The 800 MHz OPP also depends on the audio PLL, which can be
  re-rated for 44.1 kHz audio. This is a known mainline RK3588 issue (Radxa forum thread "16% more GPU performance for Panthor").
  **Fix (implemented, not yet booted — see "Fixes" below):** switch the panthor core clock to the TF-A
  SCMI GPU clock (PVTPLL), which reaches every OPP exactly.
- Thermal: during the full glmark2 run, gpu-thermal peaked at 68 °C. During vkmark (about 2 min, 850 MHz): 75 °C. The passive trip is at 85 °C,
  so no throttling happened. The GPU devfreq is registered as cooling device `devfreq-fb000000.gpu`.

## NPU (rocket, 3 cores)

### Baseline inference (7.3.0-opi5 #2 built 16:45, NPU at 200 MHz, vdd_npu 800 mV)
Teflon comes from Ubuntu's `mesa-teflon-delegate` 26.2.4 (`/usr/lib/teflon/libteflon.so`, which includes rocket). The runtime is
ai-edge-litert 2.3.0 (cp314) in `~/npu-venv`, installed offline from wheels. Models: Coral `mobilenet_v{1,2}_1.0_224_quant.tflite` (uint8).
Images: grace_hopper.bmp, cat.bmp, parrot.jpg. 30 timed `invoke()` per image (`scripts/classify.py`), CPU = XNNPACK.

| Model | CPU 4 threads | CPU 1 thread | NPU (Teflon) | Top-1 agree | Top-5 overlap | max abs diff (uint8 output) |
|---|---|---|---|---|---|---|
| MobileNet v1 | 19.6 ms | 72.7 ms | **15.6 ms** (min 12.6) | 3/3 | 4/5, 5/5, 5/5 | 5 |
| MobileNet v2 | 12.2 ms | 42.7 ms | 19.8 to 21.7 ms (min 16.3) | 3/3 | 5/5, 3/5, 5/5 | 3 |

- Delegation (`TEFLON_DEBUG=verbose`): v1 15 CONV + 13 DWCONV on the NPU. v2 36 CONV + 17 DWCONV + 10 ADD on the NPU. AVGPOOL,
  RESHAPE and SOFTMAX stay on the CPU (one CPU tail per model). Top-1 classes are correct (military uniform, Egyptian cat, macaw)
  and match the CPU on every image. The top-5 differences are only in classes with scores of 1 to 9 out of 255.
- At 200 MHz the NPU is 4.7x / 3.5x faster than a single CPU core, but only on par with or slower than 4 A76/A55 threads. v2 is slower than the CPU
  because its 10 ADD ops and smaller layers make per-job overhead dominate. The NPU runs at 1/5 of its rated clock (see below).
  Igor's DVFS series reports 2.55x at 1 GHz.
- Runtime PM: during inference cores 0 and 1 are active and core 2 stays suspended (Teflon used two cores for a single
  stream). Within about 2 s afterwards all three cores are suspended again. dmesg is clean: no rocket, IOMMU or NPU messages during the runs.
- vdd_npu_s0 stays at 800 mV (always-on, no consumer scaling it). scmi_clk_npu stays at 200 MHz. There is no NPU devfreq device.

Static findings (from DT, clk_summary and driver source):
- All three cores probe (version 1179210309), each has its own IOMMU group (10/11/12), power domains npu/nputop/npu1/npu2 are
  `off-0` with all cores runtime-suspended when idle. vdd_npu_s0 (RK8602 @ i2c2 0x42) is enabled at 800 mV,
  always-on.
- **No NPU DVFS: the NPU is pinned to 200 MHz** by `assigned-clock-rates` on `SCMI_CLK_NPU` (vendor max: 1 GHz).
- **v7.3 rocket bug:** `rocket_core_init()` calls `devm_clk_bulk_get()` on four `clk_bulk_data` entries without
  setting `.id`, so all four resolve to the first DT clock (`aclk`). clk_summary confirms this: aclk_npu0 has 4 consumers from
  fdab0000.npu, and scmi_clk_npu has an enable count of 0. The "npu", hclk and pclk clocks are never enabled by the driver.
  Fixed by Igor Paunovic's series (below).

## Fixes (branch `opi5/gpu-npu-7.3`, worktree `~/orangepi5/work/gpu-npu-7.3`)
`git log --oneline 5e33b74b0..`:
```
7bbd66417 PM / devfreq: Resume at the frequency from before suspend
40d5ed1e2 arm64: dts: rockchip: rk3588: Use SCMI GPU clock as the GPU core clock
93036a6d4 drm/panthor: Do not change the GPU clock rate while suspended
8f0ccb114 drm/panthor: Add support for a bus clk
ea1dab3bc dt-bindings: gpu: mali-valhall-csf: Add bus clock for RK3588
ffbda1e6e arm64: dts: rockchip: rk3588: add passive cooling to the NPU thermal zone
cfbe50107 accel/rocket: register a devfreq cooling device
845983141 accel/rocket: add devfreq support
31d43740c accel/rocket: restore the NPU clock boot rate before powering the cores down
85a4d828f arm64: dts: rockchip: rk3588: add an OPP table for the NPU
009e9b209 dt-bindings: npu: rockchip: allow DVFS and thermal properties
e201b780c accel/rocket: request the core clocks by name
fec03d1b1 accel/rocket: keep core slots stable across unbind and rebind
a156130a0 accel/rocket: number the cores by devicetree position, not bind order
```
### GPU 850 MHz cap — root cause and layer
- The panthor "core" clock in `rk3588-base.dtsi` is the CRU `CLK_GPU` (`clk_gpu_src`: mux gpll/cpll/aupll/npll/spll + 5-bit
  divider, `clk-rk3588.c`). The board's boot-time PLL rates cannot produce 700, 800 (except via the audio PLL), 900 or 1000 MHz. Every
  OPP in `rk3588-opp.dtsi` above 500 MHz expects a rate that this clock tree cannot make. The DT already sets
  `assigned-clocks = <&scmi_clk SCMI_CLK_GPU>` at 200 MHz, but only to put the firmware mux on its normal-PLL path.
- Mainline TF-A v2.15 (`plat/rockchip/rk3588/drivers/scmi/rk3588_clk.c`, on the board already) implements
  `SCMI_CLK_GPU` with the GPU PVTPLL: 200 MHz on GPLL, and 300 to 1000 MHz in 100 MHz steps on the PVTPLL (exact-match table, the same rates
  as the OPP table). `get_rate` reports the measured PVTPLL rate. **No firmware change is needed.**
- Fix layer: **DT + panthor driver + devfreq core** (kernel only). Based on Jonas Karlman's RFC (not posted to lore,
  carried in Armbian PR armbian/linux-rockchip#380, glmark2 terrain 139 -> 152 fps on ROCK 5B). Mainline up to the 7.4 merge window
  (`opi5/base`) and linux-next still use the CRU clock.
  1. binding: allow a 4th clock "bus" on rockchip,rk3588-mali.
  2. panthor: optional "bus" clock (the CRU gate `CLK_GPU`), enabled before and disabled after "core".
  3. panthor: do not apply rate changes while suspending/suspended (only the suspend OPP in the suspend path). The
     RFC's runtime-PM-status check left a window (still RPM_SUSPENDING after devfreq suspend). The devfreq suspend
     count cannot be used either, because panthor's first resume leaves it unbalanced at -1/0. Without such a guard, a sysfs
     `min_freq` write while the GPU is suspended SErrors: TF-A touches the GPU GRF in the powered-off PD_GPU.
  4. DT: `clocks = <&scmi_clk SCMI_CLK_GPU>, coregroup, stacks, <&cru CLK_GPU>` with names core/coregroup/stacks/bus, plus a
     200 MHz `opp-suspend` OPP (rk3588 675 mV, rk3588j 750 mV). This ensures PD_GPU only goes up or down while the GPU runs from GPLL,
     because the PVTPLL is inside the GPU power domain.
  5. devfreq core: since 62453f1ba5d5 the suspend transition overwrites `resume_freq` with the suspend frequency, so each
     runtime resume would start at 200 MHz. Fixed to restore the pre-suspend OPP.
- Needs a **full kernel Image** (devfreq core is built-in) + panthor.ko + rocket.ko + DTB. Staged in
  `~/orangepi5/work/_out/gpu-npu/test-kernel/` (release `7.3.0-opi5`, same signing key as the running image, so stock
  modules still load). Test plan: `TESTING.md`.

### NPU DVFS (Igor Paunovic, "accel/rocket: DVFS for the RK3588 NPU" v2, 2026-09-22,
https://lore.kernel.org/r/20260922080114.44662-1-royalnet026@gmail.com)
- 9 of 11 patches applied with b4/git am (v2 1/11 and 3/11 are already in v7.3). Fixes the clock-by-name bug, adds the NPU OPP
  table (200 to 1000 MHz, 700 to 850 mV, opp-shared), devfreq (simple_ondemand), cooling and an 85 °C passive trip. The author reports 2.55x
  MobileNetV1 throughput on an Orange Pi 5 Plus (91 -> 233 inf/s). Status: on the list, reviewed and tested by others, not yet merged.

### Build status
panthor.ko and rocket.ko build W=1 clean (out of tree, MO=), `drivers/devfreq/devfreq.o` builds clean, and the full Image builds (only
pre-existing frame-size warnings elsewhere). `CHECK_DTBS=y` is clean for rk3588s-orangepi-5, rk3588s-orangepi-5b, rk3588-rock-5b and
rk3588-edgeble-neu6b-io (rk3588j). `dt_binding_check` is clean for arm,mali-valhall-csf.yaml and rockchip,rk3588-rknn-core.yaml.
checkpatch --strict reports only "unknown commit id" warnings (shallow clone) and a MAINTAINERS note for the new rocket_devfreq.c.

## Results on the fixed kernel (TESTING.md, 2026-10-29 18:40-18:55, exclusive board slot)
Logs: `logs/new-kernel/`.

| Step | Result |
|---|---|
| 1 Boot | `panthor: clock rate = 200000000`, scmi_clk_gpu consumer = panthor "core", CRU `clk_gpu` consumer = "bus". GPU devfreq 200-1000 MHz, new **NPU devfreq `fdab0000.npu` 200-1000 MHz**, scmi_clk_npu consumer = "npu" (clock-name bug fixed). No errors. |
| 2 Idle | GPU suspended at 200 MHz, CRU_CLKSEL_CON158 = 0x1f05 (GPLL/6, PVTPLL bit 14 = 0) |
| 3 GPU load | **cur_freq 995-1024 MHz** (the PVTPLL rate as measured by TF-A), CON158 = 0x5f05 (PVTPLL) for the whole run. **vkmark 4146 -> 4425 (+6.7 %)**, glmark2 terrain 111 -> 118 fps, refract 262 -> 274, jellyfish 1450 -> 1519, desktop-blur 601 -> 627. Back to 200 MHz/suspended within about 1 s. |
| 4 sysfs while suspended | `min_freq=1000000000` written while suspended: **no SError**. cur_freq stays 200 MHz until the next job, which then runs at 1017-1024 MHz. `max_freq=300000000`: job runs at 310-312 MHz. Restored to 0. dmesg clean. **The guard works.** |
| 5 Suspend/resume x200 | 200 short glmark2 jobs, 0 failures, 119 s, GPU runtime-suspended between jobs. trans_stat: 200 MHz -> {300..1000} transitions grew by about 200, so resume goes straight to the remembered OPP (the devfreq resume_freq fix). No faults. |
| 6 Thermal, 3 min sustained | gpu-thermal 50 -> **85 °C** peak. The devfreq cooling device throttles to the 900 MHz OPP (about 920 MHz measured), sometimes 800 (about 830), at 83-85 °C. Stable, no faults. At 1 GHz the board reaches the passive trip after about 2 min of full load, which it did not reach at 850 MHz (75 °C). |
| 7 NPU DVFS | see the table below. Bit-exact outputs between 200 MHz, governor and 1 GHz. vdd_npu now scaled (700 mV at idle, was a fixed 800 mV). CON74 bit 0 = 1 (PVTPLL) at 1 GHz, 0 at idle. All cores suspended afterwards. |

NPU (Teflon) latency per inference, mean of 30, 3 images (ms):

| Model | NPU pinned 200 MHz | NPU simple_ondemand | NPU pinned 1 GHz | CPU 4 threads | CPU 1 thread |
|---|---|---|---|---|---|
| MobileNet v1 | 16.6 | 8.8 | **8.8** (1.9x vs 200 MHz) | 19.6 | 72.7 |
| MobileNet v2 | 19.6 | 11.5 | **11.2** (1.75x) | 12.2 | 42.7 |

The speed-up is below Igor's 2.55x (inf/s with a C harness) because each `invoke()` here also includes the CPU-side
AVGPOOL/RESHAPE/SOFTMAX tail and Python/LiteRT overhead. Top-1 matches the CPU on 6/6 image-model pairs.

dmesg for the whole session: no panthor, rocket or IOMMU faults, timeouts or SErrors.

### PVTPLL observation
At the 1000/900/800 MHz OPPs TF-A reports a measured PVTPLL rate of about 1010-1024 / 920 / 830 MHz, roughly 2 % above nominal at
the OPP voltages (850/800/750 mV). This is the expected behaviour of a ring-oscillator PLL on this chip (it tracks silicon speed at
the given voltage). It is stable under load and thermal throttling.

## Open items / next steps
1. Upstream: Jonas Karlman's RFC is not on lore. Draft a series (binding + panthor bus clk + panthor suspended guard + DT +
   devfreq resume_freq fix), coordinated with him (Suggested-by/authorship kept). The devfreq fix should go to the
   devfreq maintainers separately, with `Fixes: 62453f1ba5d5` (verify the hash on a full clone; ours is shallow).
   Report the Orange Pi 5 test results to Igor Paunovic's NPU DVFS v2 thread only if the user decides to; nothing has been sent.
2. Thermal: the GPU now reaches the 85 °C passive trip in about 2 min of sustained full load on a bare board. This is acceptable (it throttles
   cleanly), but a heatsink/fan is recommended for sustained GPU work.
3. glmark2-es2-drm cannot run headless on this setup (no connector). Use weston headless + glmark2-es2-wayland.
