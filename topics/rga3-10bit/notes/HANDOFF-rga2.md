# JOB rga3-nv15-2 (DEV, ~20 min board time)

Re-test after run rga1: kernel 7.3.0-15rga2 (branch k15-rga3nv15, same 4 RGA patches as 15rga1; only the
RGA3 flip+rotation mapping changed) and a fixed test tool (rga-xtest now sets the colorspace so the BT.709 /
BT.2020 requests reach the driver). Quick run: NO stock-15 baseline session and NO regress phase (they passed
in rga1 and the paths are unchanged); phases info, compliance and all cases (the rga1 cases plus 9 new
flip+rotation combinations).
Kind: DEV (one board turn: install the test kernel, short tests, restore stock 15). No display, camera or TV.

## Kernel / debs
- ~/orangepi5/out/test/rga/debs/linux-image-7.3.0-opi5_7.3.0-15rga2_arm64.deb
- ~/orangepi5/out/test/rga/debs/linux-headers-7.3.0-opi5_7.3.0-15rga2_arm64.deb
  (run.sh installs them itself; do not install anything by hand)

## Command (exactly this, detached)
```
cd ~/orangepi5/work/_out/k15/rga3-nv15 && \
nohup env KREV=15rga2 KDIR=out/test/rga/debs TAG=rga2 STOCK=0 PH="info compliance cases" bash tools/run.sh \
  > ~/orangepi5/work/_out/k15/rga3-nv15/run-rga2.nohup.log 2>&1 &
```
The script takes BOARD-LOCK itself (BOARD-WANT/rga3-nv15 while waiting, first come first served), clears the
board's old results of run rga1, installs and boot-checks 15rga2, runs the session "test", copies results to
run-rga2/out every 30 s, restores stock 15 (k14/install-check.sh) and checks `uname -v` before it releases the
lock, on every exit path. Stall watchdog: 8 min without new board output; 60 min limit. Honours BOARD-PAUSE
(stops at the next case/phase).

## End condition (for your watcher, check at most every 10 min)
- `grep -q 'lock released' ~/orangepi5/work/_out/k15/rga3-nv15/run-rga2/host.log`, or
- the run.sh process is gone: `ps -eo pid,args | grep '[b]ash tools/run.sh'` prints nothing.

If host.log ends with "BOARD-PAUSE: paused in session test, rerun to resume" and the lock was released: wait until
work/_out/BOARD-PAUSE is gone and no other agent's BOARD-WANT file is older, then run the same command once more;
it resumes (finished phases and cases are skipped). Record both sessions.
If host.log shows "RESTORE FAILED", "BOOT CHECK FAILED", "INSTALL FAILED", "PREP FAILED", "PUSH FAILED" or
"SESSION FAILED": BLOCKED, report the lines, do nothing else.

## Pass/fail (mechanical)
Run:
```
python3 -I ~/orangepi5/work/_out/k15/rga3-nv15/tools/check.py ~/orangepi5/work/_out/k15/rga3-nv15/run-rga2 15rga2 quick \
  | tee ~/orangepi5/work/_out/k15/rga3-nv15/run-rga2/check.txt
```
Each line is PASS/FAIL/INFO. The job is PASS only if the last line is `OVERALL PASS`. The checks:
1. stock-restored: last `uname -v:` in host.log is "#15 SMP ... Wed Nov  4 20:25:22" and "lock released" present.
2. boot-15rga2: boot-15rga2.txt shows `#15rga2`, warn=0, usb_missing empty, iommu_err=0.
3. rga3-formats / rga3-controls: as in rga1 (out/test/info.txt).
4. compliance-rga2 / compliance-rga3: v4l2-compliance on 15rga2 has Failed: 0 and Succeeded = Total.
5. regress: not run (line "INFO regress phase not run (quick)").
6. case <id> lines (judge.py, all of tools/cases.txt). The two rga1 failures to look at first:
   - c-hevc-xr24-709 / c-hevc-xr24-2020: >= 30 dB (a "colorimetry not taken" rc=1 line is a FAIL);
   - r-xr24-* (all 15 flip/rotation combinations), r-nv12-h-r90, r-nv12-v-r270, r-nv15-h-r90:
     "want X got X" (bit-exact).
7. dmesg-clean-test: 0 matching lines in out/test/dmesg*.txt.

## Files (already on the host; nothing extra to copy)
run-rga2/host.log, run-rga2/boot-15rga2.txt, run-rga2/boot-15.txt, run-rga2/dpkg.txt, run-rga2/dmesg-end.txt,
run-rga2/out/board.log, run-rga2/out/test/ (info.txt, compliance-*.txt, cases.tsv, <case>.log, <case>.raw,
judge.txt, dmesg-*.txt), run-rga2/check.txt.

## Summary must list (run-rga2/RUNNER-SUMMARY.md)
- start/end time, the command, number of sessions (resumes);
- every line of check.txt verbatim;
- the compliance `Total for ...` lines for both nodes;
- any host.log line with STALL, TIMEOUT, FAILED, BOARD-PAUSE;
- the file list (top level of run-rga2 and of out/test).

Precondition: build-15rga2.log ends with "exit=0".
