# JOB venc8k-2: VEPU580 HEVC above 4096 wide in tile columns (TEST run, about 15-20 min)

Type: **TEST** (short, pausable/resumable; the script yields to BOARD-WANT/ and BOARD-PAUSE itself,
never writes BOARD-WANT files).

## Command (host, detached)

    nohup bash ~/orangepi5/work/_out/k15/venc8k/tools/venc8k-test2.sh > /dev/null 2>&1 &

The script logs to `~/orangepi5/work/_out/k15/venc8k/results2/run.log` itself.
Restarting the same command after any stop resumes where it stopped (finished cases are skipped).

## What it does (no action needed from the runner)

One test kernel, whole debs via `tools/install-test2.sh` (debs by glob, version from `dpkg-deb -f`):

| phase | debs | uname -v |
|---|---|---|
| new | ~/orangepi5/out/test/venc8k2/debs (7.3.0-16venc8k2) | #16venc8k2 |

The 9 "old" regression rows (kernel 15hrc1) are copied from the venc8k-1 run (results/venc8k.csv);
they are not re-run. On the board `tools/v8run.sh` encodes raw NV12 (Big Buck Bunny 4K scaled with
ffmpeg) with `v4l2sl*h264enc` / `v4l2sl*h265enc` on the VEPU580 (rockchip-venc), CQP 26/28 or CBR,
decodes with FFmpeg's software decoder, measures PSNR-Y (whole picture; above 4096 wide also the left
4096 columns and the columns right of 4096) and counts matching dmesg lines per case.
Cases: 9 regression (1080p, 2160p, 4096x2160) + 15 wide (4104x2160, 4112x2160, 5120x2880,
7680x4320, 8192x4320, 12288x2048, 16384x2048; H.265 and H.264).
At the end it restores stock (`NOLOCK=1 work/_out/k14/install-check.sh`), releases BOARD-LOCK and
writes results2/VERDICT.txt.

## End condition

File `~/orangepi5/work/_out/k15/venc8k/results2/END` exists. Its one line is `DONE` or `BLOCKED <reason>`.
Watcher: check every >= 600 s for that file. If results2/run.log has not grown for 45 min and END does
not exist, report BLOCKED "stalled" with the last 20 lines of run.log (do not kill or restart anything).

## Checks after END (run exactly)

1. `cat ~/orangepi5/work/_out/k15/venc8k/results2/END` -> must be `DONE` (else job = BLOCKED, quote the line).
2. Stock restored: `$(cat ~/.claude/jobs/35761d63/tmp/ssh.cmd) 'uname -v'` must contain
   `#15 SMP` and `Wed Nov  4 20:25:22` (or `Wed Nov 4 20:25:22`) unless another job already holds
   BOARD-LOCK (then quote BOARD-LOCK and the run.log lines from "restore stock 15" to "lock released");
   `cat ~/orangepi5/work/_out/BOARD-LOCK` must not start with `venc8k2` (no file is fine).
3. `python3 -I ~/orangepi5/work/_out/k15/venc8k/tools/verdict2.py ~/orangepi5/work/_out/k15/venc8k/results2`
   (same output as results2/VERDICT.txt). Job result = its last line: `OVERALL PASS` -> PASS, `OVERALL FAIL` -> FAIL.
   The verdict applies these thresholds itself: every new-kernel case: gst exit 0, decoded frames =
   encoded frames, 0 FFmpeg decoder messages, 0 matching dmesg lines, PSNR-Y (whole, left 4096, right
   of 4096) >= 36 dB for CQP and >= 32 dB for CBR; regression rows: SAME (md5 equal) or CLOSE
   (PSNR-Y within 0.05 dB and size within 0.5%), DIFF = fail; 24 new rows expected.
4. `cat ~/orangepi5/work/_out/k15/venc8k/results2/failed.txt` (if it exists): list its lines.
5. `grep -c . ~/orangepi5/work/_out/k15/venc8k/results2/venc8k.csv` -> expect 34
   (header + 9 old + 24 new).
6. `cat ~/orangepi5/work/_out/k15/venc8k/results2/logs/dmesg-new-*.txt` -> quote every line (expected: none).
7. `cat ~/orangepi5/work/_out/k15/venc8k/results2/logs/ffdec-new-*h265*.txt` -> quote every line (expected: none).

## Files (already on the host; the script copies them off the board after every case)

results2/venc8k.csv, results2/logs/ (gst-*.log, dmesg-*.txt, ffdec-*.txt), results2/run.log,
results2/v8run.err, results2/VERDICT.txt.

## Summary must list

Job name, start/end time, the END line, the stock-restore check, the full VERDICT.txt (both tables,
the two "largest passing wide size" lines and the OVERALL line), failed.txt lines, every line of
results2/logs/dmesg-new-*.txt and ffdec-new-*h265*.txt, and any line of results2/v8run.err containing
`gst failed`, `no element`, `no source` or `no disk space`.
Write it to ~/orangepi5/work/_out/k15/venc8k/results2/RUNNER-SUMMARY.md.
