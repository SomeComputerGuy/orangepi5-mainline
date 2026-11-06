# JOB dp-black-1 (TEST, ~3 h board time, pausable/resumable)

Silent DP black rate (DP-1 over USB-C Alt Mode, camera verdict) in repeated dual-head modesets, stock kernel
7.3.0-15 (baseline) against 7.3.0-15dpirq1 (dw-dp: lost link retrained through a pipeline reset). Six blocks of
60 iterations, alternating kernels, each block its own board session (own boot): B1 (15), F1 (15dpirq1), B2, F2,
B3, F3. One iteration = one kmsctl client: both heads 1080p60 bars, camera verdict after 8 s (DP re-checked after
4 s if not GOOD), DPCD link status read over the DP AUX chardev (read only), client exit (fbcon restore).
Never touches the DP monitor (no wake, no input switch), no Type-C role changes; the TV input goes to the board over CEC.

## Kernel / debs (run.sh installs them itself; install nothing by hand)
- baseline: ~/orangepi5/out/debs/linux-{image,headers}-7.3.0-opi5_7.3.0-15_arm64.deb (stock)
- fix: ~/orangepi5/out/test/dpirq/debs/linux-{image,headers}-7.3.0-opi5_7.3.0-15dpirq1_arm64.deb

Precondition: ~/orangepi5/work/_out/k15/dp-silent-black/logs/build-15dpirq1.log ends with `rc=0`.

## Command (exactly this, detached)
```
cd ~/orangepi5/work/_out/k15/dp-silent-black && \
nohup bash tools/run-dpblack.sh > ~/orangepi5/work/_out/k15/dp-silent-black/run-dpblack.nohup.log 2>&1 &
```
TEST run: writes no BOARD-WANT file; each block takes BOARD-LOCK only while BOARD-WANT/ is empty and
work/_out/BOARD-PAUSE is absent, installs and boot-checks its kernel, runs the board part as systemd unit
dpblack-run (7 min stall watchdog, 1 h timeout), copies results to run-<block>/out every 30 s, restores stock 15
and checks `uname -v` before releasing the lock on every exit path. A BOARD-WANT file or BOARD-PAUSE makes it stop
after the current iteration (~16 s), restore stock 15, release the lock, wait (checks every 5 min) until both are
clear and resume by itself (finished iterations are skipped). If the wrapper itself is ever killed, rerunning the
same command resumes (finished blocks and iterations are skipped).

## End condition (for your watcher, check at most every 10 min)
- `grep -q 'run-dpblack: finished' ~/orangepi5/work/_out/k15/dp-silent-black/run-dpblack.log`, or
- the wrapper is gone: `ps -eo pid,args | grep '[t]ools/run-dpblack.sh'` prints nothing.
BLOCKED (report the lines, do nothing else) if: run-dpblack.log has "BLOCK FAILED" (this includes "DP-1 NOT
CONNECTED" after a boot and "NO TESTMATRIX"); any run-*/host.log has "RESTORE FAILED" or "BOOT CHECK FAILED".

## Pass/fail (mechanical)
```
bash ~/orangepi5/work/_out/k15/dp-silent-black/tools/check-dpblack.sh \
  | tee ~/orangepi5/work/_out/k15/dp-silent-black/check.txt
```
The last line decides: `OVERALL PASS` = PASS, `OVERALL FAIL` = FAIL, `OVERALL INCONCLUSIVE` = report as FAIL with
the word INCONCLUSIVE (the baseline showed no black). Checks: every block restored stock 15 and released the lock;
boot checks clean (warn=0, no missing USB device, right kernel); >= 170 iterations and >= 150 valid camera
verdicts per kernel; black (both DP verdicts BLACK) fix < baseline with one-sided Fisher p < 0.05; no error type in
the fix kernel's log that the baseline log does not have; failed commits fix <= baseline. INFO lines are data.

## Files (already on the host; nothing extra to copy)
run-dpblack.log, run-dpblack.nohup.log, check.txt, run-B1 .. run-F3/ (host.log, boot-*.txt, dpkg.txt,
dmesg-end.txt, out/: board.log, iter.tsv, kmsg-all*.txt, cal/, it/<n>/ verdicts, kms.json, kmsg.txt, frames of
non-GOOD iterations).

## Summary must list (~/orangepi5/work/_out/k15/dp-silent-black/RUNNER-SUMMARY.md)
- start/end time, the command, number of board sessions per block (lines "session start" in run-dpblack.log);
- every line of check.txt verbatim;
- every iter.tsv row whose DP field is not `DP=GOOD` (with its block name);
- any host.log / board.log line with STALL, TIMEOUT, FAILED, BOARD-PAUSE, BOARD-WANT, PAUSED, CALIBRATION FAILED;
- the file list (top level of the work dir and of each run-*/out, without it/).

Run after any earlier display job; DP monitor and cable must be as they are (do not touch them).
