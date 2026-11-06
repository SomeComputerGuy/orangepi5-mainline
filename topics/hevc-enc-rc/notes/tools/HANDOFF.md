# JOB hevcrc-1: VEPU580 HEVC CBR rate control (TEST run, about 60 min)

Type: **TEST** (long, pausable/resumable; the script yields to BOARD-WANT/ and BOARD-PAUSE itself,
never writes BOARD-WANT files).

## Command (host, detached)

    nohup bash ~/orangepi5/work/_out/k15/hevc-rc/tools/hevcrc-test.sh > /dev/null 2>&1 &

The script logs to `~/orangepi5/work/_out/k15/hevc-rc/results/run.log` itself.
Restarting the same command after any stop resumes where it stopped (finished cases are skipped).

## What it does (no action needed from the runner)

Three kernels, whole debs via `work/_out/k15/venc-rc/tools/install-test.sh`, one after another:

| phase | debs | uname -v |
|---|---|---|
| old | ~/orangepi5/out/test/h1rc2/debs | #15h1rc2 |
| new | ~/orangepi5/out/test/hevcrc/debs | #15hrc1 |
| d2  | ~/orangepi5/out/test/hevcrc-d2/debs | #15hrc1b |

Per kernel: GStreamer CBR encodes (tools/hrun.sh on the board) of bbb1080/yacht1080 (1080p60, 300 pictures)
at 2/4/8 Mb/s and bbb2160/jelly2160 (2160p30, 120 pictures) at 20/40 Mb/s with H.265 on the VEPU580;
old and new also H.264 bbb1080 4 Mb/s (VEPU580 and H1) and yacht1080 2 Mb/s (VEPU580).
New kernels re-run H.265 cases with an error below -3% with a rate control trace (label `<phase>-trace`).
Each case: bitrate error, PSNR/SSIM, encode fps, per-picture sizes. At the end it restores stock 15
(`NOLOCK=1 work/_out/k14/install-check.sh`), releases BOARD-LOCK and writes results/VERDICT.txt.
(There is no 4K yacht source on the board; jelly2160 is the second native 4K clip.)

## End condition

File `~/orangepi5/work/_out/k15/hevc-rc/results/END` exists. Its one line is `DONE` or `BLOCKED <reason>`.
Watcher: check every >= 600 s for that file. If run.log has not grown for 45 min and END does not exist,
report BLOCKED "stalled" with the last 20 lines of run.log (do not kill or restart anything).

## Checks after END (run exactly)

1. `cat ~/orangepi5/work/_out/k15/hevc-rc/results/END` -> must be `DONE` (else job = BLOCKED, quote the line).
2. Stock restored: `$(cat ~/.claude/jobs/35761d63/tmp/ssh.cmd) 'uname -v'` must contain
   `#15 SMP` and `Wed Nov  4 20:25:22` (or `Wed Nov 4 20:25:22`); and `cat ~/orangepi5/work/_out/BOARD-LOCK`
   must not start with `hevc-rc` (no file is fine).
3. `python3 -I ~/orangepi5/work/_out/k15/hevc-rc/tools/verdict.py ~/orangepi5/work/_out/k15/hevc-rc/results`
   (same output as results/VERDICT.txt). Job result = its last line: `OVERALL PASS` -> PASS, `OVERALL FAIL` -> FAIL.
   The verdict applies these thresholds itself (H.265, variant new vs old):
   RATE |err| <= 3% (or below -3% with the traced QP at the minimum in >= 50% of pictures = FLOOR, counts as ok),
   PSNR >= old - 0.05 dB, SPIKE (first P after IDR / median P) <= 2.0, FPS >= 0.95 x old, KERNEL as expected;
   H.264 new vs old: kbps within 0.3%, PSNR within 0.05 dB.
4. `cat ~/orangepi5/work/_out/k15/hevc-rc/results/failed.txt` (if it exists): list its lines.
5. `grep -c . ~/orangepi5/work/_out/k15/hevc-rc/results/hevcrc.csv` -> expect 38 or more
   (header + 13 old + 13 new + 10 d2 + trace rows).

## Files (already on the host; the script copies them off the board after every case)

results/hevcrc.csv, results/sizes/, results/trace/, results/run.log, results/hrun.err, results/VERDICT.txt.

## Summary must list

Job name, start/end time, the END line, the stock-restore check, the full VERDICT.txt tables
(both variants and the H.264 block), OVERALL line, failed.txt lines, and any line of results/hrun.err
containing `gst failed` or `no element` or `no source`.
