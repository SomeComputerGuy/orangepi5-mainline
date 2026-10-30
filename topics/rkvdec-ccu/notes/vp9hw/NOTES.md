# VDPU381 VP9: hardware probability adaptation + CCU pipelining

Branch `opi5/rkvdec-ccu-vp9hw` (worktree `work/rkvdec-ccu-vp9hw`) = `opi5/rkvdec-ccu-k4` + 2 commits:

- `0001` media: rkvdec: vdpu381: adapt the VP9 probabilities in hardware
- `0002` media: rkvdec: vdpu381: decode VP9 on both RK3588 cores with the CCU

Build `build/wt-rkvdec-ccu-vp9hw` (build/linux config, Module.symvers, signing key), W=1 clean,
checkpatch --strict clean on both commits. `rockchip-vdec.ko` + `v4l2-mem2mem.ko` here are signed and
built from HEAD (includes the DEBUG A/B patch of the k4 branch, so `ccu_hw`/`pipeline`/`cache`
module parameters still work); `v4l2-mem2mem.ko` symbol CRCs are identical to `k4/`.
**Nothing here has run on the board.**

## Design

Before: the CPU did forward updates + backward adaptation (`v4l2_vp9_fw_update_probs()` in run,
`v4l2_vp9_adapt_*()` in `done()` from the hardware symbol counts), so frame N+1 could only be set up
after N was done, and VP9 ran with the core disconnected from the CCU.

After (0001), per stream (`struct vdpu381_vp9_stream_tbl`, one coherent allocation):
- `default_probs`: VP9 default probabilities (spec 10.5) in the hardware frame-context layout,
  written once at stream start.
- `ctx_probs[4]`: one buffer per VP9 frame context, written only by the hardware
  (`prob_save_en` = refresh_frame_context, `refresh_en` = !error_resilient && !frame_parallel).
- `segmap[2]`: the two segment-ID maps used in turn (unchanged logic).

Per job slot (`struct vdpu381_vp9_job_tbl`, `ctx->job->slot`, `ctx->num_job_slots` of them):
- `updates`: flag bits + update values of the compressed header (intra or inter layout).
- `counts`: symbol counts the hardware writes (unused by the CPU now).

Per frame the driver: picks the frame context (setup_past_independence of the spec; reset contexts
are marked "not saved" and read from `default_probs`), points reg162 (last_prob_base) at the saved
context or the default table, reg172 (update_prob_wr_base) at the context, reg160 at the job's update
table, reg167 at the job's count buffer, reg028 rd/wr_prob_idx = ctx+1 (rd 0 for the default table),
reg103 as MPP. All "last frame" state is updated at run time (was in `done()`); `.done` is gone.

0002: per-stream frame counter 1..0xffff (0 = none) stored in the CAPTURE buffer
(`rkvdec_decoded_buffer.vp9.poc`): reg065 cur POC, reg095-097 ref POCs (0 for missing refs and for
intra frames), reg098 POC of the buffer whose MVs are read (cur POC when it is the dst), reg099 POC of
the last writer of the frame context read (only when reading a saved one), reg100 POC of the last
frame that coded a segment map (0 for frames that code one). Refs and the MV buffer are recorded
with `rkvdec_job_add_ref()`; `RKVDEC_FMT_FLAG_PIPELINE` set for VP9, so it runs in CCU mode with
`min(cores, 2)` job slots.

## Mapping to MPP (reference only, nothing copied)

| Driver | MPP |
|---|---|
| `vdpu381_vp9_write_intra/inter_updates()` | `hal_vp9d_prob_flag_delta()` (hal_vp9d_com.c) |
| `vdpu381_vp9_update_index()` (V4L2 inv_map_table[] value -> coded index) | `vp9d_diff_update_prob()` `*delta = delp` (vp9d_codec.c); MV updates passed as is (vp9d_parser.c) |
| `vdpu381_vp9_write_default_probs()` | `hal_vp9d_prob_default()` + `TRANS_TO_HW_STYLE` / partition reorder of `vp9d_fill_picparams()` |
| `config_prob_registers()` | `HW_PROB` block of `hal_vp9d_vdpu34x_gen_regs()`: `prob_ctx_valid`, `prob_loop_base[4]`, `prob_default_base`, reg103, rd/wr_prob_idx, `prob_ref_poc[]` |
| frame counter POC | `vp9_alloc_frame()` `cur_poc` 1..0xffff (vp9d_parser.c) |
| reg095-098, reg100, segmap swap | "set info for multi core" block of `hal_vp9d_vdpu34x_gen_regs()` (`col_ref_poc`, `segid_ref_poc`, `last_segid_flag`) |
| per-job update/count buffers | `g_buf[i].probe_base` (fast mode), count at `VDPU34X_OFFSET_COUNT` |

Deliberate deviations from MPP (all in commit messages):
1. Frame context resets follow the spec: MPP invalidates all 4 contexts on *every* intra frame; the
   spec keeps them for intra-only frames with reset_frame_context 0/1 (frame uses context 0, which may
   be a hardware-saved one). Affects `vp90-2-16-intra-only.webm`-type streams.
2. reg103 `last_key_frame_flag` = previous frame was a key frame (spec 8.4.3 update factor); MPP uses
   "previous frame was intra" (differs only after an intra-only frame).
3. reg099 bookkeeping: MPP updates `prob_ref_poc[ctx]` only when !frame_parallel_mode; the driver also
   records a frame-parallel frame that saves the context (refresh_frame_context=1), so the next reader
   waits for it. Only adds synchronisation. To get MPP's behaviour: `if (!parallel)` in
   `config_prob_registers()`.
4. reg098 is the POC of the buffer actually used for the previous-frame MVs (previous decoded frame,
   unchanged selection logic); MPP uses the last *shown* frame. Same when the hardware uses the MVs.
5. Not ported (not needed for VP9 decoding before, unknown for CCU): reg181-183 per-ref colmv bases,
   reg013 cur_pic_is_idr, colmv compression, MPP's `lasttile_size` in reg078.

## Host validation

`harness/` (`./build.sh && ./vp9tbl 10000`): extracts the MPP table writers and the driver's table
writers at build time into `harness/gen/` (local only, not for distribution) and compares their
output byte for byte for random compressed headers (intra/key/intra-only/inter, all tx modes,
reference modes, switchable filter, hp, update densities 0/3/30/100%), plus the default table and the
inverse of inv_map_table for all 254 indices. Result: 10000 iterations, 0 failures.
Known by-design difference: coded index 254 (also maps to 253) is sent as 253; the hardware's table
should map both to 253 (as libvpx/ffmpeg do).

## Risks / unverified

- Everything hardware-side is unverified: the hardware path in serial mode, CCU synchronisation, and
  whether MPP's register semantics transfer 1:1 (reg099/100 are 16-bit fields as in mainline; MPP
  uses full words, values never exceed 0xffff).
- reg100 = 0 for a frame that codes a new map *with temporal prediction* (reads the previous map):
  as MPP; if that races in CCU mode, set reg100 to the previous `segmap_poc` when
  `V4L2_VP9_SEGMENTATION_FLAG_TEMPORAL_UPDATE` is set.
- Two segment maps are shared by in-flight frames (as in MPP); a non-updating frame may write
  segidcur concurrently with the next updating frame writing the same buffer.
- Frame-parallel streams may pipeline less (deviation 3).
- Hardware errors: a frame that fails still leaves whatever the hardware saved in its context; no
  recovery until the next key frame (same as MPP; before, the CPU skipped adaptation on error).
- The "last frame" and frame-context state is now updated when a frame is set up. The only
  failure in `rkvdec_vp9_run()` (validate_dec_params()) happens before any state changes.

## Board test plan

Install the two modules like `k4/install-k4.sh` does (to `updates/opi5-rkvdec-ccu/`, depmod, CCU
overlay in the DTB), reboot, then:

1. `~/ccu/ccu-verify.sh` — VP9 600-frame 4K bit-exact vs FFmpeg (framemd5) and fps, in every mode.
   Pass: 600/600 with `ccu_hw=1 pipeline=1` (was 0/600), fps > 138.5 (serial baseline), `stat_overlap`
   > 0 during VP9, no timeouts/IOMMU faults. Also check `ccu_hw=0` (serial, hardware adaptation
   alone): 600/600 — if this fails, the problem is in 0001 (tables/reg103), not the CCU.
2. `~/ccu/fluster.sh ccu VP9-TEST-VECTORS` — baseline 230/305; must not regress. Compare the
   failing list with the baseline one; the vectors most exposed to this change are the intra-only
   ones (deviations 1/2), segmentation, frame-parallel / error-resilient, and resize ones.
3. If CCU mode fails but serial passes: try deviation 3 reverted (MPP behaviour), then reg100 for
   temporal updates, then `pipeline=0` with `ccu_hw=1` to separate POC programming from overlap.
