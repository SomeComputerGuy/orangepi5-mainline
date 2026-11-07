# JOB dp-black-2 (TEST, ~7 h board time, pausable/resumable)

Silent DP black (DP-1 over USB-C Alt Mode, camera verdict) in repeated dual-head modesets, A/B of the VOP2 DP
interface enable order inside ONE test kernel, 7.3.0-16dpb1 (branch k16-dpblack). The board script alternates
the runtime parameter /sys/module/rockchipdrm/parameters/dp_if_gate per iteration: odd iterations 0 (old order,
like stock), even iterations 1 (fix). Seven blocks D1..D7 of 200 iterations, each block its own board session (own
boot + camera calibration). One iteration = one kmsctl client: both heads 1080p60 bars, camera verdict after 8 s
(DP re-checked after 4 s if not GOOD), DPCD link status read over the DP AUX chardev (read only), client exit
(fbcon restore). Never touches the DP monitor (no wake, no input switch), no Type-C role changes; the TV input goes
to the board over CEC.

## Kernel / debs (run.sh installs them itself; install nothing by hand)
- ~/orangepi5/out/test/dpblack/debs/linux-{image,headers}-7.3.0-opi5_*_arm64.deb (16dpb1; the script
  globs them and reads the version from the deb)

Precondition: ~/orangepi5/work/_out/k15/dp-silent-black/logs/build-16dpb1.log ends with `rc=0`.

## Command (exactly this, detached)
```
cd ~/orangepi5/work/_out/k15/dp-silent-black/b2 && \
nohup bash tools/run-dpb2.sh > ~/orangepi5/work/_out/k15/dp-silent-black/b2/run-dpb2.nohup.log 2>&1 &
```
TEST run: writes no BOARD-WANT file; each block takes BOARD-LOCK only while BOARD-WANT/ is empty and
work/_out/BOARD-PAUSE is absent, installs and boot-checks the kernel, runs the board part as systemd unit
dpblack2-run (board dir /var/tmp/dpblack2, 7 min stall watchdog, 90 min timeout), copies results to
b2/run-<block>/out every 30 s, restores stock 15 and checks `uname -v` before releasing the lock on every exit path.
A BOARD-WANT file or BOARD-PAUSE makes it stop after the current iteration (~16 s), restore stock 15, release the
lock, wait (checks every 5 min) until both are clear and resume by itself (finished iterations are skipped). If the
wrapper itself is ever killed, rerunning the same command resumes (finished blocks and iterations are skipped).

## End condition (for your watcher, check at most every 10 min)
- `grep -q 'run-dpb2: finished' ~/orangepi5/work/_out/k15/dp-silent-black/b2/run-dpb2.log`, or
- the wrapper is gone: `ps -eo pid,args | grep '[t]ools/run-dpb2.sh'` prints nothing.
BLOCKED (report the lines, do nothing else) if: run-dpb2.log has "BLOCK FAILED" (this includes "DP-1 NOT
CONNECTED" after a boot, "NO TESTMATRIX" and "NO DP_IF_GATE PARAM"); any b2/run-*/host.log has "RESTORE FAILED" or
"BOOT CHECK FAILED".

## Pass/fail (mechanical)
```
bash ~/orangepi5/work/_out/k15/dp-silent-black/b2/tools/check-dpb2.sh \
  | tee ~/orangepi5/work/_out/k15/dp-silent-black/b2/check.txt
```
The last line decides: `OVERALL PASS` = PASS, `OVERALL FAIL` = FAIL, `OVERALL INCONCLUSIVE` = report as FAIL with
the word INCONCLUSIVE. Checks (all in check-dpb2.sh): every block restored stock 15 and released the lock; boot
checks clean (#16dpb1, warn=0, no missing USB device); >= 1300 iterations, >= 600 valid camera verdicts per arm;
0 WARNING/BUG/Oops/Call trace lines; no error type in the gate=1 arm that the gate=0 arm lacks; 0 "video FIFO
overflow" iterations in the gate=1 arm; failed commits gate=1 <= gate=0; black (both DP verdicts BLACK) rate of
gate=1 below the reference (gate=0 arm + dp-black-1 stock data 2/360) with one-sided Fisher p < 0.05.
INFO lines are data (copy them verbatim).

## Files (already on the host; nothing extra to copy)
b2/run-dpb2.log, b2/run-dpb2.nohup.log, b2/check.txt, b2/run-D1 .. run-D7/ (host.log, boot-*.txt, dpkg.txt,
dmesg-end.txt, out/: board.log, iter.tsv, kmsg-all*.txt, cal/, it/<n>/ verdicts, kms.json, kmsg.txt, frames of
non-GOOD iterations and of every 10th).

## Summary must list (~/orangepi5/work/_out/k15/dp-silent-black/b2/RUNNER-SUMMARY.md)
- start/end time, the command, number of board sessions per block (lines "session start" in run-dpb2.log);
- every line of check.txt verbatim;
- every iter.tsv row whose DP field is not `DP=GOOD` (with its block name);
- the count of iter.tsv rows with ovfall not 0, per gate value (`grep -h 'ovfall=[1-9]' b2/run-D*/out/iter.tsv | grep -c 'gate=0'`, same for `gate=1`);
- any host.log / board.log line with STALL, TIMEOUT, FAILED, BOARD-PAUSE, BOARD-WANT, PAUSED, CALIBRATION FAILED;
- the file list (top level of b2/ and of each run-*/out, without it/).

Run after any earlier display job; DP monitor and cable must be as they are (do not touch them).
