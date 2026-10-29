# RK3588 IEP2 deinterlacer: build and on-board results

Branch `opi5/iep2-7.3` (worktree `~/orangepi5/work/iep2-7.3`), on top of `opi5/multicore-7.3`.
Board: Orange Pi 5 (RK3588S), kernel 7.3.0-opi5, combined DTB from `opi5/board-dt` (IEP2 + JPEG nodes).

## Build / static checks
| Check | Result |
|---|---|
| Module build, W=1 (`M=drivers/media/platform/rockchip/iep`) | clean, signed, vermagic `7.3.0-opi5`, `kernelrelease` = `7.3.0-opi5` |
| sparse | not installed on the host |
| checkpatch --strict (per commit) | only missing Signed-off-by (by rule), `Co-Authored-By` form, MAINTAINERS note on uapi/binding commits; SPDX check skipped (python `ply` missing) |
| dt_binding_check `rockchip,rk3568-iep.yaml` | clean |
| CHECK_DTBS rk3588s-orangepi-5.dtb, rk3588s-orangepi-5-sata.dtb | clean |

## Board run 1 (12:37), first committed driver: FAILED, recovered
The first streaming job (I1O1T) read past the end of the source buffer (IOVA 0xfff98000 = page-rounded end of a
720x576 NV12 buffer at 0xfff00000). The IEP retries a faulting read forever: about 39k rk_iommu faults over 2.5 min,
`irq 27: nobody cared`, RCU stall, journald watchdog. Recovered by restoring the DTB, removing the module and rebooting.
The BSP has the same workaround (`mpp_iep2.c`, I1O1T, `src_iova_end`: it maps a spare page at the fault address);
that is not possible in mainline (`iommu_set_fault_handler()` refuses DMA-API default domains).
Logs: `journal-storm1.txt`, `dmesg-storm1.txt`.

Fix (fixup commit 8da9bb0ee): OUTPUT `sizeimage` tail padding (debug param `src_tail`, default 4096), and an abort
path in the hard IRQ (4 shared IRQs during a job without IEP status, so the IOMMU is faulting: mask, soft reset,
fail the job).

## Board run 2 (12:58), module with padding (8da9bb0ee)
All runs under `tools/guard.sh` (timeout plus dmesg fault count). **0 IOMMU faults, 0 IEP errors in all runs.**

| Test | Result |
|---|---|
| Probe: `/dev/video6`, IOMMU group 8, IRQ 28 (GIC SPI 117) shared `fdbb0800.iommu, fdbb0000.deinterlace` | PASS |
| Runtime PM: device and IOMMU `suspended` when idle, also after all tests | PASS |
| v4l2-compliance 1.32.0 `-s` | 56/57; the 1 failure was `V4L2_CID_MIN_BUFFERS_FOR_OUTPUT` (only allowed on stateful encoders), fixed in f79075dcb (not yet re-run on the board) |
| Streaming in compliance (MMAP, select, epoll) | PASS |
| 720x576 and 1920x1080, NV12 and NV16, TFF and BFF, bob and MA, frame and field rate (32 runs) | PASS (no errors), PSNR below |
| NV21 1080 bob | PASS (37.19 dB Y, same as NV12) |
| Progressive bypass (`V4L2_FIELD_NONE`), also with field rate set | bit-exact |
| 50 STREAMOFF/STREAMON cycles, MA field rate and bob (1080, 15 frames/cycle) | PASS |
| 30 open/stream/close cycles | 30/30 |
| Throughput 1080i NV12 MA frame rate, 495 frames, 4 buffers, incl. memcpy in the client | 290 frames/s (11.6x real time for 1080i25) |
| Throughput 1080i field rate (25 frames, incl. setup) | 85 in/s, 170 out/s |
| Throughput 576i | 400 to 600 frames/s |
| Shared-IRQ count after all tests | 3472 on IRQ 28, no storm, no `nobody cared` |
| GStreamer 1.28.7 `v4l2convert` (the IEP took the generic name; the RGAs are `v4l2video0convert`/`v4l2video1convert`) | progressive pass-through bit-exact; **interlaced: not negotiable** (v4l2transform asks for `interlace-mode` unchanged on CAPTURE, driver returns FIELD_NONE, "Device wants progressive interlacing"). Needs a GStreamer change. |
| FFmpeg 8.1 | no V4L2 m2m deinterlace filter; used for references only |
| Deliberate zero-padding fault test (abort path) | **DEFERRED** (coordinator) |

### PSNR, luma, dB (testsrc2 50p, `interlace=lowpass=off` to 25i; reference = progressive source; frame rate vs even frames, field rate vs all 50)
| size | fmt | order | bob frame | ma frame | bwdif frame | yadif frame | bob field | ma field | bwdif field | yadif field | weave |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 720x576 | nv12 | tff | 35.21 | 36.68 | 36.77 | 36.22 | 35.21 | 33.24 | 36.75 | 36.22 | 31.20 |
| 720x576 | nv12 | bff | 35.24 | 36.74 | 36.78 | 36.19 | 35.22 | 33.24 | 36.76 | 36.19 | 31.23 |
| 720x576 | nv16 | tff | 35.21 | 36.68 | 36.77 | 36.22 | 35.21 | 33.24 | 36.75 | 36.22 | 31.20 |
| 720x576 | nv16 | bff | 35.24 | 36.74 | 36.78 | 36.19 | 35.22 | 33.24 | 36.76 | 36.19 | 31.23 |
| 1920x1080 | nv12 | tff | 37.16 | 35.46 | 37.84 | 37.65 | 37.15 | 33.10 | 37.83 | 37.65 | 31.45 |
| 1920x1080 | nv12 | bff | 37.16 | 35.45 | 37.83 | 37.61 | 37.16 | 33.10 | 37.83 | 37.61 | 31.44 |
| 1920x1080 | nv16 | tff | 37.16 | 35.46 | 37.84 | 37.65 | 37.15 | 33.10 | 37.83 | 37.65 | 31.45 |
| 1920x1080 | nv16 | bff | 37.16 | 35.45 | 37.83 | 37.61 | 37.16 | 33.10 | 37.83 | 37.61 | 31.44 |

Per-frame alignment (`tools/psnrmat`) shows:
- **Bob** and **MA frame rate** are aligned with the expected source frame.
- **MA field rate (I5O2)**: the first-field output is good (36.6 dB at 576), but the second-field output sits halfway
  between source frames 2i and 2i+1 (30.7 dB to both). With `nxt = cur` (zero latency) the second field has no
  look-ahead. MPP runs I5O2 with one frame of latency (`cur` = previous frame, `nxt` = new frame).
- **MA frame rate** is +1.4 dB over bob at 576 but -1.7 dB at 1080 (more fine motion in testsrc2 at 1080).
- So the default was switched to **bob** (f79075dcb). Real MA quality needs the latency-1 mode (design U3).
- Synthetic content only (testsrc2); real interlaced material should be checked.

## Board run 3 (13:10), final build (f79075dcb, coordinator-installed, camera-detect DTB with the same IEP nodes)
| Test | Result |
|---|---|
| Probe (`/dev/video3`), `src_tail` = 4096 | PASS |
| v4l2-compliance 1.32.0 `-s` | **57/57, 0 warnings** |
| Controls | deinterlacing_mode default Bob; output_one_frame_per_field |
| 1080i bob/MA x frame/field rate | PASS, 158 fps frame rate, 84 in/s / 168 out/s field rate (15 frames incl. setup) |
| MA with REQBUFS count=1 on OUTPUT (raised to 2 by `min_reqbufs_allocation`) | PASS, no stall |
| 20 STREAMOFF/ON cycles, MA field rate, BFF | PASS |
| Idle runtime status / IRQ 28 count / IOMMU faults | suspended / 729 / 0 |

Left installed: final build in `/lib/modules/7.3.0-opi5/updates/opi5-iep/` (healthy).

## Known issues
1. Over-read length still unknown; `src_tail` = 4096 is a guess (BSP maps one 4 KiB page). Measuring needs the
   deferred zero-padding test. The padding makes DMABUF imports of exactly frame-sized buffers fail at QBUF (safe).
2. Field rate, first job after STREAMON: both CAPTURE buffers get the same timestamp (no previous timestamp to derive
   half a period from).
3. GStreamer v4l2convert cannot deinterlace (see above). The new device also takes the plain `v4l2convert` name.
4. UAPI (U7): driver-private controls vs a generic deinterlace-mode control.
5. GStreamer follow-ups (coordinator list): the IEP takes the plain `v4l2convert` name, and v4l2transform cannot change interlace-mode.

## Files
- `rockchip-iep.ko`: signed, final build (driver commit after autosquash)
- `dt/0001-arm64-dts-rockchip-add-IEP2-deinterlacer-to-RK3588.patch`, `patches/`
- `tools/`: `iep-test.c` (m2m client), `psnrmat.c`, `board-test.sh`, `guard.sh`
- `board-results-run2.txt`: raw output of run 2
