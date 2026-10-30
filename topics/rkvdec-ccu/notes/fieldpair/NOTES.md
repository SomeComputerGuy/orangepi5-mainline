# rkvdec CCU: overlap the two fields of an interlaced H.264 frame

Branch `opi5/rkvdec-ccu-fieldpair` (worktree `work/rkvdec-ccu-fieldpair`) = `opi5/rkvdec-ccu-k4` + 2 commits
(`patches/0001-0002`). Modules in `modules/` (signed, `modules/BUILT-FROM`), built in
`build/wt-rkvdec-ccu-fieldpair` with build/linux's config, Module.symvers and key, W=1, no warnings.
Not installed, not board-tested.

## Design

**v4l2-mem2mem (`0001`)**: `v4l2_m2m_buf_detach_and_job_finish()` now also detaches a job whose OUTPUT buffer
has `V4L2_BUF_FLAG_M2M_HOLD_CAPTURE_BUF`: the src leaves the ready list (driver owns it), the dst *stays on the
CAPTURE ready list with `is_held`*, exactly as after `v4l2_m2m_buf_done_and_job_finish()`, and the context gets
a new internal job flag `TRANS_HELD_DETACHED` ("detached jobs still write the held buffer"). New export
`v4l2_m2m_detached_buf_done(m2m_ctx, vbuf, state)`: the driver calls it once all detached jobs writing `vbuf` are
done; if `vbuf` is still held it clears the flag and leaves the buffer to the framework (returned on the next
hold release, DONE, as today); otherwise it returns it with `state`.
While the flag is set, every place that releases a hold (timestamp mismatch in `__v4l2_m2m_try_queue()`,
`V4L2_DEC_CMD_FLUSH` with no OUTPUT pending, `v4l2_m2m_buf_done_and_job_finish()` of a non-HOLD job) only takes
the buffer off the ready list and clears the flag; `v4l2_m2m_detached_buf_done()` returns it later. A non-HOLD
job that is detached takes the held buffer over (removed, flag cleared). So the capture buffer completes when the
last job writing it is done *and* the hold is released, whichever is last.

The reference count lives in the driver (it knows which jobs write which buffer); m2m only needs one bit,
because a context has at most one held buffer (the head of the CAPTURE queue).

**rkvdec (`0002`)**: HOLD jobs are detached like the others (`rkvdec_job_started()` no longer special-cases
them); `rkvdec_job_ready()` lets a job with a held dst (second field) start while jobs are in flight, and a
first field after the previous frame goes through the normal "dst still a reference of an in-flight job" check.
In-order completion: when a job completes and a later in-flight job writes the same dst, only its src is
returned and the later job is marked `dst_shared` (+ `dst_error` if it failed); the last one calls
`v4l2_m2m_detached_buf_done()` (dst first, then src: request order kept). Jobs are registered (incl.
`job->src/dst`) under `ctx->done_lock`, which completion holds across "is another job using this dst?" +
`v4l2_m2m_detached_buf_done()`, so a second field can't be registered and take the buffer over in between.

## Invariants

- Drivers that never detach (hantro, cedrus, visl, rkvdec on other SoCs if they ever use the old path): the flag
  is never set, all hold paths behave exactly as before. uAPI unchanged (no doc change needed in
  dev-stateless-decoder.rst / buffer.rst / vidioc-decoder-cmd.rst).
- No structure changed (flag is a new bit in `job_flags`, a private `#define`). The 58 existing v4l2-mem2mem
  export CRCs are identical to `build/linux/Module.symvers` (checked); 2 exports differ from build/linux:
  `v4l2_m2m_buf_detach_and_job_finish` (already in the k4 build), `v4l2_m2m_detached_buf_done` (new).
- `is_held` is true only for the buffer at the head of the CAPTURE queue; all release paths clear it.
- Streamoff: rkvdec's stop_streaming waits for all jobs (which complete/put their buffers) before cleanup;
  `v4l2_m2m_streamoff()` resets `job_flags` afterwards.
- Lock order: done_lock -> job_spinlock -> cores_lock (job_ready runs under job_spinlock and takes cores_lock;
  completion never calls m2m with cores_lock held).
- RK3399/non-CCU: HOLD jobs now detach instead of keeping the m2m job, so with several cores another stream can
  use the other core during a field; user-visible behaviour identical.

## Hardware evidence (does the CCU sync field 2 reading field 1 of the same buffer?)

Indirect but consistent; no document says it in words:
- MPP `hal_h264d_vdpu34x.c` (used on RK3588) sets `support_fast_mode = 1`; `mpp_dec_cfg.c` defaults
  `fast_parse = 1`. In fast mode `mpp_dec_normal.c` skips "wait previous task done" (step 7.1); the only extra
  wait (`dec_all_done`) is set by VP9 alone (`wait_done`). Each field picture is its own task with the same output
  slot, and the second field's DPB lists the current slot as reference (`h264d_init.c` refer[]).
- BSP `mpp_rkvdec2_link.c` `rkvdec2_soft_ccu_worker()`: takes pending tasks in order and starts each on any idle
  core (`rkvdec2_get_idle_core()`), no dependency or same-buffer check; completion in order.
  => the vendor's default production path decodes the two fields of a frame on two cores at the same time and
  relies on the cores' sync.
- What tells the fields apart: MPP programs, for field pictures, `cur_poc_highbit` = parity (reg204) and the
  reference POC high bits 0 (top) / 1 (bottom) per DPB entry; the cores match references by film index + POC +
  high bit, not by address. Our commit `program the H.264 POC high bits` does the same.
- Unverified: whether the co-located MV read of field 2 (direct mode, colmv of field 1) is synced as well
  (`colmv_req_advance_flag` exists; the vendor path relies on it identically). The board test will show it.

## Board test plan (coordinator)

1. Install `modules/*.ko` to `updates/opi5-rkvdec-ccu/` (both modules, they go together), depmod, reboot or
   reload; CCU overlay DTB as for k4.
2. `cat /sys/module/rockchip_vdec/parameters/stat_overlap` -> note; then `~/ccu/fluster.sh ccu JVT-AVC_V1 JVT-FR-EXT`.
   Pass: >= baseline 129/135 (AVC_V1) and 65/69 (FR-EXT), same failing vectors as the baseline; no "Frame
   processing timed out", IOMMU faults or WARNs in dmesg.
3. Overlap actually happens for fields: stat_jobs/stat_overlap are read-only, so diff them around the run;
   decode one field-coded vector alone (e.g. CVFI1_Sony_D, CVPA1_TOSHIBA_B, CVSE3, camp_mot_fld0_full,
   cvmp_mot_fld0_full) with fluster `-j1`: stat_overlap should grow by about the number of field pictures
   (with the k4 build the two fields of a frame never overlapped).
4. A/B: `pipeline=0` / `ccu_hw=0` must still pass (serial paths).
5. If field streams fail only with this build: suspect colmv sync for direct-mode field 2; the fallback is to
   return 0 in `rkvdec_job_ready()` for `dst->is_held` (serial field pairs) while keeping the m2m change.
