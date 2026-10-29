# rockchip-venc: V4L2 stateless encoder for the RK3588 VEPU580

Branch `opi5/rkvenc-7.3` in `~/orangepi5/work/rkvenc-7.3`. It is based on `opi5/multicore-7.3`
plus the Orange Pi 5 SATA DTS commit.

**Status: working on the board.** The safe tests ran on the Orange Pi 5 at about 17:45–18:20 on
2026-10-29, using the combined DTB from `opi5/board-dt` and the VEPU121 agent's v4l2-core
modules. Every stream decodes with 0 errors in ffmpeg, and both cores run in parallel. dmesg
shows no IOMMU faults or encoder errors. The first P frame did **not** hang.

## Commits (`git log --oneline opi5/multicore-7.3..`)

```
c12698a64 arm64: dts: rockchip: Add the VEPU580 encoder cores to the RK3588
f33a0ab38 media: rockchip: Add a VEPU580 stateless video encoder driver
a17ffbfd4 dt-bindings: media: Add the Rockchip VEPU580 video encoder
ab9ea6f95 DO NOT UPSTREAM: media: v4l2-ctrls: Keep the v4l2-core symbol versions        (VEPU121 agent)
2aa17bece media: h264: Support picture order count type 2 in stateless encode           (VEPU121 agent)
cadb459da media: h264: Only write the SPS and PPS of a stateless encode when they change (VEPU121 agent)
0eec39baf media: h264: Add stateless encode rate control              \
de6101d07 media: h264: Add stateless encode reference management       |
37b92c339 media: h264: Add stateless encode rbsp                       |  Paul Kocialkowski,
67a63bf23 media: h264: Add stateless encode core                       |  [PATCH 1-7/14] v1,
5bfd14948 media: h264: Add SPS video definitions                       |  2026-05-22
b89ff5224 media: uapi: Add H.264 stateless encode support              |
6801bbd68 media: h264: Add a more generic reflist builder init        /
5e33b74b0 arm64: dts: rockchip: add Orange Pi 5 M.2 SATA variant
```

### uAPI

The uAPI is Paul Kocialkowski's "[PATCH 00/14] media: Add V4L2 H.264 stateless encode and VC8000E
support", v1, 2026-05-22 (<https://lore.kernel.org/all/20260522101653.2565125-1-paulk@sys-base.io/>).
No v2 had been posted. Only the generic patches 1–7 (uAPI and v4l2-core helpers) are applied,
cherry-picked from the VEPU121 agent's branch `opi5/vepu121-h264enc`, which applied them with
`git am`. Their content is identical to the mbox; the patch-id differs only because of the
trailing `-- ` line. Authorship and `Link:` tags are kept.

On top of these are the VEPU121 agent's three v4l2-core commits:
- the SPS/PPS change-detection fix (this fixes the inverted check noted below);
- POC type 2 (rejected by this driver: the VEPU580 needs POC type 0);
- the DO-NOT-UPSTREAM commit that keeps the v4l2-core symbol versions.

`drivers/media/v4l2-core`, `include/media` and `include/uapi` are therefore byte-identical to
`opi5/vepu121-h264enc`. The two branches merge cleanly, and this driver links against the
v4l2-core modules already installed on the board.

## Design

Files are in `drivers/media/platform/rockchip/rkvenc/`. The module is `rockchip-venc.ko` and the
Kconfig option is `VIDEO_ROCKCHIP_VENC`. The file names use dashes (`rkvenc-*.c`) and so do not
collide with the out-of-tree `rkvenc_*.c` files.

| File | Content |
|---|---|
| `rkvenc.c` | Component master and core drivers, V4L2 m2m, formats, vb2, request API, core scheduling, IRQ, watchdog, reset and IOMMU recovery, runtime PM |
| `rkvenc.h` | Device, core and context structs; `struct rkvenc_codec_ops` (per-codec backend: `adjust_fmt/start/stop/run/done`) and `struct rkvenc_coded_fmt_desc` |
| `rkvenc-vepu580.c` | Codec-independent frame programming: control class, source picture/CSC/strides, bitstream ring, ME range and CIME cache sizing, row RC / fixed QP, the H.264 tuning blocks, and generation of the flat quantisation table |
| `rkvenc-h264.c` | H.264 backend on top of `v4l2-h264-enc`: `state_constrain`, FBC recon buffers, syntax registers, references, RC hookup, feedback |
| `rkvenc-regs.h` | Register and field definitions (MPP layouts, bit positions checked by hand) |

- **Multi-core.** There is one DT node per core (`rockchip,rk3588-vepu580`). The module creates a
  virtual master platform device that binds every available core as a component. This is the
  RGA/rkvdec pattern on this branch.
  - The video and media devices live on core 0.
  - Cores 1..n are attached to core 0's default IOMMU domain, so every vb2 and recon mapping is
    valid on both IOMMUs (the same approach as rkvdec multicore).
  - `v4l2_m2m_set_max_parallel_jobs(core_count)` and an idle-core bitmap give frame-level
    scheduling: one job per context, and contexts spread across idle cores. The dual-core
    handshake (DCHS) is off (`dual_core` = 0).
- **Per-frame flow.**
  1. `device_run` picks an idle core and applies the request's controls.
  2. It copies the timestamp to CAPTURE; the reference code keys recon buffers by timestamp.
  3. It calls `pm_runtime_resume_and_get`, then `ops->run`. For H.264 this runs
     `v4l2_h264_enc_step()`, which writes SPS/PPS/AUD into the CAPTURE buffer through the CPU
     mapping.
  4. A shadow register image (0x0000–0x2c9c) is built. `adr_bsbs` = CAPTURE base + header bytes,
     and `bsbt` = base + size − 1.
  5. Erratum: a per-frame force-clear, then the AXI counter is cleared. The classes CTL, frame,
     RC/KLUT, PARAM, RDO and SCL are written, the hardware watchdog is armed, and `enc_strt` is
     written.
  6. The threaded IRQ handler reads the status block, then `ops->done`: payload = header bytes +
     `bs_lgth`, then `v4l2_h264_enc_complete()`. It completes the request and finishes the job.
- **Errors.**
  - Any error bit (bits 4–9: overflow, bus, watchdog, link table) or the 1 s software watchdog
    marks the job as an error.
  - Recovery is the BSP sequence: safe clear (polling bit 2), then force clear. If the safe clear
    times out, the CRU reset is asserted (all three resets), followed by IOMMU re-init by
    attaching an empty domain and then the shared domain again.
  - Overflow is treated as an error. The vendor driver instead bumps the ring pointer, which
    corrupts the stream.
- **IRQ bits.** These follow MPP and the BSP `mpp_rkvenc2.c` (develop-6.1), which agree: done
  = 0, sclr_done = 2, slc_done = 3, bsf_oflw = 4, brsp_otsd = 5, wbus = 6, rbus = 7, wdg = 8. This
  confirms §6.4 of the programming-model doc: the out-of-tree port's BIT(1)/(2)/(4)/(5) defines are
  wrong.
- **Watchdog.** The BSP table is used (50/100/200/400/800 ms by picture size), with the BSP units
  (`ms * core_rate/256000`). The out-of-tree port uses `/1024000`. The BSP units give the longer
  timeout if they turn out to be wrong.

## Implemented features (v1)

- **Coded format.** CAPTURE `V4L2_PIX_FMT_H264_SLICE`, the coded format the series uses. It is
  one access unit per buffer, Annex-B only: `V4L2_CID_STATELESS_H264_START_CODE` is fixed to
  ANNEX_B because the hardware writes start codes.
- **OUTPUT formats.** NV12, NV12M, NV21, YUV420, YUV420M, YUYV, UYVY.
  - Luma stride is aligned to 16 bytes. The allocation covers the 16-aligned height.
  - Size is 64x64 to 4096x4096, in steps of 2. Wider than 4096 needs the external line buffer or
    SRAM (`ebuft/ebufb`, (aw-3072)/64*480 bytes); not done.
- **H.264 profiles and tools.** Baseline / Main / High, CAVLC and CABAC (with `cabac_init_idc`),
  8x8 transform (High), constrained intra, deblocking control (idc, alpha/beta offsets), and chroma
  QP offsets (`cb/cr_ofst`; `CHROMA_QP_CR_OFFSET` is set).
- **Frame types.** I (IDR or non-IDR) and P, with one reference. `state_constrain` forces
  `max_num_ref_frames` = 1, `num_ref_idx` = 0 and no override. POC type 0 is required by the core.
  It also forces frame_mbs_only, 4:2:0 8-bit, and drops field flags.
- **Marking.** Sliding window only. `no_output_of_prior_pics` and `long_term_reference_flag` are
  set on IDR. The MMCO and reordering registers are left at zero.
- **Recon/ref buffers.** These are driver-internal and managed by `v4l2-h264-enc` (indexed by
  slot, keyed by timestamp). Each is an FBC header+body plus a 1/4 thumbnail, using MPP's sizes.
  The thumbnail is rounded up rather than truncated. Non-reference frames are written to the
  current slot and dropped.
- **Rate control.**
  - Direct QP (`FRAME_RC_ENABLE` = 0, I/P QP controls) and CQ (`CONSTANT_QUALITY`) set a fixed
    frame QP: min = max = QP, row RC off.
  - CBR: the common RC's frame size target becomes `ctu_ebit` = target_bits×16/MBs. The hardware
    row RC is enabled with ±2 QP per row, 9-bucket deviation thresholds {-4p, -p, p, 4p} where
    p = 5/16 of a row's bits, ΔQP {-2,-1,0,1,2,0,0,0,1}, AQ on, and min/max from the controls.
  - The per-row QP range is the `row_rc_qp_range` module parameter (0644, default 2; 0 =
    frame-level RC only).
  - The hardware average QP is **not** fed back into the frame-level statistics. On the board,
    feeding it back made CBR spiral down to QP 11 and overshoot about 7x. With adaptive
    quantisation the average sits a few QP below the frame QP, and each frame's estimate
    starts from that lower value.
  - The MPP sign of the ΔQP table was checked against an inverted variant: at the same bitrate
    the MPP sign gives 0.8–1.2 dB better PSNR.
  - VBR is masked out of the menu; the series has no VBR mode.
- **Feedback.** `V4L2_CID_MPEG_VIDEO_AVERAGE_QP` (read-only) is updated per frame and captured in
  the request at completion. It comes from the hardware `qp_sum`, not from the RC state.
  - So it does not have the stale-QP problem the VEPU121 agent found in Paul's v1: there,
    ENCODE_PARAMS is published in `state_commit` before `rc_step` sets `slice_qp_delta`.
  - `slice_qp_delta` read back from ENCODE_PARAMS is still stale with this driver. The fix
    belongs in the helper. Adapted SPS/PPS/ENCODE_PARAMS are written back by the core, as the
  series does. Buffer flags are KEYFRAME / PFRAME.
- **Other controls.** `PREPEND_SPSPPS_TO_IDR`, `AU_DELIMITER`, VUI SAR, and frame rate via
  S_PARM (VUI timing).
- **Tuning.** RDO lambda, chroma KLUT, AQ, intra/ATR thresholds, CIME/RIME/FME, RDO intra/skip
  weights and the quant dead zone use MPP's H.264 defaults (default, non-IPC scene mode). They are
  written as named fields and formulas:
  - The chroma weights are stored unpacked (≈16·2^(k/3)) and packed at run time.
  - The flat scaling-list block (576 words) is generated from the H.264 8x8 quantisation
    multipliers. Its layout was reverse-engineered from MPP's table and checked against 5 sampled
    ranges: groups of 6×64 (value, low byte, high byte).

### Not done / limitations

- Multi-slice. The `sli_splt` registers exist; the series has no multi-slice control yet.
- Scaling matrices, MMCO/LTR beyond IDR, reordering, POC type ≠ 0, ROI/qpmap, OSD, rotation and
  mirroring, RGB input, AFBC input, and >4096 width.
- DCHS frame-parallel encoding of one stream on two cores.
- Average QP and frame size are the only feedback exposed. SSE, MADI/MADP, intra block count and
  cycles are read into `struct rkvenc_feedback` but not exported.
- The BSP wraps the CRU reset in a PMU idle request. Mainline has no API for that, so it is
  omitted.

## HEVC TODO (references to `~/orangepi5/docs/vepu580-programming-model.md`)

1. **uAPI.** Wait for or align with the sibling agent's HEVC stateless-encode uAPI, and add a
   `v4l2-hevc-enc` core equivalent to `v4l2-h264-enc`: VPS/SPS/PPS RBSP writer, short-term RPS
   for a single reference, POC.
2. **Format descriptor.** Add `rkvenc_hevc_fmt_desc` to `rkvenc_coded_fmts[]` and
   `rkvenc-hevc.c` implementing `rkvenc_codec_ops`. The common code needs no change for single-tile
   HEVC.
3. **Registers.** `enc_pic.enc_stnd` = 1, `log2_ctu_num`, `num_pic_tot_cur` (§1.2.2). HEVC syntax
   registers `reg0237..0245` (§2.5); their offsets are UNVERIFIED, so fetch them from
   `hal_h265e_vepu580_reg.h`. Inline st-RPS (num_negative_pics=1, delta_poc_s0, used_by_s0),
   SAO, TMVP, sign data hiding, cu_qp_delta, deblocking/LF-across flags, merge candidates.
4. **Buffers (§2.2).**
   - FBC sizes per CTU: cw=ceil(w/64), ch=ceil(h/64)+1, header ALIGN(cw*ch*64, 8K),
     body cw*ch*4096*3/2, thumb cw*ch*256.
   - Collocated MV buffer `cmvw/cmvr` ALIGN(cw*ch*96, 256), stored with each recon (`colmv` is
     already in `struct rkvenc_rec_buf`). Set `me_cfg.colmv_stor/load`.
5. **Rate control.** `rc_ctu_num` = CTU columns. The HEVC dthd table is {2n, n, p, 2p} (§4.1),
   and `vepu580_setup_row_rc()` needs a parameter for it. md_sad/madi thresholds are 20/30/40,
   `madi_thd` = 25.
6. **Tuning.** HEVC tuning blocks: the RDO cu64/cu32/cu16/cu8 inter/skip/intra thresholds
   (0x2004–0x21e4, layout in `Vepu580RdoCfg`), `iprd_wgt_qp_hevc` and the HEVC lambda tables,
   pre-intra, smear, segment. The values are in `hal_h265e_vepu580.c` / `_tune.c`. The HEVC
   scaling-list block (0x2200–0x2c98) needs the 16/32 tables.
7. **Temporal ID.** The hardware cannot emit TemporalId ≠ 0 (§3), so restrict the uAPI to
   TemporalId 0 or patch the NAL header in the kernel.
8. **Tiles.** Width > 4096 likely needs tiles (§1.4, UNVERIFIED). Tiles need per-tile
   `lpfw/lpfr` buffers and per-tile bitstream buffers with a kernel memcpy. Defer.

## Build and checks

The build uses the brief's commands, in `~/orangepi5/build/wt-rkvenc-7.3`. `.config` is the
board's config plus `CONFIG_VIDEO_ROCKCHIP_VENC=m` (which selects `V4L2_H264_ENC=m`).
`kernelrelease` = `7.3.0-opi5`.

| Check | Result |
|---|---|
| `M=drivers/media/v4l2-core` modules | OK, no warnings |
| `M=drivers/media/platform/rockchip/rkvenc W=1` | OK, 0 warnings |
| `M=drivers/media` (all media modules, needed for the ABI change) | see "Deploy" |
| `checkpatch --strict` on the 3 new commits | clean apart from the expected missing Signed-off-by (brief rule), `Co-Authored-By` spelling, and the MAINTAINERS reminder |
| `dt_binding_check DT_SCHEMA_FILES=rockchip,rk3588-vepu580.yaml` | clean |
| `CHECK_DTBS=y rockchip/rk3588s-orangepi-5-sata.dtb` | clean, no warnings |
| sparse | not installed |
| test client `tools/rkvenc-enc` | cross-built, -Wall -Wextra clean |

## ABI / deployment

On their own, Paul's uAPI patches change `union v4l2_ctrl_ptr` / `enum v4l2_ctrl_type`, and with
them the CRCs of 86 `videodev` and 3 `v4l2-flash-led-class` exports. Without a workaround, all
763 modules that link these exports would have to be replaced; the first build of this branch
measured that.

The VEPU121 agent's DO-NOT-UPSTREAM commit (cherry-picked here) avoids it. With it:
- the CRC diff against the board kernel's `Module.symvers` is **0**;
- the CRC diff against the VEPU121 build's `v4l2-h264-enc*` symvers is **0**;
- `v4l2_m2m_set_max_parallel_jobs` is already exported by the board kernel.

| .ko | Action |
|---|---|
| `rockchip-venc.ko` | **new**. It is the only module this driver needs. `deploy/rockchip-venc.ko`, signed (`modinfo -F signer` = "Build time autogenerated kernel key"), vermagic `7.3.0-opi5`. Depends on `v4l2-mem2mem, videobuf2-v4l2, videodev, mc, v4l2-h264-enc, videobuf2-dma-contig, videobuf2-common, v4l2-h264-enc-rbsp` |
| `videodev.ko`, `v4l2-h264.ko`, `v4l2-h264-enc{,-rbsp,-rc}.ko` | unchanged. The ones installed by the VEPU121 agent are used, built from identical sources |

The module is installed on the board as `/lib/modules/7.3.0-opi5/updates/opi5-venc/rockchip-venc.ko`.
It is the final build, with sha256 in `deploy/SHA256SUMS`. It was installed with depmod and a
reboot, and never rmmod'ed.

DT: `dt/0001-arm64-dts-rockchip-Add-the-VEPU580-encoder-cores-to-.patch` touches only
`rk3588-base.dtsi` (2 cores and 2 IOMMUs). It applies cleanly on `opi5/board-dt`.

Without the DNU commit, i.e. a full kernel rebuild with the real uAPI, the whole module tree has
to be rebuilt. A drivers/media rebuild with the CRC-changing core was tested and builds cleanly
(`M=drivers/media`, exit 0).

## Board test results (2026-10-29, Orange Pi 5, kernel 7.3.0-opi5 16:45 build)

Raw logs: `board-run1.txt` (first module) and `board-run2.txt` (final module). The input is
ffmpeg `testsrc2` NV12: 300 frames at 1080p and 60 frames at 4K, at 30 fps. PSNR is measured by
decoding the stream with ffmpeg and comparing frame by frame (`tools/psnr.sh`).

| Test | Result |
|---|---|
| Probe | `registered encoder core 0` (fdbd0000) and `core 1` (fdbe0000), both bound to the master. One video node (found by name: /dev/video6 or /dev/video11 depending on boot) and one media node. IOMMU groups created for both |
| v4l2-compliance 1.32 | 44/49 OK, **0 warnings** after the bus_info fix. The 5 failures are v4l2-compliance not knowing stateless encoders: ENUM_FRAMEINTERVALS and S_PARM are accepted only for stateful encoders, and the aborted ENUM_FMT test then makes G/TRY/S_FMT report "format not reported". `Requests` shows "Not Supported" because the tool doesn't test requests on encoders |
| 1080p I-only QP 22/27/32/37 | 15.9/11.8/8.4/5.6 Mbit/s; PSNR(avg) 52.5/47.7/43.3/39.7 dB; 0 decode errors; ~260 fps |
| 1080p GOP 30 QP 22/27/32/37 | 12.4/8.7/5.8/3.4 Mbit/s; 51.9/47.2/42.9/39.0 dB; 0 errors; ~264 fps. P frames are ~36 KB vs ~46 KB for I at QP 27, which matches x264 `-qp 27 -g 30 -bf 0 -refs 1` on the same content (~37 KB P frames) |
| 4K I-only QP 22/27/32/37 | 56.9/41.8/28.6/17.8 Mbit/s; 53.2/48.2/43.6/40.2 dB; 0 errors; **70.8 fps** |
| 4K GOP 30 QP 22/27/32/37 | 50.1/35.1/22.8/13.0 Mbit/s; 52.4/47.6/43.0/39.6 dB; 0 errors; 70.7 fps |
| CBR 1080p, targets 2 / 4 / 8 / 20 Mbit/s | 1.94 (−3%) / 3.88 (−3%) / 7.28 (−9%) / 16.5 (−17%; QP hits the client's min QP of 10) Mbit/s. With the row RC off (`row_rc_qp_range=0`): 1.98 / 3.79 / 7.74 Mbit/s |
| CBR 4K (only 60 frames, 2 GOPs) | 2 → 4.5, 8 → 6.8, 20 → 17.3 Mbit/s. The RC has too few frames to converge, and 2 Mbit/s at 4K needs QP > 51 |
| Profiles 66/77/100, High+CAVLC | ffprobe reports Baseline/Main/High; all decode cleanly |
| 2 parallel 4K streams | 68.5 + 70.5 fps = 139 fps combined (≈ 2× one stream). IRQ counters: core 0 +60, core 1 +60. Both outputs decode cleanly and have the same size as the single-stream run (8769313 bytes) |
| Runtime PM | both cores `suspended` 2 s after the last job |
| dmesg | clean: no IOMMU faults, no encode errors, no timeouts |

Fixed during the board session (squashed into the driver commit):
1. The media `bus_info` did not match the V4L2 one ("platform:rockchip-venc" vs
   "platform:fdbd0000.video-codec").
2. CAPTURE buffers are now completed before the OUTPUT buffer. Before, the request could
   signal completion before the CAPTURE buffer was dequeueable, so the client saw EAGAIN once
   in 20 runs.
3. CBR spiralled down to QP 11 and overshot 7x because the average QP was fed back into the
   statistics. That feedback is removed, and the `row_rc_qp_range` parameter was added.

**Deferred: risky, not to be run without the user present.**

| Step | Risk | Why |
|---|---|---|
| Force a bitstream overflow (tiny CAPTURE buffer) | medium | exercises the error IRQ, safe clear and possibly the CRU reset + IOMMU re-attach path |
| Watchdog/timeout recovery | high | can wedge the core or its IOMMU |
| rmmod/modprobe cycles | high | exercises the component unbind and remove paths |
| Replacing v4l2-core without a reboot | high | modules in use |

## Open problems and risks

1. **Confirmed on hardware:**
   - P frames work with the MPP FBC layout.
   - Software headers at an unaligned `adr_bsbs` work.
   - The generated flat scaling tables give PSNR in line with x264.

   **Not exercised:** the error/reset/IOMMU-recovery paths (deliberately deferred), and source
   widths that are not multiples of 16.
2. **CBR accuracy.** CBR is about −3% at moderate rates and undershoots at high rates where
   `qp_min` binds. Paul's helper CBR needs about 2 GOPs to converge. The hardware row RC
   trades ~0.1 dB PSNR for adaptive quantisation on synthetic content.
3. **Possible bugs in the helper series (Paul v1), not fixed here so the patches stay identical:**
   - `rbsp_update()` compared the old and new SPS/PPS only for the first frame, so every later
     frame got SPS+PPS again. This is fixed by the VEPU121 agent's commit cadb459da, included
     here.
   - `ref_complete_slot_find()` uses an unsigned `FrameNumWrap` and an uninitialised index when
     frame_num wraps without an IDR in between. The client avoids this with
     log2_max_frame_num = 16 and a GOP shorter than 65536.
4. **Collabora.** Their Vulkan-Video/Rust KMD plan for this block conflicts with a V4L2 driver
   (survey §2). Nothing is to be sent upstream before talking to them.
5. **MAINTAINERS.** No entry added; it needs a maintainer name.
6. **Unbind with open file handles.** A sysfs unbind of a core, or a core probe deferral, while
   the device is open would free the m2m device under the open contexts (use-after-free).
   - rkvdec and RGA share the same pattern.
   - Master unbind now drains running jobs with `v4l2_m2m_suspend()`.
   - A proper fix needs refcounted lifetime: free from `vdev.release`.
   - Never unbind or rmmod on the board.
7. **Independent review.** A fresh-eyes review found these bugs, and they are fixed in the
   driver commit:
   - the core was released before the job's buffers were finished (a race with another
     context's `device_run`);
   - a P frame without a reference;
   - a NULL vaddr / DMABUF header flush problem (CAPTURE is now MMAP only);
   - control races (OUTPUT now requires requests);
   - format changes after start;
   - the WARN-path request completion;
   - bind error state;
   - system sleep with a running job (the master pauses the m2m queue);
   - mbs == 0.
