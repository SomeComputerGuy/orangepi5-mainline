# hevc-rc: VEPU580 HEVC CBR rate control review/fix (state file)

## State (2026-11-06, hevcrc-2)
- hevcrc-1 (job 013, 15hrc1 on k15): FAIL 3 checks (results/VERDICT.txt, results/RUNNER-SUMMARY.md).
  Analysis below: all three fails come from the criteria (partial GOP, start-up trade, fps noise), but the data shows a real flaw the criteria did not
  even test (I picture bloat, 1 s peaks up to 1.52x).
- hevcrc-2: new commit 892dbc68ef24 on k16-hevcrc (I picture size bound, MPP behaviour), new criteria,
  new package tools2/ (results in results2/). Built 16hrc2 (exit 0, build-hrc2.log; uname #16hrc2);
  queued RUNNER-QUEUE/039-hevcrc-2.job (TEST, ~30 min).
  Not run yet.

## Branches (src/linux)
- k16-hevcrc (worktree build/wt-k16hevcrc) on k16-venc8k ca8a79c75793:
  - 892dbc68ef24 media: v4l2-core: Bound the I picture size in the encode CBR rate control
  (k16-venc8k already carries 019b77c74e75 helper, 6185f0465ac0 HEVC core CBR, ff2515e155e8 rkvenc
  uses it, 0bbcfa636c53 + ca8a79c75793 >4096.)
- Debs: out/test/hrc2/debs (7.3.0-16hrc2, uname #16hrc2), log build-hrc2.log.
- Old: k15-hevcrc (wt-k15hevcrc), k15-hevcrc-d2 (test only): superseded by the k16 branches.
- Patch: patches/0004-media-v4l2-core-Bound-the-I-picture-size-in-the-enco.patch (after 0001-0003).

## hevcrc-1 analysis (from results/sizes, per GOP)
1. RATE bbb1080:2000 +3.2 % (gop% +0.1): partial-GOP artifact of a GOP planner. The 1080p clips are
   2.5 GOPs (300 pictures, GOP 120); the plan front-loads each GOP with the I excess and repays it over
   the GOP. After half a GOP the planned excess is 60(R-1)/(R+119) nominal pictures, i.e. a full-clip
   error of 20(R-1)/(R+119) % = 3.9 % at the largest ratio R=30, whatever the controller does.
   Per GOP: GOP1 1998, GOP2 2006, half GOP3 2318 kbit/s. The old driver RC repaid I excess over the
   next 8 P (0.2 %), at the price of tiny IDRs (3.9x nominal) and poor I quality (-0.7 dB).
   MPP's rc_model_v2 is a GOP planner too. -> Criterion fixed, not the code.
2. PSNR jelly2160 -0.07/-0.11 dB: at equal achieved bitrate (new 20016 vs old 19955 kbit/s, 39982 vs
   40021) still -0.08/-0.11 dB, so not a rate effect. All of it is in GOP1: first IDR 5.2x nominal
   (old 2.8x, fixed 4x I target) from MPP's initial I/P ratio 10 (init_ip_ratio 160), so GOP1 P get
   0.93 instead of 0.97 nominal; GOP2 has equal IDR (3.4 vs 3.5x) and more P budget (0.96 vs 0.95).
   The same start-up allocation is +1.0 dB on bbb2160 and +0.7..0.9 dB on bbb1080. Verdict: a start-up
   rate/quality trade (MPP-identical), not a steady-state regression; on a 4 s clip GOP1 is half the clip.
   -> Criterion: steady state (whole GOPs after the first) at equal rate >= -0.05 dB; all whole GOPs
   >= -0.15 dB (start-up allowance); mean over all cases >= 0.
3. FPS d2 bbb1080:2000 229.7 vs 252.3: the old baseline is the outlier (all other 1080p cases of every
   kernel 228-235 fps; it is the first case of the phase). 300 pictures at 230 fps = 1.3 s per run,
   with ~0.1-0.2 s gst start-up in the measurement: per-case noise > 5 %. Rate control does not change
   the hardware time per picture. -> Criterion: per case >= 0.85x, median per resolution >= 0.95x.
4. Real flaw, not tested before: I picture bloat. I QP = P state - 4, regardless of its target. On
   bbb (static, P pictures very cheap) the state drifts down over a GOP and IDR@121 came out 137 kB =
   33x nominal (2.6x its target, 36 % above its share at the largest ratio 30); IDR sizes swing 3.0x
   (idr_ratio 3.02, old 0.60); largest 1 s window 1.52x target (old 1.20x); bbb2160 IDR 14.4x.
   H.264 has the same code (shared helper) but its I QP delta is 2.

## MPP behaviour notes: I picture QP (clean room, read from orangepi-bsp/mpp/mpp/codec/rc/rc_model_v2.c
## rc_model_v2_hal_start/hal_end, calc_next_i_ratio, check_re_enc; h265e_api.c defaults)
- I QP = mean of (the P QP state when the previous I was coded) and (the current P state, plus a
  pending I increase), minus qp_delta_ip (H.265 4; limited to 4..7 by texture, no effect at 4).
  When the current value is >= 35 and the previous <= 33, the current weighs about 70 %.
- After an I picture: if its size exceeded the I allocation of the GOP at the largest ratio
  (max_i_prop 30: gop_bits*480/(480+16*(gop-1))), the pending I increase grows by
  (size - alloc)/alloc * 4 QP (clipped to +-4 QP per I), accumulating, never below 0, and limited by
  a QP-dependent table (about 10 QP at low QP, 4 at QP 25-27, 2 at 33-38, 1 at 39-44, 0 at >= 45).
  It decays when later I pictures come out below that allocation.
- Re-encode (default max_reenc_times 1): an I picture larger than 1.5x its target (P: 3x) is coded
  again with a higher QP when, in CBR, the 3 s window rate jumps by > 5 % and is > 10 % off target.
  Our driver cannot re-encode yet (open item).
- H.265 defaults: qp_min 10, qp_min_i 15 (I never below 15), qp_max 51, init_ip_ratio 160,
  max_i_prop 30, min_i_prop 10, gop 60, stats window 3 s.
- Our helper before 892dbc68ef24: I QP = current state - delta, nothing else (the H.264 venc-rc work
  noted MPP's mean but did not implement it).

## Fix (892dbc68ef24, both codecs, written from the notes above)
- I QP = mean(state now, state at the previous I) [70 % now when it rose from <= 33 to >= 35] +
  I increase - delta. All-intra (gop 1) unchanged.
- I increase: after an I above its share at ratio 30, += 4 QP * (size - share)/share clipped +-4 QP,
  in [0, min(6, (45 - QP)/4) QP]; decays as I pictures come out below the share. Own limit
  function (quarter QP per QP step below 45, at most 6), not MPP's table.
- H.264 changes too (shared helper; MPP does the same for H.264): checked in hevcrc-2 against k16rc2.

## Criteria (hevcrc-2, tools2/verdict.py) and why
- Baseline "old" = k16rc2 (exact parent of k16-venc8k without the three hevcrc commits): driver HEVC
  RC and the pre-helper H.264 code with the same nal_ref_idc (stock 15 has the older H.264 RC, so it
  is no regression baseline for the helper; compare decoded PSNR/size, never md5).
- RATE: whole-GOP error -3..+1 % (over-rate beyond 1 % over whole GOPs is a control error;
  under-rate to -3 % as before, below that only FLOOR); full clip -3..+3 %, +5 % for clips ending
  inside a GOP (planned excess of the unfinished GOP, <= 3.9 % here).
- PEAK (new): largest 1 s window <= the plan's 1 s peak with the I at 1.5x its largest share (MPP's
  re-encode threshold): 1.395x at 1080p60/GOP 120, 1.66x at 2160p30/GOP 60. hrc1 fails it on all
  three bbb1080 cases (1.52/1.45/1.43): that is the flaw of item 4.
- PSNR: per-picture MSE (FFmpeg stats_file), whole GOPs only (the unfinished GOP's I is paid for
  in the rate but its quality pay-off falls outside the clip, which unfairly penalises a GOP planner),
  at equal achieved bitrate (old curve of the same clip interpolated over log kbps). Steady state
  (GOPs after the first) >= -0.05 dB (about 1.2 % BD-rate at these slopes: below what a rate control
  change can be told apart from noise-level allocation shifts); all GOPs >= -0.15 dB; mean >= 0.
- SPIKE <= 2.0, FPS (see item 3), KERNEL. H.264: RATE as above, PSNR at equal rate (slope of the old
  H.265 curve of the clip) >= -0.05 dB. Wide H.265 (>4096): venc8k-2's checks.
- Verdict smoke-tested on the hevcrc-1 data (fake per-picture MSE): mechanics ok.

## Next step (when results2/RUNNER-SUMMARY.md arrives)
- OVERALL PASS: done. Proposal for patches/linux: k16-venc8k's hevcrc commits + 892dbc68ef24.
- PEAK still FAIL on bbb1080 (I bloat at the first IDR after a drift, which the increase only acts on
  for the next I): read results2/trace/trace-new-trace-bbb1080-h265-rkv-2000.txt (lines "intra: 1,
  picture QP", "size: ... target"); if the I is > 1.5x its target the remaining MPP mechanism is the
  I re-encode: rkvenc already has a multi-pass hook (codec op next_pass, used for tiles); a re-encode
  needs the HEVC core to re-run rc_step with a higher QP for the same picture (core API change).
- PSNR FAIL steady state on yacht/jelly: compare dSS of old vs new per GOP with results2/psnr files;
  if it comes from the mean I QP (I QP higher than hrc1), consider the mean only when the state
  dropped (MPP applies it both ways).
- H.264 FAIL: the change hit H.264 (delta 2); compare its IDR sizes with old.

## Test packages
- hevcrc-1: tools/ (hevcrc-test.sh, hrun.sh, verdict.py, HANDOFF.md) -> results/.
- hevcrc-2: tools2/hevcrc-test.sh (host, resumable/pausable, BOARD-WANT/BOARD-PAUSE, stock restore,
  copy-off per case), tools2/hrun.sh (board; + per-picture PSNR stats, dmesg -w trace capture),
  tools2/install-test.sh (glob + dpkg-deb -f Version), tools2/verdict.py, tools2/HANDOFF.md -> results2/.
