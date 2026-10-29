# VP9 decode performance on RK3588 rkvdec (VDPU381), Orange Pi 5

Branch `opi5/vp9-perf-7.3` (worktree `work/vp9-perf-7.3`):

```
192ef8eb0 media: rkvdec: vdpu381-vp9: keep the count table cacheable      <- this work
9cb9c761e media: rkvdec: vdpu381-vp9: fix segmentation map handling       <- vp9-conf (fast-forwarded)
313bd442e media: rkvdec: vdpu381-vp9: reset the register set for every frame  <- vp9-conf
afe2d3426 media: rkvdec: vdpu381-vp9: allow frames smaller than the CAPTURE format
```

Patch: `patches/0001-media-rkvdec-vdpu381-vp9-keep-the-count-table-cachea.patch` (checkpatch --strict
clean apart from the intentionally missing Signed-off-by). Module:
`~/orangepi5/build/wt-vp9-perf-7.3/final/rockchip-vdec.ko` (only rockchip-vdec.ko changes; v4l2-vp9.ko
untouched, so no exported-symbol CRC change).

## TL;DR

1. **The reported numbers (63/52 fps at 4K) were mostly GStreamer, not the kernel.** `fakesink` does not
   advertise `GstVideoMeta` in the allocation query. The rkvdec CAPTURE layout has 64-aligned luma
   height (2176 for 2160p, 1088 for 1080p), so it differs from the default GstVideoInfo layout and
   `v4l2slvp9dec` falls back to a CPU copy of every frame:
   `gst_v4l2_codec_vp9_dec_decide_allocation: GstVideoMeta support required, copying frames.`
   That copy is synchronous in the decoder's streaming thread (VP9 has no output delay in
   v4l2codecs), so the hardware sat idle ~4.7 ms of every 11 ms frame (53% busy). With a sink that
   supports video meta (`fakevideosink`, kmssink, waylandsink, glimagesink) the same kernel does
   148 fps (4K 8-bit) / 124 fps (4K 10-bit), on par with 4K HEVC (140 fps) on the same core.
2. After that, the decoder **hardware** sets the limit: 5.8 ms (4K 8-bit), 7.0-7.4 ms (4K 10-bit)
   and 7.8 ms (4K 10-bit at ~58 Mbit/s) per frame. That is 89-92% busy before the fix and
   94-96% after it.
3. Kernel-side bottleneck: the CPU backward probability adaptation in `rkvdec_vp9_done()` read the
   **uncached** (`dma_alloc_coherent`) count table one u32 at a time. That took ~430 us per frame
   on CPU0 (Cortex-A55: rkvdec IRQs default to CPU0) and held up the next frame. Fixed by making
   the table cacheable with explicit syncs: done path 437 -> 81 us, +5% fps at 4K and +18% at
   1080p, output bit-identical.
4. 2 streams scale ~1.85-1.9x and both cores get the same number of frames (600/600). The
   "uneven IRQ counts" were an artefact of single-stream runs: `acquire_core()` is LIFO, so a lone
   stream always reuses the core it just released. With 2 streams both cores stay busy. The
   1.6x reported for 2 streams came from the GStreamer copy (CPU/memory-bound), not from the
   scheduler.

Goal "VP9 4K60 10-bit with headroom": met. One 4K 10-bit stream decodes at 130 fps, two at 238 fps
total (119 each). A ~58 Mbit/s 10-bit 4K clip runs at 113 fps (1 stream) / 206 fps (2 streams).

## Numbers

Decode-only, `gst-launch-1.0 filesrc ! matroskademux ! vp9parse ! v4l2slvp9dec ! <sink> sync=false`,
wall clock including pipeline start-up (~0.1-0.2 s, so it slightly understates steady-state fps).
Board otherwise idle unless noted. Clips: libvpx-vp9 realtime, testsrc2 (`scripts/gen.sh`).
4k8 = 3840x2160 8-bit P0 20 Mbit/s, 600 frames. 4k10 = same, 10-bit P2. 4k10hb = mandelbrot+noise
10-bit, ~58 Mbit/s, 300 frames. 1080p = 8-bit 8 Mbit/s, 1200 frames.

| clip / streams | fakesink (as reported) | fakevideosink, before | fakevideosink, after (192ef8eb0) |
|---|---|---|---|
| 4K 8-bit x1 | 84 | 148 | **156** |
| 4K 8-bit x2 (total) | 143 | 276 | **286** |
| 4K 10-bit x1 | 69 | 124 | **130** |
| 4K 10-bit x2 (total) | - | 225 | **238** |
| 4K 10-bit 58 Mbit/s x1 | - | 109 | **113** |
| 4K 10-bit 58 Mbit/s x2 | - | 198 | **206** |
| 1080p x1 | 276 | 455 | **538** |
| 1080p x2 | - | 796 | - |
| HEVC 4K 8-bit x1 / x2 (reference) | - | 140 / 267 | 140 |
| H.264 4K 8-bit x1 / x2 (reference) | - | 85 / 167 | - |

"before" = base2.txt (module of the day) and E0/E4 in exp1.txt (debug module with the toggles off,
same numbers). "after" = E1/E2 in exp1.txt (debug module with the cached count table; the final
commit is the same code with the toggle removed). For reference only: also moving the rkvdec IRQs
to the A76 cores (`/proc/irq/N/smp_affinity_list` = 4-7, a userspace setting) gives 160 / 291 /
132 / 241 / 565 fps for the same rows.

## Per-frame time breakdown (ftrace function_graph + irq events + kprobes)

Single 4K 8-bit stream, fakevideosink, mean per frame (`traces/t3_E0_4k8_x1.txt` vs
`traces/t3_E1_4k8_x1.txt`):

| step | before | after |
|---|---|---|
| hardware (DEC_E write -> IRQ) | 5787 us | 5758 us |
| hard IRQ -> threaded handler starts (CPU0, A55) | 69 us | 71 us |
| `rkvdec_irq_handler` total | 467 us | 111 us |
| - `rkvdec_vp9_done`: `v4l2_vp9_adapt_coef_probs` | 360 us | 54 us |
| - `rkvdec_vp9_done`: `v4l2_vp9_adapt_noncoef_probs` | 66 us | 14 us |
| - `v4l2_m2m_buf_done_and_job_finish` | ~16 us | ~16 us |
| handler end -> next DEC_E (kworker `v4l2_m2m_try_run` + `rkvdec_device_run`) | 161 us | 162 us |
| - of which `rkvdec_device_run` (ctrl setup, fw_update_probs, init_probs, regs) | 136 us | 144 us |
| **frame period** | **6484 us** | **6102 us** |
| hardware busy | 89% | 95% |

Userspace wait: none with fakevideosink. The next request is always queued before the current frame
finishes, and the next frame is started from the m2m kworker (595-599 of 600 frames). With
fakesink the next frame was queued only after the copy finished. Then the core sat idle 4.7 ms
per frame (`traces/t0_4k8_1_fakesink.txt`: hardware 53% busy, all frames started from the demuxer
thread).

Register writes (`rkvdec_memcpy_toio`, 4 calls) take 2 us per frame in total: negligible.
`v4l2_vp9_fw_update_probs` takes 18 us and `v4l2_ctrl_request_setup` 25 us (on the A55).

2 streams, 4K 10-bit (`traces/t3_E0_4k10_x2.txt` vs `t3_E1_4k10_x2.txt`): 600 frames per core.
Hardware busy went from 89-90% to 94% on both cores. Before, both IRQ threads were on CPU0 and
queued behind each other's 450 us adaptation (p90 IRQ -> handler latency 327 us). After, that
latency is 55 us mean / 79 us p90.

## Hypotheses checked

- **Probability init/copy (`init_probs`)**: inlined in `rkvdec_vp9_run`, which takes 130 us in
  total on the A55 (33 us on an A76) including the uncached 4.8 KB writes. That's ~2% of the
  frame time, so left alone.
- **Count readback + backward adaptation on the CPU**: confirmed as the kernel-side bottleneck,
  caused by uncached reads. **Fixed.** The adaptation does serialise frames within a stream
  (every frame depends on the previous one's adapted context, and m2m runs one job per context
  anyway). What matters is how long it takes, and that's now 70 us.
- **Cache maintenance of large buffers**: the CAPTURE/OUTPUT vb2 buffers are dma-contig through
  the IOMMU, so the CPU never touches them in decode-only use. The 1 MB `priv_tbl` (probs +
  segmaps) is written only for the 4.8 KB probability part.
- **Register writes via memcpy_toio**: 2 us per frame. Not an issue.
- **Hardware time**: dominant (89-96%). The decoder's internal caches are already enabled at
  reset: the debug module dumped the "cache" region registers as cache0/1 cfg = 0x13 and
  cache2 = 0x17 (cacheable access + read allocate + 64-byte lines). Writing the BSP values
  (`mpp_rkvdec2.c`) plus a clear before each frame made no measurable difference, so no patch.
  Clocks match the BSP: aclk 786 MHz, core/ca 594 MHz, hevc_ca 1 GHz.
- **GStreamer pipelining**: with video meta, v4l2slvp9dec keeps the next request queued, so the
  kernel always has work. Without video meta it copies synchronously. See the follow-up below.
- **Multi-core scheduling**: fair with 2 streams (600/600 frames). One context can't run on two
  cores (one m2m job per context, by design of the parallel-jobs patch, and VP9's context
  dependency would forbid it anyway). `acquire_core()` is LIFO, so single-stream runs always land
  on the same core. That's harmless for throughput, but it explains the IRQ-count skew.
- **IRQ affinity**: rkvdec's threaded handler runs where the hard IRQ is routed (CPU0, an A55).
  Moving it to the A76 cores gives another 2-5%. That's system policy (irqbalance or a udev rule
  writing `/proc/irq/*/smp_affinity_list`), not a driver change, so no patch.

## Follow-ups (not done)

- **GStreamer (deferred)**: `sys/v4l2codecs/gstv4l2codecvp9dec.c` (1.28.6) copies every frame when
  downstream lacks GstVideoMeta, and VP9 has no render delay, so the copy runs inline. Options:
  (a) document that decode-only benchmarks must use `fakevideosink` (or any meta-capable sink);
  (b) add output delay / a pending-request queue to the VP9 decoder like h264/h265 have, so the
  copy overlaps with decoding; (c) note it costs ~45% at 4K. HEVC/H.264 copy as well, but their
  render delay hides it.
- **Hardware probability adaptation**: MPP's `hal_vp9d_vdpu34x.c` (`HW_PROB 1`, also used for
  RK3588) lets the decoder do the backward adaptation itself: reg103 `prob_update_en` /
  `refresh_en` / `prob_save_en`, reg162 last-prob base, reg172 update-prob write base, reg160
  delta-prob base, reg028 rd/wr prob idx. That would remove the remaining ~70 us of CPU work and
  the count table entirely. The gain is now ≤1.5%, against a large conformance risk, so not
  pursued.
- The same uncached-count-table pattern exists in the RK3399 backend (`rkvdec-vp9.c`). That fix
  would be the same, but I can't test it here.
- `colmv_compress_en` (reg012), which MPP sets, isn't used by mainline. It might cut memory
  bandwidth (hardware time), but the colmv buffer size and layout would need checking.

## Regression checks

- Output md5 over the per-frame md5s of the raw CAPTURE buffers (`scripts/md5.sh`, checksumsink),
  identical with the cached table on and off. Values in `md5-slot1.txt`:
  4k10hb cea692ef..., 1080p ff798cd6..., 4k8 d23f937e..., 4k10 3ac3c5d1... (2700 frames).
- Fluster VP9 (must be identical per vector to the vp9-conf fix1 result): to be run on the final
  module, since fix1 is its base.

## Files

- `scripts/`: `gen.sh` (clips), `bench.sh`, `baseline.sh`, `experiment.sh`, `trace.sh`
  (function_graph + irq + kprobes on `rkvdec_schedule_watchdog` / `rkvdec_irq_handler` for
  per-core attribution), `parse.py` (per-frame timeline), `md5.sh`.
- `traces/`: raw ftrace output. t0 = day module, t1 = affinity test, t2 = 2-stream baseline,
  t3_E* = debug-module matrix.
- `base2.txt`, `exp1.txt`: benchmark logs. In exp1, E0 = toggles off, E1 = cached counts,
  E2 = + BSP cache registers, E3 = + IRQ affinity 4-7, E4 = BSP cache registers only. The H.264
  lines in exp1 are invalid (the element name changed after a reboot).
- `debug-instrumentation.diff`: the debug-only toggles (module params). Not committed.
