# rkvdec HEVC SPS RPS fixes: board test

Status 2026-10-29: compile-tested only. Nothing was run on the board and nothing was sent upstream.

## What is being tested

The fixes are on two branches with the same six commits:

| Branch | Base | Worktree | Patches |
|---|---|---|---|
| `opi5/rkvdec-hevc-rps` | `opi5/base` (c339f4010, the 7.4 merge window) | `work/rkvdec-hevc-rps` | `patches/` (with a draft cover letter) |
| `opi5/rkvdec-hevc-rps-7.3` | `opi5/integration-7.3` (1afa8d268 = `patches/linux`) | `work/rkvdec-hevc-rps-7.3` | `patches-7.3/` |

The files exist on `opi5/base`, and `rkvdec-hevc-common.c` is the same there as in
`integration-7.3`. The 7.3 copies differ only in context: `core->dev` instead of `rkvdec->dev`,
because of the multi-core series.

| # | Commit | Bug | Board test |
|---|---|---|---|
| 1 | Apply the request controls before reading them | `rkvdec_hevc_run_preamble()` read the control pointers, `num_slices` and the RPS pointers *before* `v4l2_ctrl_request_setup()`. Dynamic array pointers could be stale (freed when a request grows the array), RK3399 used another request's slice count, and the first request with RPS controls got no table | B, D (no regressions); not separately observable |
| 2 | Notice SPS RPS controls set to their current value | NOTES §7.3. The bug was not in rkvdec: the core never calls `s_ctrl` when the value equals the current one, so the `has_changed` test inside it never ran in that case. Fixed by making the controls EXECUTE_ON_WRITE | A |
| 3 | Don't read past the end of the SPS RPS controls | The SPS counts were never checked against the controls' element counts, so the table code could read past the array | none (needs a crafted client and KASAN) |
| 4 | vdpu383: Complete the request when rejecting a HEVC job | The `-EINVAL` path skipped `v4l2_ctrl_request_complete()`, so the request never completed | none (RK3576 only) |
| 5 | Rebuild the short-term RPS table when any set changes | NOTES §7.1: the cache held only set 0. The zeroed-cache case **does** show up in the conformance suite (see B) | B, C, D |
| 6 | Handle allocation failure of the short-term RPS sets | NOTES §7.2 | none (needs fault injection) |

## Files

| Path | What |
|---|---|
| `modules/before/rockchip-vdec.ko` | `opi5/integration-7.3` unchanged (rkvdec sources identical to `src/linux`, which `build/linux` is built from) |
| `modules/after/rockchip-vdec.ko` | `opi5/rkvdec-hevc-rps-7.3` |
| `modules/BUILT-FROM` | srcversion and sha256 of both |
| `scripts/build-dropin.sh` | host: rebuilds both modules against `build/linux`'s `.config`, `Module.symvers` and signing key (read only) |
| `scripts/board-hevc-rps.sh` | board: the whole test, A/B, restores the board's module at the end |
| `scripts/board-hevc-extsps.sh` | copy of `ffmpeg-hevc-extsps/board-hevc-extsps.sh`, for test C |
| `tools/spsdump.{c,sh}`, `tools/spsdump*-JCT-VC-HEVC_V1.txt` | host: dumps every SPS short-term set of the suite; used to choose the vectors below |

Both modules are vermagic `7.3.0-opi5`, signed with `build/linux`'s key
(`sig_key 0E:5A:3D:41:...:D1:6A`), and depend only on in-kernel modules.

## 0. Before you start

- The board must run the 7.3.0-opi5 kernel that `build/linux` was built from. Otherwise the module
  won't load (signature or symbol CRCs), and `board-hevc-rps.sh` stops when `modprobe` fails.
  To check:
  ```sh
  uname -r                                   # 7.3.0-opi5
  modinfo -F sig_key $(modinfo -n rockchip_vdec)   # same key as above
  find /lib/modules/$(uname -r)/updates -name 'rockchip-vdec.ko*' -o -name 'v4l2-mem2mem.ko*'
  ```
  If an `updates/opi5-*` directory has a **v4l2-mem2mem** drop-in, move it aside for the test as
  well: the modules were linked against the in-kernel v4l2-mem2mem. Other **rockchip-vdec**
  drop-ins are moved aside by `--move-others` and put back at the end.
- Nothing may hold `/dev/video*` of rkvdec (no browser, mpv or Jellyfin), because the script
  reloads the module.
- Userspace: gst-launch-1.0 with v4l2codecs, ffmpeg/ffprobe (software reference), python3,
  v4l2-ctl. Optional: strace, v4l2-compliance, the private fluster in `~/cq/flpkg`, and
  `/var/tmp/extsps/bin/ffmpeg-after` from `ffmpeg-hevc-extsps`.
- Vectors: JCT-VC-HEVC_V1 with one directory per vector. `work/_downloads/browser-hwdec/hevc-conf/x`
  and the fluster resources directory both work.

## 1. Run

```sh
# host
S="ssh -i ~/orangepi5/.ssh/opi5_ed25519 -o UserKnownHostsFile=~/orangepi5/.ssh/known_hosts"
rsync -a -e "$S" ~/orangepi5/work/_out/rkvdec-hevc-rps/ <user>@<board-ip>:/var/tmp/hevc-rps/
rsync -a -e "$S" ~/orangepi5/work/_downloads/browser-hwdec/hevc-conf/x <user>@<board-ip>:/var/tmp/hevc-rps/
# board (about 10 minutes; add --fluster for about 1-2 hours more)
cd /var/tmp/hevc-rps
./scripts/board-hevc-rps.sh x out --move-others --ffmpeg /var/tmp/extsps/bin/ffmpeg-after --fluster
cat out/summary.txt
```

`--variants after` runs only the fixed module. The script loads `before`, runs A-D, loads
`after`, runs A-D again, and then restores the board's own module, also when it fails. The
`out/<variant>/` directories hold `results.txt`, the logs, the strace files, `dmesg.txt`,
`ctrls.txt`, `v4l2-compliance.txt`, `ffmpeg/` and `fluster.md`.

## 2. Tests and expected results

### A. The default value counts as set (commit 2)

The script decodes IPRED_A_docomo_2, ipcm_A_NEC_3 and MAXBINS_A_TI_5 with GStreamer and counts
`Long and short term RPS not set` in the kernel log. Each of these streams has one SPS set, and it
is empty, so the first EXT_SPS_ST_RPS value is one all-zero element: the default.

| | before | after |
|---|---|---|
| warnings (rate-limited) | > 0 | **0** |
| `ctrls.txt`, the two RPS controls | `flags=has-payload, dynamic-array` (or similar) | the same plus `execute-on-write` |

The streams are intra-only, so the frames are correct in both cases; only the warning shows the
bug. If "before" also has 0 warnings, GStreamer didn't send the control for these streams, and
A tells you nothing.

### B. Frame-exact decode of SPS changes and empty first sets (commits 5, 1)

Every frame of the GStreamer decode (`h265parse ! v4l2sl…h265dec ! videoconvert dither=none !
I420`) is compared with FFmpeg's software decode of the same file.

Synthetic SPS-change streams: two 416x240 vectors concatenated, so the second half starts with a
new VPS/SPS/PPS and an IDR at the same resolution. In each pair, the first SPS set is the same in
both halves (`n4p0: -1,-5,-9,-13`) but most later sets differ
(`tools/spsdump-all-JCT-VC-HEVC_V1.txt`):

| Stream | First half | Second half | Sets that the old table gets wrong in the second half |
|---|---|---|---|
| SPSCHG_A | MVCLIP_A_qualcomm_3 (13 sets) | TSCL_B_VIDYO_4 (14) | 11: 1, 3, 5-13 |
| SPSCHG_B | TSCL_B_VIDYO_4 (14) | MVCLIP_A_qualcomm_3 (13) | 10: 1, 3, 5-12 |
| SPSCHG_C | WP_A_Toshiba_3 (13) | VPSID_A_VIDYO_2 (15) | 11 non-empty: 1, 3, 5-13 |
| SPSCHG_CTRL | MVCLIP_A_qualcomm_3 | MVEDGE_A_qualcomm_3 | none: identical sets (control) |

Conformance vectors whose first SPS set is empty, followed by non-empty sets. Before commit 5 their
first set compares equal to the zeroed cache, so the table is never built:
DELTAQP_A_BRCM_4 (8 sets), ENTP_A_Qualcomm_1 (2), OPFLAG_B_Qualcomm_1 (2). Controls: the five
halves on their own, RPS_A_docomo_5, POC_A_Bossen_3 (no SPS sets).

Each `results.txt` line is `PASS|FAIL name frames= bad= first_bad= (first half: N frames) STREAMON=k`.

| | before | after |
|---|---|---|
| halves alone, RPS_A, POC_A, SPSCHG_CTRL | PASS | PASS |
| SPSCHG_A/B/C | FAIL, `first_bad` ≥ first-half frame count | **PASS** |
| DELTAQP_A, OPFLAG_B, ENTP_A | FAIL from the first inter picture that uses an SPS set ≥ 1 | **PASS** |

The SPSCHG tests reproduce the bug only if userspace keeps streaming across the SPS change.
`STREAMON=2` (OUTPUT and CAPTURE once) shows that it did. With `STREAMON=4` GStreamer
renegotiated, which gives a new context and a fresh cache, so "before" can pass; then check test C,
or treat the SPSCHG result as inconclusive. ENTP_A could also fail for unrelated reasons (entry
points, slice header extension); it counts only if it passes with "after".

**Pass criteria for B:**
- every stream that passes with "before" passes with "after";
- with "after", all streams pass whose halves pass on their own;
- with "after", no `Long and short term RPS not set` line, no WARNING, Oops, KASAN or IOMMU fault
  in `dmesg.txt`.

### C. FFmpeg v4l2request with the RPS controls (optional, `--ffmpeg`)

This runs `board-hevc-extsps.sh` with the given FFmpeg on the same set: FFmpeg + patches/ffmpeg
0012, so the SPS sets come from FFmpeg's derived form. Expected: the same as B. FFmpeg may re-init
the hwaccel on an SPS change, and then the SPSCHG streams pass with "before" too.

### D. Whole suite with fluster (optional, `--fluster`)

`GStreamer-H.265-V4L2SL-RKVDEC JCT-VC-HEVC_V1 -j 1`, with the rkvdec H.265 element looked up after
each module reload.

**Pass criteria for D:**
- no vector that passes with "before" fails with "after" (compare the two `fluster.md`);
- expected gains: DELTAQP_A_BRCM_4, OPFLAG_B_Qualcomm_1, and possibly ENTP_A_Qualcomm_1 and
  VPSSPSPPS_A_MainConcept_1 (several SPS, each with an empty first set);
- 10-bit vectors and CONFWIN_A are unchanged.

v4l2-compliance (if installed): the same totals before and after. The baseline may already have
the 2 failures that `codec-quality` 0612 fixes, which is not in this stack.

## 3. Not covered on the board

- Commit 3 (short control arrays): GStreamer and FFmpeg always send `num` elements. A test needs a
  client that sends an SPS with N sets and an EXT_SPS_ST_RPS with fewer elements, on a KASAN
  kernel. With the fix, VDPU381 prints `Long and short term RPS not set` instead of reading out of
  bounds.
- Commit 4: VDPU383 (RK3576) only.
- Commit 6: needs failslab or fail_function, which the Ubuntu config doesn't enable.
- RK3399 (commit 1 also fixes its `num_slices`): no hardware.
- `opi5/rkvdec-ccu-7.3` ("give every job its own H.264/HEVC tables") is not part of
  `patches/linux`. With one RPS table per job, a single per-context cache is wrong: a table that
  wasn't used for the last build is never rebuilt. If that branch goes in, it must either rebuild
  the RPS table for every job or keep one cache per table.

## 4. Undo and integration

The script restores the board itself: it removes `updates/opi5-hevc-rps`, moves the other drop-ins
back, runs `depmod -a` and reloads the module. To do it by hand:
`sudo rm -rf /lib/modules/$(uname -r)/updates/opi5-hevc-rps && sudo depmod -a`, then reboot or
`sudo modprobe -r rockchip_vdec && sudo modprobe rockchip_vdec`.

For the next image (the user's call, not done here): `patches-7.3/0001-0006` apply in sequence on
`opi5/integration-7.3` and on `opi5/integration-extra-7.3`. Renamed to a free range, for example
`patches/linux/0620-0625-*.patch` (after the rkvdec VP9 range 0601-0609; `codec-quality` has planned 0610-0612), they go into the next `build-kernel.sh` run. They need no
config change.
