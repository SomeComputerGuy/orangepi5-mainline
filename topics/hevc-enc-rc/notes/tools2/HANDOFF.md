# JOB hevcrc-2: VEPU580 HEVC CBR rate control, I picture size bound (TEST run, about 30 min)

Type: **TEST** (pausable/resumable; the script yields to BOARD-WANT/ and BOARD-PAUSE itself,
never writes BOARD-WANT files).

## Command (host, detached)

    nohup bash ~/orangepi5/work/_out/k15/hevc-rc/tools2/hevcrc-test.sh > /dev/null 2>&1 &

The script logs to `~/orangepi5/work/_out/k15/hevc-rc/results2/run.log` itself.
Restarting the same command after any stop resumes where it stopped (finished cases are skipped).

## What it does (no action needed from the runner)

Two kernels, whole debs via `tools2/install-test.sh` (debs found by glob, version read with
`dpkg-deb -f`), one after another:

| phase | debs | uname -v |
|---|---|---|
| old | ~/orangepi5/out/test/k16rc2/debs | #16rc2 |
| new | ~/orangepi5/out/test/hrc2/debs | #16hrc2 |

Per kernel: GStreamer CBR encodes (tools2/hrun.sh on the board) of bbb1080/yacht1080 (1080p60, 300 pictures)
at 2/4/8 Mb/s and bbb2160/jelly2160 (2160p30, 120 pictures) at 20/40 Mb/s with H.265 on the VEPU580, plus
H.264 bbb1080 4 Mb/s (VEPU580 and H1) and yacht1080 2 Mb/s (VEPU580); per-picture PSNR stats are kept.
New kernel only: 4 rate control traces (label `new-trace`, no PSNR) and 3 H.265 encodes wider than
4096 (k15/venc8k/tools/v8run.sh: 4104x2160 CQP, 5120x2880 CBR 60 Mb/s, 8192x4320 CQP).
At the end it restores stock (`NOLOCK=1 work/_out/k14/install-check.sh`, installs out/debs), releases
BOARD-LOCK and writes results2/VERDICT.txt.

## End condition

File `~/orangepi5/work/_out/k15/hevc-rc/results2/END` exists. Its one line is `DONE` or `BLOCKED <reason>`.
Watcher: check every >= 600 s for that file. If run.log has not grown for 45 min and END does not exist,
report BLOCKED "stalled" with the last 20 lines of run.log (do not kill or restart anything).

## Checks after END (run exactly)

1. `cat ~/orangepi5/work/_out/k15/hevc-rc/results2/END` -> must be `DONE` (else job = BLOCKED, quote the line).
2. Stock restored: `$(cat ~/.claude/jobs/35761d63/tmp/ssh.cmd) 'uname -v'` must contain
   `#15 SMP` and `Wed Nov  4 20:25:22` (or `Wed Nov 4 20:25:22`); and `cat ~/orangepi5/work/_out/BOARD-LOCK`
   must not start with `hevc-rc2` (no file is fine).
3. `python3 -I ~/orangepi5/work/_out/k15/hevc-rc/tools2/verdict.py ~/orangepi5/work/_out/k15/hevc-rc/results2`
   (same output as results2/VERDICT.txt). Job result = its last line: `OVERALL PASS` -> PASS, `OVERALL FAIL` -> FAIL.
   The verdict applies all thresholds itself (listed at the top of verdict.py; reasons in ../STATE.md).
4. `cat ~/orangepi5/work/_out/k15/hevc-rc/results2/failed.txt` (if it exists): list its lines.
5. `grep -c . ~/orangepi5/work/_out/k15/hevc-rc/results2/hevcrc.csv` -> expect 31
   (header + 13 old + 13 new + 4 new-trace); `grep -c '^new,' .../results2/wide.csv` -> expect 3.
6. `ls ~/orangepi5/work/_out/k15/hevc-rc/results2/psnr | wc -l` -> expect 26.

## Files (already on the host; the script copies them off the board after every case)

results2/hevcrc.csv, results2/wide.csv, results2/sizes/, results2/psnr/, results2/trace/, results2/run.log,
results2/hrun.err, results2/VERDICT.txt.

## Summary must list

Job name, start/end time, the END line, the stock-restore check, the full VERDICT.txt (all tables and the
OVERALL line), failed.txt lines, the counts of checks 5 and 6, and any line of results2/hrun.err containing
`gst failed` or `no element` or `no source` or `no disk space`.
Write it to ~/orangepi5/work/_out/k15/hevc-rc/results2/RUNNER-SUMMARY.md.
