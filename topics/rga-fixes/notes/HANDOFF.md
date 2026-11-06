# JOB rga-fu-1 (DEV, ~25 min board time)

RGA follow-up fixes: kernel 7.3.0-15rgafu1 (branch k15-rgafu = k15-rga3nv15 + 4 patches: RGA2 flip
direction, RGA3 crop/compose rectangles, larger userspace bytesperline, NV20 on the RGA3).
One test session on 15rgafu1, NO stock-15 session (the stock baseline is the stock session of the
rga3-nv15 run rga1, read by check.py from k15/rga3-nv15/run-rga1/out/stock). Phases: info, compliance,
regress (RGA2 k14 regress + RGA3 k12 func suite) and all cases (the rga3-nv15 cases as regression plus the
new flip/crop/stride/NV20 cases).
Kind: DEV (one board turn: install the test kernel, short tests, restore stock 15). No display, camera or TV.

## Kernel / debs
- ~/orangepi5/out/test/rgafu/debs/linux-image-7.3.0-opi5_7.3.0-15rgafu1_arm64.deb
- ~/orangepi5/out/test/rgafu/debs/linux-headers-7.3.0-opi5_7.3.0-15rgafu1_arm64.deb
  (run.sh installs them itself; do not install anything by hand)
Precondition: ~/orangepi5/work/_out/k15/rga-fu/build-15rgafu1.log ends with "exit 0".

## Command (exactly this, detached)
```
cd ~/orangepi5/work/_out/k15/rga-fu && \
nohup env KREV=15rgafu1 KDIR=out/test/rgafu/debs TAG=fu1 STOCK=0 PH="info compliance regress cases" bash tools/run.sh \
  > ~/orangepi5/work/_out/k15/rga-fu/run-fu1.nohup.log 2>&1 &
```
The script takes BOARD-LOCK itself (BOARD-WANT/rga-fu while waiting, first come first served), installs and
boot-checks 15rgafu1, runs the session "test" (board dir /var/tmp/rgafu, systemd unit rgafu-run), copies
results to run-fu1/out every 30 s, restores stock 15 (k14/install-check.sh) and checks `uname -v` before it
releases the lock, on every exit path. Stall watchdog: 8 min without new board output; 60 min limit.
Honours BOARD-PAUSE (stops at the next case/phase). The first run pushes ~270 MB of inputs to the board.

## End condition (for your watcher, check at most every 10 min)
- `grep -q 'lock released' ~/orangepi5/work/_out/k15/rga-fu/run-fu1/host.log`, or
- the run.sh process is gone: `ps -eo pid,args | grep '[b]ash tools/run.sh'` prints nothing
  (careful: the rga3-nv15 job uses the same script name; check that no process has cwd
  ~/orangepi5/work/_out/k15/rga-fu: `for p in $(pgrep -x bash); do [ "$(readlink /proc/$p/cwd)" = ~/orangepi5/work/_out/k15/rga-fu ] && echo $p; done` prints nothing).

If host.log ends with "BOARD-PAUSE: paused in session test, rerun to resume" and the lock was released: wait until
work/_out/BOARD-PAUSE is gone and no other agent's BOARD-WANT file is older, then run the same command once more;
it resumes (finished phases and cases are skipped). Record both sessions.
If host.log shows "RESTORE FAILED", "BOOT CHECK FAILED", "INSTALL FAILED", "PREP FAILED", "PUSH FAILED" or
"SESSION FAILED": BLOCKED, report the lines, do nothing else.

## Pass/fail (mechanical)
Run:
```
python3 -I ~/orangepi5/work/_out/k15/rga-fu/tools/check.py ~/orangepi5/work/_out/k15/rga-fu/run-fu1 15rgafu1 \
  | tee ~/orangepi5/work/_out/k15/rga-fu/run-fu1/check.txt
```
Each line is PASS/FAIL/INFO. The job is PASS only if the last line is `OVERALL PASS`. The checks:
1. stock-restored: last `uname -v:` in host.log is "#15 SMP ... Wed Nov  4 20:25:22" and "lock released" present.
2. boot-15rgafu1: boot-15rgafu1.txt shows `#15rgafu1`, warn=0, usb_missing empty, iommu_err=0.
3. rga3-formats: NV15, P010 and NV20 on both RGA3 queues; rga3-controls: hflip/vflip/rotate.
4. compliance-rga2 / compliance-rga3: v4l2-compliance on 15rgafu1 has Failed: 0 and Succeeded = Total.
5. rga2-regress-test, rga3-regress-cases/-gst/-kernel: same results as the rga1 stock baseline.
6. case <id> lines (judge.py, all of tools/cases.txt):
   - f2-*: RGA2 flips/rotations "want X got X" (f2-xr24-h is the old INFO case r2-xr24-h);
   - k3-*/k2-*: crop/compose rectangles as listed and bit-exact contents;
   - s3-*/s2-*: bytesperline values as listed and bit-exact contents;
   - n3-*: NV20 conversions; n3-nv20-r90 must be refused (rc=4);
   - all other ids: the rga3-nv15 regression cases.
   INFO lines (f2-nv12-*, s2-nv12-ref, m2-nv12) never fail the job.
7. dmesg-clean-test: 0 matching lines in out/test/dmesg*.txt.

## Files (already on the host; nothing extra to copy)
run-fu1/host.log, run-fu1/boot-15rgafu1.txt, run-fu1/boot-15.txt, run-fu1/dpkg.txt, run-fu1/dmesg-end.txt,
run-fu1/out/board.log, run-fu1/out/test/ (info.txt, compliance-*.txt, rga2reg*, k12func*, cases.tsv,
<case>.log, <case>.raw, judge.txt, dmesg-*.txt), run-fu1/check.txt.

## Summary must list (run-fu1/RUNNER-SUMMARY.md)
- start/end time, the command, number of sessions (resumes);
- every line of check.txt verbatim;
- the compliance `Total for ...` lines for both nodes;
- any host.log line with STALL, TIMEOUT, FAILED, BOARD-PAUSE;
- the file list (top level of run-fu1 and of out/test).
