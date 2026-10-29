# On-board test: GPU SCMI/PVTPLL clock (1 GHz) and NPU DVFS

Branch `opi5/gpu-npu-7.3` (worktree `~/orangepi5/work/gpu-npu-7.3`). These changes need a **full kernel
Image plus modules plus DTB**: the devfreq core fix is built-in (`CONFIG_PM_DEVFREQ=y`), panthor and rocket are modules,
and the DT changes the GPU clocks. **No firmware change is needed.** Mainline TF-A v2.15, already on the board,
implements `SCMI_CLK_GPU` and `SCMI_CLK_NPU` with the PVTPLL (rates 200 MHz on GPLL, 300 to 1000 MHz in 100 MHz steps on the PVTPLL).

Commits under test (`git log --oneline 5e33b74b0..`):
- NPU (Igor Paunovic, "accel/rocket: DVFS for the RK3588 NPU" v2, 9 of 11; v2 1/11 and 3/11 are already in v7.3):
  core numbering, stable slots, **clocks requested by name** (a v7.3 bug: all four `clk_bulk` entries resolve to `aclk`, so the
  SCMI `npu` clock and hclk/pclk are never enabled by the driver), NPU OPP table, boot-rate restore, devfreq,
  cooling device, passive trip.
- GPU: binding "bus" clock, panthor bus clk, panthor "no rate change while suspended", DT switch of the GPU core clock
  to `SCMI_CLK_GPU` plus a 200 MHz `opp-suspend` OPP, and the devfreq core fix "resume at the frequency from before suspend".

## Risks (read before booting)
- **SError/panic risk** if the GPU power domain goes up or down while the GPU runs from the PVTPLL, or if an
  SCMI GPU rate is set with PD_GPU off. Mitigations: the 200 MHz opp-suspend OPP (GPLL path) is applied before each
  runtime suspend, and the panthor guard skips rate changes while the device is suspending or suspended. Test the sysfs path
  explicitly (step 4). The board auto-reboots on panic.
- NPU: the same constraint applies to the NPU islands. The rocket series keeps all cores resumed above the boot rate.

## Steps
1. Boot. Check `dmesg | grep -iE 'panthor|rocket|scmi|devfreq'`:
   - `panthor fb000000.gpu: [drm] clock rate = 200000000` (previously 198000000 from the CRU),
     no clk or opp errors, `Initialized panthor`.
   - rocket: three cores probe, and there are no "failed to set the OPP clock and supply" or "no NPU supply described" messages.
   - `ls /sys/class/devfreq/` shows `fb000000.gpu` and the NPU devfreq (on fdab0000.npu).
   - `cat /sys/class/devfreq/fb000000.gpu/available_frequencies` starts at 200000000.
2. Check that the GPU is idle: `cur_freq` = 200000000, `/sys/devices/platform/fb000000.gpu/power/runtime_status` = suspended.
   The CRU witness `sudo busybox devmem 0xfd7c0578 32` (CRU_CLKSEL_CON158) should have bit 14 = 0 (normal PLL path) when idle.
   **Do not read the GPU GRF registers (PVTPLL status) with devmem: with PD_GPU off that access SErrors.**
3. Run the load and compare with the baseline (850 MHz cap, 7.3.0-opi5 #2):
   ```sh
   ~/gpunpu/mon.sh /tmp/mon.log & M=$!
   timeout 120 vkmark --winsys headless -D <uuid from vkmark -L> -b cube -b effect2d:kernel=blur -b shading:shading=phong
   # with weston headless (see RESULTS.md):
   WAYLAND_DISPLAY=wl-bench timeout 60 glmark2-es2-wayland --off-screen -b terrain -b refract
   kill $M
   ```
   Pass: `cur_freq` under load = 1000000000 (or the PVTPLL-measured value near it; scmi get_rate reports the measured
   PVTPLL rate), CLKSEL_CON158 bit 14 = 1 during load, terrain > 111 fps (expected about 125 to 130, scaling with 1000/850), no
   panthor faults. After load: back to 200 MHz and `suspended` within about 1 s.
4. **sysfs while suspended** (this panicked in Jonas Karlman's RFC without a guard). With the GPU idle and suspended:
   ```sh
   echo 1000000000 | sudo tee /sys/class/devfreq/fb000000.gpu/min_freq   # must not panic
   cat /sys/class/devfreq/fb000000.gpu/cur_freq                            # still 200 MHz while suspended
   WAYLAND_DISPLAY=wl-bench timeout 20 glmark2-es2-wayland --off-screen -b build   # runs at 1 GHz
   echo 0 | sudo tee /sys/class/devfreq/fb000000.gpu/min_freq                       # restores the default
   ```
   Repeat with `max_freq` 300000000 and 0. Pass: no SError/panic, rates follow the limits.
5. Suspend/resume stress: run 200 cycles of a short GPU job (`timeout 2 vkmark --winsys headless -b clear` or `eglinfo -B -p surfaceless`) with
   sleep 0.2 s in between, so each cycle runtime-suspends. Pass: no panthor timeout or fault, and `trans_stat` shows
   200 MHz <-> top OPP transitions. With the devfreq fix, `trans_stat` also shows a direct 200 -> previous OPP
   jump on resume, rather than 200 MHz followed by a later governor ramp.
6. Thermal: about 3 minutes of vkmark at 1 GHz. Watch `gpu-thermal`: the passive trip is at 85 °C, and the devfreq cooling device
   should cap the frequency if it is reached.
7. NPU: run `~/npu/scripts/classify.py` with and without `--delegate /usr/lib/teflon/libteflon.so` and record the time per inference
   under each OPP. NPU devfreq `cur_freq` and the scmi_clk_npu rate should go up under load and return to 200 MHz after it.
   Pass: outputs identical to the 200 MHz run (bit-exact), and roughly 2.5x the throughput at 1 GHz (Igor's OPi5 Plus data).

## Rollback
Boot the previous image (7.3.0-opi5 #2). Nothing on disk or in firmware changes.
