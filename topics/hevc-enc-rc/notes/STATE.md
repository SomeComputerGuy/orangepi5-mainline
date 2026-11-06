# hevc-rc: VEPU580 HEVC CBR rate control review/fix (state file)

## State
Code done, built, board test package hevcrc-1 submitted to the runner (TEST, ~60 min). Waiting for
the runner summary (results/RUNNER-SUMMARY.md, results/VERDICT.txt). Nothing tested on the board yet.

## Branches (src/linux; worktree build/wt-k15hevcrc)
- k15-hevcrc on k15-h1rc (956c85289a35):
  - b5540f8ce451 media: v4l2-core: Move the H.264 encode CBR rate control to a helper
    (new v4l2-enc-cbr.[ch], CONFIG_V4L2_ENC_CBR selected by V4L2_H264_ENC/V4L2_HEVC_ENC;
    H.264 core = same math, I QP delta 2: meant to be bit-exact, checked on the board)
  - cc6bc918fe2d media: v4l2-hevc-enc: Add a constant bitrate mode (core CBR, I QP delta 4 = MPP H.265
    default; enc->cbr.target_bits for the row RC; a driver rc_ops->estimate still overrides)
  - 4a63c9b23492 media: rockchip: rkvenc: Use the CBR mode of the HEVC encode core (private RC dropped)
- k15-hevcrc-d2 = k15-hevcrc + 5ddcb2b3ef97 TEST ONLY (I QP delta 2), comparison build, never merge.
- Patches: patches/0001-0003 (exported from k15-hevcrc).
- Debs: out/test/hevcrc/debs (15hrc1), out/test/hevcrc-d2/debs (15hrc1b). Logs build-hrc1*.log.

## Review findings (flaws of the H.264 list, checked against the old rkvenc HEVC RC)
- Dead band: none in HEVC (6*log2 full correction, +-4/pic). Not a flaw there.
- Target bias: P target = nominal, I = fixed 4x nominal; error pushed onto the next 8 P. Fixed I ratio = flaw.
- Separate I/P histories: YES (qp[0]/qp[1]); IDR coded at the previous I QP, IDR size swings
  0.53..1.38x the previous IDR (venc-rc C1 sizes). Flaw, fixed.
- Error buffer cap: 30 nominal pictures (0.5 s at 60 fps). Flaw, now 3 s.
- QP step per picture: bounded +-4 already; now +4/-2 as H.264.
- Start QP: coarse bpp table; now the MPP bits/sample relation.
- HEVC core had no RC of its own (only rc_ops hooks) -> the model now lives in a codec-independent helper.
- MPP: same rc_model_v2 for HEVC, qp_delta_ip 4 (h265e_api.c), qp_min 10, I QP limited by max_ip_qp_dealt 4..7.

## Expected risks (see verdict)
- 1080p clips are 2.5 GOPs (GOP 120): the partial last GOP's I excess inflates the full-clip error
  (H.264 rkv: +2.4% full vs +0.1% whole GOPs). Delta 4 makes I pictures bigger -> bbb 2 Mb/s may
  exceed +3%; d2 variant shows the alternative. gop_err_pct column = error over whole GOPs.
- 4K bbb 40 Mb/s under-rate (old RC -2.9% too): suspected QP floor (qp_min 10); traced rerun
  classifies it (FLOOR).

## Next step
When the runner summary arrives: read results/VERDICT.txt. If new PASS: done (proposal for
patches/linux: the 3 commits). If RATE fails only from the partial GOP while gop_err is small,
compare d2; pick the delta and/or discuss the criterion with the coordinator. H.264 block must
show identical behaviour (refactor is meant to be no-op).

## Test package
tools/hevcrc-test.sh (host, resumable), tools/hrun.sh (board), tools/verdict.py, tools/HANDOFF.md.
Results: results/hevcrc.csv, sizes/, trace/, run.log, END, VERDICT.txt.
