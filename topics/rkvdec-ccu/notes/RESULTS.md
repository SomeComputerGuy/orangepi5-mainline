# rkvdec: one stream on both RK3588 decoder cores (CCU frame pipelining)

Branch `opi5/rkvdec-ccu-7.3` (worktree `work/rkvdec-ccu-7.3`), based on `opi5/rkvdec-ccu-base-7.3` = `opi5/integration-7.3` + the 3 codec-quality rkvdec commits (H.264/HEVC colmv compression, HEVC SPS default; cherry-picked, authorship kept), so the A/B is against the board's previous rockchip-vdec, build dir
`build/wt-rkvdec-ccu-7.3`. Patches: `patches/0001-0008` (0008 is a DEBUG-only A/B patch, not for upstream).

**Status: implemented, compile-tested (every commit, W=1), checkpatch/dt_binding_check/dtbs_check clean,
installed on the board; board verification NEEDS THE REBOOT** (see "Board state" and "After the reboot").

## 1. How the vendor runs one stream on both cores

Sources (read-only reference, nothing copied): Rockchip BSP kernel `mpp_rkvdec2.c`, `mpp_rkvdec2_link.c`,
`mpp_rkvdec2_link.h` (develop-6.1, in `_downloads/vp9-perf/`), BSP `rk3588s.dtsi` (develop-5.10 and 6.1,
`_downloads/iep2/`), MPP userspace develop (`_downloads/rkvdec-ccu/mpp`, `mpp/hal/rkdec/{h264d,h265d,vp9d}`,
and `_downloads/codec-quality/vdpu34x_com.h`).

**It is frame-level parallelism with a hardware row/coordinate dependency sync, not an intra-frame split.**

- DT: `rkvdec_ccu: rkvdec-ccu@fdc30000` (`rockchip,rkv-decoder-v2-ccu`, reg 0x100, `ACLK_RKVDEC_CCU` @600 MHz,
  `SRST_A_RKVDEC_CCU`, `PD_RKVDEC0`, `rockchip,ccu-mode = <1>` = "soft ccu"). Both cores have
  `rockchip,ccu = <&rkvdec_ccu>`, `rockchip,core-mask = <0x00010001>` / `<0x00020002>` (Rockchip hi-word
  write-mask format: bit n + mask bit n+16) and `rockchip,task-capacity = <16>` (only used by mode 2).
- Mode 1 ("soft CCU", the RK3588 default, `rkvdec2_soft_ccu_worker()`): every *task = one frame* goes to
  whichever core is idle (`rkvdec2_get_idle_core()`), so consecutive frames of one stream run on both cores at
  the same time. Per task the kernel: sets link-block reg 0x000 = BIT16 (core work mode) | BIT17 (CCU work
  mode); CCU 0x018 WORK_EN=1, 0x040 WORK_MODE=1, 0x044 CORE_WORK=core mask; enables + flushes the three core
  read caches (0x51c/0x55c/0x59c = cacheable|read-allocate|64 B, 0x510/0x550/0x590 = 1); ORs **reg013 bit 1**
  ("disable multicore pu/colmv offset req timeout reset"); writes the **film index = session index into
  reg028 bits 16-25** (`RKVDEC_REG_FILM_IDX_MASK 0x3ff0000`); per-resolution reg032 timeout; writes the
  registers; CCU 0x048 CORE_STA = core mask; starts. Completion is in submission order
  (`rkvdec2_soft_ccu_dequeue()` stops at the first unfinished task). While the CCU is on, *all* cores and the CCU
  are powered (`rkvdec2_ccu_power_on()`). Error recovery: CCU 0x04c CORE_IDLE (disconnect), soft reset, 0x054
  CORE_ERR clear, reconnect.
- Mode 2 ("hard CCU") is a link-table mode where the CCU itself dispatches a task list; no benefit with the
  2-deep queue V4L2 userspace gives us, and it needs the task tables.
- The dependency sync is in the cores (MPP `vdpu34x_com.h`, "reg027 ~ reg032 are added in vdpu38x at rk3588"):
  `SW027_CORE_SAFE_PIXELS` ("colmv and recon report coord x/y safe pixels"), `SWREG28_MULTIPLY_CORE_CTRL`
  (`ref_req_advance_flag`, `colmv_req_advance_flag`, `poc_only_highbit_flag`, `poc_arb_flag`, `film_idx`,
  `pu_req_mismatch_dis`, `colmv_req_mismatch_dis`), and regs 200-204 POC high bits (H.264 field parity; MPP
  writes them only on RK3588). A core reports how far it has written its frame; a core whose reference or
  co-located MV read hits a frame that another core is still writing (same film) waits. MPP userspace programs
  nothing special per frame for H.264/HEVC (H.264 sets `poc_arb_flag = 0`; HEVC leaves reg028 at 0); the kernel
  sets the film index. For VP9 the hardware even adapts probabilities across cores (`vp9_wr/rd_prob_idx`,
  `prob_ref_poc`, `segid_ref_poc`, last/golden/altref POC regs 95-100), which our driver does in software.
- The vendor never splits one frame across cores: option (b) doesn't exist on this hardware.

**Fit with the stateless model:** good. Userspace already submits one request per frame and the hardware
resolves the pixel/colmv dependencies; the kernel only needs >= 2 frames queued and has to keep completion in
order. GStreamer v4l2codecs does keep 2 in flight: `get_preferred_output_delay()` returns 1 for non-live
streams, and `gst_v4l2_decoder_request_queue()` waits for the oldest request only once more than
`MAX(1, render_delay)` = 1 are pending, i.e. frame N+1 is queued before GStreamer waits for N.

## 2. Design (mainline)

1. `media: v4l2-mem2mem: add v4l2_m2m_buf_detach_and_job_finish()` — takes the src/dst buffers of the running
   job off the ready lists without returning them and finishes the m2m job, so the next job can be scheduled
   while the hardware still works on this one (like MediaTek's LAT/core pipelining, but without a fake
   `job_finish` that WARNs for HOLD_CAPTURE_BUF-capable queues). Refuses jobs whose OUTPUT buffer holds the
   CAPTURE buffer (field pairs): those finish the usual way.
2. `media: rkvdec: complete decode jobs independently of the m2m job` — rkvdec tracks `struct rkvdec_job`s
   (per context, completed in decoding order) instead of the m2m job. A started job is detached as soon as
   another core is free; with no free core the m2m job is held and detached when a core frees up. m2m runs one
   job at a time (`max_parallel_jobs` back to 1), so `device_run()` always finds a free core, and multi-stream
   parallelism (the existing behaviour) falls out of the same mechanism. `job_ready()` decides whether the next
   frame of a context may start early (this patch: never). IRQ/watchdog work on their core, not `ctx->core`.
3. `media: rkvdec: vdpu381: give every job its own H.264/HEVC tables` — the PPS/RPS/scaling-list DMA tables
   (and their "unchanged" caches) per job slot.
4. `dt-bindings: media: rockchip: add the RK3588 video decoder CCU` — new `rockchip,rk3588-vdec-ccu` binding
   (reg, clocks, resets, power-domains); cores get `rockchip,ccu = <&vdec_ccu index>`.
5. `media: rkvdec: decode one stream on both RK3588 cores with the CCU` — `rkvdec-ccu.c` platform driver;
   the master finds the CCU through the cores' phandles (if its driver isn't bound, the decoder works as before);
   per job: connect the core (link bits, CCU WORK/WORK_MODE/CORE_WORK), film index (one IDA entry per open
   file) + reg013 `req_timeout_rst_sel`, CORE_STA before DEC_E; all cores + CCU powered during a job; for
   H.264/HEVC (`RKVDEC_FMT_FLAG_PIPELINE`) `min(cores, 2)` job slots, and `job_ready()` lets frame N+1 start
   while N is decoding unless (a) the CAPTURE buffer is held / is the second field, or (b) **the next CAPTURE
   buffer is still a reference of an in-flight frame** (GStreamer returns a DPB picture to the pool when no
   *future* frame needs it, which can be before the in-flight frame finished reading it — a real race once
   frames overlap; the backends record each job's reference vb2 buffers for this check).
   VP9 stays serial within a stream (software backward adaptation reads frame N's symbol counts before N+1).
6. `arm64: dts: rockchip: add the RK3588 video decoder CCU` — node at 0xfdc30000 (+ `rockchip,ccu` on vdec0/1).
7. `media: rkvdec: vdpu381: enable and flush the read caches for every job` — the mainline driver never set up
   the core caches (BSP does it for every frame, single- and multi-core). Required for correctness with two
   cores (a core may hold stale lines of a buffer the other core rewrote) and possibly a single-core speedup.
8. `DEBUG: ...` (not for upstream) — runtime-writable `pipeline`, `cache`, `ccu_hw` parameters and
   `stat_jobs`/`stat_overlap` counters (`/sys/module/rockchip_vdec/parameters/`), so one boot can A/B everything.

Rejected: making m2m run several jobs of one context (changes TRANS_RUNNING/buffer semantics for every m2m
driver); intra-frame split (no hardware support); hard-CCU link mode (needs deeper queues than V4L2 userspace
provides; can come later).

## 3. Results

### Before (current board driver: codec-quality debug rockchip-vdec with stock defaults, kernel #3)
Fluster (`scripts/fluster.sh base`, rkvdec elements only, -j2; `~/ccu/fluster-base/` on the board):

| Suite | Decoder | Result | Failing |
|---|---|---|---|
| JCT-VC-HEVC_V1 | GStreamer-H.265-V4L2SL-RKVDEC | 146/147 | TSUNEQBD_A_MAIN10_Technicolor_2 (Error) |
| JVT-AVC_V1 | GStreamer-H.264-V4L2SL-RKVDEC (v4l2slvideo6h264dec) | 129/135 | CVFC1_Sony_C, FM1_BT_B, FM1_FT_E, FM2_SVA_C (Error), SP1_BT_A, sp2_bt_b |
| JVT-FR-EXT | same | 65/69 | HPCAMOLQ_BRCM_B, HPCVMOLQ_BRCM_B, Hi422FREXT17_SONY_A, Hi422FREXT19_SONY_A |
| VP9-TEST-VECTORS | GStreamer-VP9-V4L2SL-RKVDEC | 230/305 | (same 75 as before: small sizes etc.) |

Throughput and bit-exactness (`scripts/baseline.sh`, `~/ccu/baseline-1029-2327/` on the board): the whole
600-frame 3840x2160 clips from `~/demo`, `filesrc ! demux ! parse ! <rkvdec element> ! fakevideosink sync=false`,
best of 2; bit-exactness = every frame's framemd5 (GStreamer -> videoconvert I420) vs FFmpeg software decoding:

| Clip | fps (1 stream, 1 core) | bit-exact |
|---|---|---|
| yacht_hevc_2160p120.mp4 (x265 CRF20, ~77 Mbit/s) | 130.6 | 600/600 |
| yacht_h264_2160p120.mp4 | 67.8 | 600/600 (a first run stopped after 68 frames while another agent switched HDMI modes; the rerun was complete) |
| yacht_vp9_2160p120.webm | 138.5 | 600/600 |
| 2 x HEVC at once (2 cores) | 245.2 total | |

Note: decode-only HEVC is already ~130 fps on one core; the "~63 fps" figure came from kmssink/VOP2 pacing
(`_out/vop2-underflow/RESULTS.md`), not from the decoder. H.264 is the codec that needs the second core.

### After: PENDING REBOOT (run `~/ccu/ccu-verify.sh`, then `~/ccu/fluster.sh ccu`)

## 4. Side findings

- codec-quality's private fluster copy (`~/cq/flpkg` on the board) never ran its `-RKVDEC`/`-HANTRO` decoders:
  they're created with `type()` and aren't module attributes, so multiprocessing can't pickle them and fluster
  silently runs 0 tests ("Ran 0/147"). Fixed copy: `~/ccu/flpkg` (classes registered in `globals()` with
  `__module__`). Also their `run-fluster.sh` runs a shell function under `timeout`, which can't exec it.
- Mainline has `vdec1` at 0xfdc40000, the BSP at 0xfdc48000 (both decode; presumably an alias). Not changed.
- The H.264/HEVC register-struct layouts (reg008-reg032) match MPP's; no layout bug.

## 5. Board state (installed, active after the reboot)

- `/lib/modules/7.3.0-opi5/updates/opi5-rkvdec-ccu/{rockchip-vdec,v4l2-mem2mem}.ko` (signed, built from
  `opi5/rkvdec-ccu-7.3` HEAD incl. the DEBUG patch; `modules/` here, `modules/BUILT-FROM`). depmod done.
  `updates/opi5-codec-quality/rockchip-vdec.ko` was removed (its hantro-vpu and rockchip-jpegd stay), depmod done; neither module is in the initramfs.
  `v4l2-mem2mem.ko` only adds one export; all 58 existing symbol CRCs are identical, so the in-tree and other
  drop-in m2m drivers load unchanged.
- DTB `/usr/lib/linux-image-7.3.0-opi5/rockchip/rk3588s-orangepi-5-sata.dtb` = previous DTB (md5
  c50a1a1a..., backup `/var/tmp/rk3588s-orangepi-5-sata.dtb.pre-ccu`) + `dt/rk3588-vdec-ccu.dtbo` (adds only
  the CCU node and `rockchip,ccu` on vdec0/vdec1), md5 54f61e44.... If another agent installs a new combined
  DTB, re-apply: `sudo fdtoverlay -i <dtb> -o <dtb> /tmp/rk3588-vdec-ccu.dtbo` (copies: `dt/` here, `~/ccu/rk3588-vdec-ccu.dtbo` on the board). Without the
  node, the new driver behaves like the old multi-core one.
- Undo: remove `updates/opi5-rkvdec-ccu`, `depmod -a`, restore the `.pre-ccu` DTB, reboot.

## 6. After the reboot

```sh
~/ccu/ccu-verify.sh          # driver/DT state, every-frame bit-exactness vs FFmpeg (framemd5) for 4K HEVC,
                             # H.264, VP9, fps A/B (pipeline/cache/ccu_hw), 2 streams, dmesg -> ~/ccu/run-*/summary.txt
~/ccu/fluster.sh ccu         # fluster HEVC/AVC_V1/FR-EXT/VP9 on rkvdec, -j2 -> ~/ccu/fluster-ccu/summary.txt
```
Pass criteria: "decoding with the CCU" in dmesg; 600/600 frames bit-exact for every mode; fluster equal to the
baseline above; `stat_overlap` > 0 and both cores' IRQ counts advancing for a single stream; no timeouts or
IOMMU faults; 4K120 HEVC >= 120 fps with pipeline=1.

## Update 2026-10-30: first board run and VP9 fix
`ccu-verify.sh` (coordinator): HEVC 4K 130.4 -> 227.8 fps, H.264 4K 67.6 -> 121.4 fps, both 600/600 bit-exact.
VP9 in CCU mode: 0/600 bit-exact, 15.9 fps (136.4 fps with ccu_hw=0). The VP9 back-end doesn't program the
POC/probability/segment-map references the cores sync VP9 on (MPP regs 65, 95-100, reg028 prob idx). Fix
(squashed into patch 0005): only formats with RKVDEC_FMT_FLAG_PIPELINE (H.264, HEVC) run in CCU mode; for
others the core is disconnected from the CCU (link ctrl 0, CORE_WORK bit cleared) and reg013/reg028 stay 0.
Installed, needs a reboot to verify.

## Update 2026-10-30 (2): H.264 fluster regression, root cause, kernel-4 build
Board run with 17e7fe46: HEVC 146/147 (= baseline), but JVT-AVC_V1 30/135. Run order (`~/ccu/fluster-ccu/`):
the 16 vectors before `cabac_mot_fld0_full` pass; from the first field-coded stream on, almost every stream
(progressive ones too) decodes wrong, with one short passing window; no kernel errors during AVC_V1. In
JVT-FR-EXT the cores then stopped finishing frames (910 "Frame processing timed out" from 00:19:56), then rk_iommu
stall timeouts, PD rkvdec0 idle failure and an SError panic at 00:21:09 (`journalctl -k -b -1`) -- that's why the
queue died. After the reboot, the failing progressive vectors (CABA3_TOSHIBA_E, CAMA1_Sony_C) decode bit-exact in
every mode, alone and two at a time, so the breakage is state left behind by interlaced streams in CCU mode.
Cause: the driver didn't program the POC high bits (regs 200-204) that MPP writes on RK3588 (field parity of the
current picture and of references, 3 for unused DPB entries); the cores use them to identify references in CCU
mode, so field pictures (two fields in one buffer, unused entries pointing at the current buffer) leave the CCU
waiting on references that never complete. Fix (commit `keep interlaced H.264 off the CCU, program the POC high
bits`): program the high bits as MPP does; run H.264 streams without frame_mbs_only_flag serially with the core
disconnected from the CCU (like VP9); don't reuse a just-freed film index. Unverified on the board.

Kernel 4: branch `opi5/rkvdec-ccu-k4` (worktree `work/rkvdec-ccu-k4`) = v7.3 + `patches/linux` (309, `git am`,
identical rkvdec/m2m sources to `src/linux`) + the 9 commits; built in `build/wt-rkvdec-ccu-k4` with build/linux's
config, Module.symvers and key (m2m CRCs identical, one new export). Staged, NOT installed: `k4/` here and
`~/ccu/k4/` on the board; `~/ccu/k4/install-k4.sh` installs the modules, removes codec-quality's rockchip-vdec,
depmods and applies the CCU overlay to the kernel-4 DTB (backup `.pre-ccu-k4`). Patches re-exported from the k4
branch (0009 should be squashed into 0005 after the board run).

## Update 2026-10-30 (3): no serial fallbacks
- H.264 field/MBAFF: the "interlaced off the CCU" fallback is removed; these streams run in CCU mode with the POC
  high bits programmed as MPP does (commit 0009 `program the H.264 POC high bits for the CCU`). Field pairs still
  don't overlap each other: both fields write one CAPTURE buffer that m2m holds on the queue
  (V4L2_BUF_FLAG_M2M_HOLD_CAPTURE_BUF); frame pictures (incl. MBAFF and PAFF frames) pipeline. Module
  8ffd956d staged in `~/ccu/k4b/` (board runs eac7d04, the fallback build). Needs a reboot/board slot to verify.
- VP9 is still decoded with the cores disconnected from the CCU, one frame of a stream at a time. That is a
  limitation of the current VP9 back-end, not a hardware one: rkvdec adapts the probabilities on the CPU in
  `rkvdec_vp9_done()` from frame N's symbol counts and keeps the segment map / last-frame state per context, so
  N+1 can only be set up after N is done. The proper fix is MPP's design (hal_vp9d_vdpu34x.c): hardware backward
  adaptation (reg103 refresh_en/prob_save_en, reg162 last_prob_base, reg172 update_prob_wr_base, reg028
  vp9_rd/wr_prob_idx, reg099 prob_ref_poc) plus the POC registers 65/95-98/100 (cur/last/golden/altref/col/segid
  ref POC from a per-stream frame counter), which the CCU synchronizes. Not implemented yet (VP9 back-end rework).

## Update 2026-10-30 (4): k4b wedge fixes + field pairs + VP9 hardware adaptation (combined build k4c)
k4b board run: ccu-verify passed; fluster HEVC 146/147; JVT-AVC_V1 wedged core 1 with HCBP2_HHI_A + HCMP1_HHI_A
at once (timeouts every ~39 ms, IOMMU stall timeouts, PD rkvdec1 idle failure; evidence `~/ccu/fluster-k4b-wedge/`).
New commits on `opi5/rkvdec-ccu-k4` (patches 0010-0014):
- 0010: a failed or timed-out core is forced idle in the CCU, soft reset (reset lines pulsed if that fails),
  its IOMMU reinitialized and reconnected (BSP soft-CCU reset sequence); the job fails back to userspace. POC
  aliases (IDR/MMCO5/CRA reuse POCs; the cores match references by POC) could make an in-flight frame wait for the
  next frame that waits for it: a frame starts in CCU mode only once no earlier in-flight frame has a reference
  with its POC (`stat_poc_alias` counter). Root cause of the HHI hang is this hypothesis + reset; unverified.
- 0011-0012 (field-pair agent, `_out/rkvdec-ccu/fieldpair/NOTES.md`): m2m lets detached jobs hold the CAPTURE
  buffer (`TRANS_HELD_DETACHED`, `v4l2_m2m_detached_buf_done()`); rkvdec lets the second field start while the
  first one runs. Evidence: MPP fast mode and the BSP soft-CCU worker already run both fields at once.
- 0013-0014 (VP9 agent, `_out/rkvdec-ccu/vp9hw/NOTES.md`): hardware backward adaptation (MPP HW_PROB layouts,
  byte-identical to MPP's writers on 10000 random headers in a host harness), CPU adaptation removed; POC
  registers from a per-stream counter; VP9 pipelined in CCU mode.
Modules (k4c, `_out/rkvdec-ccu/k4c/`, also `~/ccu/k4c/` on the board): rockchip-vdec 385f40fa, v4l2-mem2mem
d3ee1f68 (58 existing CRCs identical; new exports detach_and_job_finish, detached_buf_done). Every commit builds
with W=1; checkpatch clean except the known MAINTAINERS note on 0005.

## Update 2026-10-30 (5): k4c regressions and timeouts
k4c fluster: HEVC 146/147, AVC_V1 128/135 (new fail HCBP1_HHI_A), FR-EXT 64/69 (new fail HCHP3_HHI_A), VP9 230/305;
9 timeouts: 04:49:04 during AVC_V1 (04:48:51-04:49:11, the HHI vectors), 8 at 04:50:14-17 during VP9 (started
04:50:08); all recovered. HCBP1: hierarchical P (all P slices, POC lsb 0,32,16,8,24,...; 15 refs, MMCO1);
HCHP3: field-coded hierarchical B (PAFF, 8 refs). Not root-caused yet: k4c logged nothing about the jobs.
k4d (`_out/rkvdec-ccu/k4d/`, board `~/ccu/k4d/`, rockchip-vdec dbbca28c): POC-alias wait moved before the watchdog
is armed (a waiting frame could time out), "resetting the core" logged, and DEBUG timeout dumps (film, POCs, refs,
status/debug regs, CCU regs) + `fieldpair` A/B switch. `~/ccu/hhi-ab.sh` A/Bs the HHI vectors (5 runs each, alone
and two at a time) across fieldpair/pipeline/ccu_hw.

## Update 2026-10-30 (6): cause of the k4c/k4d regressions and timeouts
k4d dumps (`~/ccu/dmesg-k4d.txt`): every timeout follows a core reset within ms; the timed-out core was mid-frame
in CCU mode (CCU CORE_STA = 3, both busy). The resets come from vectors that fail without the CCU too (decode
errors). In the fluster order the regressions ran next to such vectors: HCBP1_HHI_A with FM2_SVA_C (Error) and
FM1_FT_E, HCHP3_HHI_A next to the Hi422 failures, VP9 sharpness-7 next to size-08x08. Alone they pass (hhi-ab 5/5).
Cause: resetting (and forcing idle in the CCU) one core breaks the frame the other core is decoding. Fix (commit
`reset the cores together once they are idle`, k4e 8e65bae6): as the BSP soft-CCU worker, on a failure start no
new job (the held m2m job is run by the reset work afterwards), fail the later frames of the failed stream at once,
wait for all cores to be idle, reset them all. `~/ccu/ccu-repro.sh` = the minimal pairs (expected: fail with k4d,
pass with k4e).

## Update 2026-10-30 (7): kernel 5 builds, clean 16xx series
- k5e (board test build, with the DEBUG A/B parameters): branch `opi5/rkvdec-ccu-k5` = v7.3 + patches/linux (318)
  + 0001-0017; modules in `k5e/` and `~/ccu/k5e/` (`install.sh` applies the CCU overlay to the k5 DTB).
- Clean series for patches/linux: branch `opi5/rkvdec-ccu-k5-clean`, `_out/rkvdec-ccu/patches-16xx/1601-1614`:
  same code without the DEBUG commits (fixups squashed), every commit builds with W=1, checkpatch --strict clean
  (only the MAINTAINERS note on 1605, which is covered by the existing rkvdec F: entry), one Assisted-by each,
  no SoB/Co-Authored-By. VP9 and field/MBAFF H.264 run dual-core through the CCU (1611-1613); no serial fallback
  remains. To go into patches/linux once k5e passes on the board.

## Update 2026-10-30 (8): board slot 08:35-09:40 (kernel 5) -- NOT ready to land
Builds tested (k5 tree, DEBUG): 9ac73df1 (k5e) -> d59a2687 (job-start/reset race) -> 48691f5b (+ context pin
UAF fix, quiesce before IOMMU restore, H.264 field/frame CCU sync) -> 01ed182a (+ stop core / leave CCU mode
before the reset, always CRU reset). Clean equivalents: `opi5/rkvdec-ccu-k6` (on opi5/image-k6-7.3, 314 patches),
`patches-16xx/1601-1617` (each commit builds, checkpatch clean) -- DO NOT LAND yet, see the open bug below.

Results with 48691f5b (pipeline/ccu on), same boot single-core reference (pipeline=0 ccu_hw=0):
- ccu-repro: 5/5 for every pair (HCBP1+FM2_SVA_C, HCBP1+FM1_FT_E, HCHP3+Hi422FREXT17, sharpness-7+size-08x08).
- fluster CCU vs single, per vector identical in all four suites: HEVC_V1 146/147, AVC_V1 129/135, FR-EXT 65/69,
  VP9 230/305 (failing vectors = the single-core ones: `fluster-k5/`, `~/ccu/fluster-single/*.fail.txt`).
  The H.264 run was repeated with fieldpair=Y (first run had it off by mistake): identical again.
- ccu-verify: 600/600 bit-exact HEVC/H.264/VP9; HEVC 227 fps (130 single), H.264 121 (67), VP9 147 (137);
  2 x HEVC 240 total, 121.6/121.4 fps each (fair), HEVC+H.264 85/84 fps.
- reopen.sh 50 cycles x {normal, SIGKILL mid-stream, SIGKILL at start} with the 4K HEVC stream running: 0 hangs,
  0 timeouts, 0 hung tasks.
Root causes found and fixed in the slot: (1) a victim stream next to a broken stream (FM1_FT_E: hardware
timeouts, sta 0x23) decoded wrong after the all-cores reset: soft reset alone left state behind; the BSP's
unconditional CRU reset fixed it. (2) HCHP3_HHI_A: a frame picture and a field picture of the same stream in
flight on two cores aren't synchronized by the CCU (parity of the producer); they no longer overlap, and field
pictures program only their own POC (MPP). (3) the context use-after-free and the job-start/reset race.

OPEN BUG (blocks landing): after a watchdog timeout on the broken FMO streams (FM1_BT_B/FM1_FT_E pairs in
JVT-AVC_V1), the reset path produces "Page fault while iommu not attached to domain?" + "Enable stall request
timed out" (11-15 per AVC_V1 run, 1 of 2 runs, on either core; also seen at 08:58 in single-core mode), and with
01ed182a the board panicked (memory corruption: commoncap WARNING, NULL derefs in enqueue_task_fair from
delayed_work_timer_fn) 60 s into an AVC_V1 run. Most likely cause: the CRU reset of a core also resets its IOMMU
(same reset lines/power domain), leaving it in bypass while the core (or the CCU) can still master the bus, so
DMA reaches physical memory. To do (fresh agent, KASAN + DEBUG_OBJECTS_WORK test kernel): stall/disable the IOMMU
only with the core quiesced, order soft reset -> bus idle -> CRU reset -> IOMMU reinit -> restart, check what
the CRU reset does to the IOMMU registers, and whether the in-tree driver (which never resets, only reattaches
the IOMMU on error) faults on FM1_BT_B+FM1_FT_E too. Board left on plain kernel 5 (k5e removed, .pre-ccu-k5 DTB).

## Hand-over (2026-10-30): branches, builds, scripts
Ownership of the reset/IOMMU fix, the rebase onto reopen-fix 1801/1802, the KASAN proof and landing 16xx moved
to a new agent (plan in the coordinator's message; summary: one reset path = 1802's `rkvdec_core_recover()`,
CCU force-idle/leave-CCU-mode before and error-clear/reconnect after it, all-cores-idle reset kept, no
always-on CRU pulse unless ccu-repro shows the victim corruption again).

Branches (worktrees under `work/`):
- `opi5/rkvdec-ccu-k6` (worktree `rkvdec-ccu-k6`): the clean series, 17 commits on `opi5/image-k6-7.3` (314
  patches) = `patches-16xx/1601-1617`. Every commit builds W=1, checkpatch --strict clean, one Assisted-by each.
  Contains everything of 48691f5b except the DEBUG parts. NOT ready to land (open IOMMU/reset bug, section 8).
- `opi5/rkvdec-ccu-k5` (worktree `rkvdec-ccu-k5`): debug tree on the 318-patch kernel-5 stack, base = the stack
  commit in `/tmp/ccu/k5stack` (git am of patches/linux at build 5). Board builds: k5e 9ac73df1 (commit 04519d4f
  + DEBUG), k5f 7b5dff03 (9d71151a), 48691f5b and 01ed182a (both from a59b9263; 48691f5b without the changes in
  `scripts/stopcore-01ed182a.py`). 48691f5b is the build behind every result in section 8; 01ed182a panicked.
- `opi5/rkvdec-ccu-k5-clean`: superseded by `-k6` (contains USB3 patches 1501-1504 in its base).
- Older: `opi5/rkvdec-ccu-k4` (k4c/k4d/k4e builds), `opi5/rkvdec-ccu-7.3` (kernel 3), `opi5/rkvdec-ccu-vp9hw`
  and `opi5/rkvdec-ccu-fieldpair` (the two sub-agent branches, merged into k4/k5/k6).
- Build dirs: `build/wt-rkvdec-ccu-k5` (kernel-5 config/symvers/key), `build/wt-rkvdec-ccu-k4`, `-7.3`.

Scripts: host `work/_out/rkvdec-ccu/scripts/`, board `~/ccu/` (same names):
- `build.sh` (W=/B= env: build + sign v4l2-mem2mem.ko and rockchip-vdec.ko for a build dir)
- `ccu-verify.sh` + `ccu-lib.sh` (600-frame 4K bit-exact vs FFmpeg framemd5, fps A/B, two streams)
- `fluster.sh <tag> [suites]` (rkvdec elements only, -j2, fixed private fluster copy `~/ccu/flpkg`; results
  `~/ccu/fluster-<tag>/`, failing lists `*.fail.txt`), `ccu-repro.sh` (victim + broken-stream pairs, 5 runs),
  `fmfm.sh [n]` (FM1_BT_B+FM1_FT_E together: timeouts / IOMMU faults), `reopen.sh [cycles]` (close/reopen one
  context in 3 variants while 4K HEVC streams), `hhi-ab.sh`, `h3b.sh`, `fm.sh` (per-frame diffs), `baseline.sh`.
- Board copies of builds: `~/ccu/k5e/` (install.sh applies the CCU overlay), `~/ccu/k5f/`; overlay `dt/`.

Per-vector notes (for the fluster triage agent; single-core = in-tree behaviour, CCU identical on every vector
with 48691f5b): the failing vectors are listed per suite in `fluster-k5/` (`fluster-single.tgz`,
`fluster-ccu.tgz`) and on the board in `~/ccu/fluster-single/*.fail.txt`:
- JVT-AVC_V1 129/135: CVFC1_Sony_C, FM1_BT_B, FM1_FT_E (hardware timeouts, sta 0x23, and the IOMMU-fault
  trigger when run together), FM2_SVA_C (Error), SP1_BT_A, sp2_bt_b (SP slices).
- JVT-FR-EXT 65/69: HPCAMOLQ_BRCM_B, HPCVMOLQ_BRCM_B, Hi422FREXT17_SONY_A, Hi422FREXT19_SONY_A.
- JCT-VC-HEVC_V1 146/147: TSUNEQBD_A_MAIN10_Technicolor_2 (Error).
- VP9-TEST-VECTORS 230/305: the 75 small-size/odd-size vectors (vp90-2-02-size-08x08 ... etc., unchanged from
  the kernel-3 baseline in section 3).
