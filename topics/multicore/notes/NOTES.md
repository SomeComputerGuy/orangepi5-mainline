# rkvdec + RGA3 multi-core — status 2026-10-29

## Branches
- `opi5/multicore` (base c339f4010, 7.4 merge window): RGA multi-core v2 (s.pueschel, 2026-09-16)
  + rkvdec multi-core v2 (Detlev Casanova, 2026-08-10) patches 1,2,4,5. Patch 3/5 (export
  v4l2_m2m_set_max_parallel_jobs) is already in the RGA series. Patch 4 hand-merged (note in commit).
- `opi5/multicore-7.3` (worktree work/multicore-7.3): same 21 commits on v7.3, preceded by a local-only
  commit syncing rga/ and rkvdec/ to c339f4010. Used to build drop-in modules for the board's 7.3.0-opi5.
- An earlier agent's abandoned half-applied patch is saved as abandoned-partial-patch3.diff (superseded).

## Deployed on the board (out-of-tree, reversible)
/lib/modules/7.3.0-opi5/updates/opi5-multicore/{v4l2-mem2mem,rockchip-vdec,rockchip-rga,hantro-vpu}.ko,
built against build/linux's .config + Module.symvers, signed with its key. Kernel shows "loading
out-of-tree module taints kernel". Undo: `sudo rm -r /lib/modules/7.3.0-opi5/updates/opi5-multicore &&
sudo depmod -a && reboot` (or modprobe -r/modprobe the four modules).

## Results (synthetic testsrc2 clips, decode-only, fakesink)
| 4K HEVC streams in parallel | stock      | multi-core |
|-----------------------------|------------|------------|
| 1                           | 105 fps    | 105 fps    |
| 2                           | 111 total  | 202 total  |
| 4                           | 129 total  | 206 total  |
- 4x parallel 4K HEVC and 2x parallel 4K H.264: bit-exact vs FFmpeg software; both cores' IRQs advance.
- RGA3: both cores bound into one /dev/video node; 4 parallel NV12->BGRx jobs OK, IRQs on both cores.
- v4l2-compliance unchanged vs stock (rkvdec 47/49, same 2 failures pre-exist).
- No IOMMU faults / timeouts in dmesg.

## Issues found
- Pre-existing, not multi-core: GStreamer's default `v4l2slh264dec` binds Hantro G1 (<=1080p), so 4K
  H.264 fails with "Failed to configure H264 decoder" unless rkvdec's element (`v4l2slvideoNh264dec`, N =
  rkvdec's node number, which moved from 2 to 0 with the multi-core driver) is used. decodebin may pick
  Hantro too. Fix options: rank override (GST_PLUGIN_FEATURE_RANK), or not exposing H.264 on the
  RK3588 VDPU121 in the kernel.
- RGA prints "HW Version: 0x00.00" for the first-bound core (version read before the core is powered?) —
  cosmetic, worth reporting to the series author.
- Hantro VEPU121 JPEG encoder is still single-core (no series exists).
- Untested: 8K, long runs, runtime-PM idle cycling, module unload under load.
