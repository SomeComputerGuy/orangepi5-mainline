# JOB venc8k-1: VEPU580 H.264/H.265 encode above 4096 wide (TEST run, about 75 min)

Type: **TEST** (long, pausable/resumable; the script yields to BOARD-WANT/ and BOARD-PAUSE itself,
never writes BOARD-WANT files).

## Command (host, detached)

    nohup bash ~/orangepi5/work/_out/k15/venc8k/tools/venc8k-test.sh > /dev/null 2>&1 &

The script logs to `~/orangepi5/work/_out/k15/venc8k/results/run.log` itself.
Restarting the same command after any stop resumes where it stopped (finished cases are skipped).

## What it does (no action needed from the runner)

Two kernels, whole debs via `work/_out/k15/venc-rc/tools/install-test.sh`, one after the other:

| phase | debs | uname -v |
|---|---|---|
| old | ~/orangepi5/out/test/hevcrc/debs | #15hrc1 |
| new | ~/orangepi5/out/test/venc8k/debs | #15v8k1 |

Per kernel, `tools/v8run.sh` on the board encodes raw NV12 (Big Buck Bunny 4K scaled with ffmpeg)
with `v4l2sl*h264enc` / `v4l2sl*h265enc` on the VEPU580 (rockchip-venc), constant QP 26/28 or CBR,
decodes the result with FFmpeg's software decoder, measures PSNR-Y (whole picture, and for widths
above 4096 also the left 4096 columns and the columns right of 4096), and counts dmesg lines after a
per-case marker that match iommu/fault/timeout/watchdog/venc/vepu/WARNING/BUG/Oops.
old: 9 regression cases (1080p, 2160p, 4096x2160). new: the same 9 plus 16 wide cases
(4104x2160, 4112x2160, 5120x2880, 7680x4320, 8192x4320, 16384x2048; H.265 and H.264).
At the end it restores stock 15 (`NOLOCK=1 work/_out/k14/install-check.sh`), releases BOARD-LOCK and
writes results/VERDICT.txt.

## End condition

File `~/orangepi5/work/_out/k15/venc8k/results/END` exists. Its one line is `DONE` or `BLOCKED <reason>`.
Watcher: check every >= 600 s for that file. If run.log has not grown for 45 min and END does not exist,
report BLOCKED "stalled" with the last 20 lines of run.log (do not kill or restart anything).

## Checks after END (run exactly)

1. `cat ~/orangepi5/work/_out/k15/venc8k/results/END` -> must be `DONE` (else job = BLOCKED, quote the line).
2. Stock restored: `$(cat ~/.claude/jobs/35761d63/tmp/ssh.cmd) 'uname -v'` must contain
   `#15 SMP` and `Wed Nov  4 20:25:22` (or `Wed Nov 4 20:25:22`); and `cat ~/orangepi5/work/_out/BOARD-LOCK`
   must not start with `venc8k` (no file is fine).
3. `python3 -I ~/orangepi5/work/_out/k15/venc8k/tools/verdict.py ~/orangepi5/work/_out/k15/venc8k/results`
   (same output as results/VERDICT.txt). Job result = its last line: `OVERALL PASS` -> PASS, `OVERALL FAIL` -> FAIL.
   The verdict applies these thresholds itself:
   every new-kernel case: gst exit 0, decoded frames = encoded frames, 0 FFmpeg decoder messages,
   0 matching dmesg lines, PSNR-Y (whole, left 4096, right of 4096) >= 36 dB for CQP and >= 32 dB for CBR;
   regression (1080p/2160p/4096 wide): new bitstream md5 = old (SAME), or for CBR cases PSNR within 0.05 dB
   and size within 0.5% (CLOSE); DIFF = fail; 25 new rows expected.
4. `cat ~/orangepi5/work/_out/k15/venc8k/results/failed.txt` (if it exists): list its lines.
5. `grep -c . ~/orangepi5/work/_out/k15/venc8k/results/venc8k.csv` -> expect 35
   (header + 9 old + 25 new).
6. `cat ~/orangepi5/work/_out/k15/venc8k/results/logs/dmesg-new-*.txt` -> quote every line (expected: none).

## Files (already on the host; the script copies them off the board after every case)

results/venc8k.csv, results/logs/ (gst-*.log, dmesg-*.txt, ffdec-*.txt), results/run.log,
results/v8run.err, results/VERDICT.txt.

## Summary must list

Job name, start/end time, the END line, the stock-restore check, the full VERDICT.txt (both tables,
the two "largest passing wide size" lines and the OVERALL line), failed.txt lines, every line of
results/logs/dmesg-new-*.txt, and any line of results/v8run.err containing `gst failed`, `no element`,
`no source` or `no disk space`.
