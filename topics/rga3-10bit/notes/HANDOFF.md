# JOB rga3-nv15-1 (DEV, ~40 min board time)

RGA fixes + RGA3 features: kernel 7.3.0-15rga1 (branch k15-rga3nv15 = k15-v4 + 4 RGA patches: descriptor
off-by-one, oversized DMA-BUFs on the RGA2, RGA3 NV15/P010, RGA3 rotation/flip).
Kind: DEV (one board turn: baseline on stock 15, install the test kernel, short tests, restore stock 15). No display,
no camera, no TV needed.

## Kernel / debs
- ~/orangepi5/out/test/rga/debs/linux-image-7.3.0-opi5_7.3.0-15rga1_arm64.deb
- ~/orangepi5/out/test/rga/debs/linux-headers-7.3.0-opi5_7.3.0-15rga1_arm64.deb
  (run.sh installs them itself; do not install anything by hand)

## Command (exactly this, detached)
```
cd ~/orangepi5/work/_out/k15/rga3-nv15 && \
nohup env KREV=15rga1 KDIR=out/test/rga/debs TAG=rga1 bash tools/run.sh \
  > ~/orangepi5/work/_out/k15/rga3-nv15/run-rga1.nohup.log 2>&1 &
```
The script makes the test inputs on the host (tools/prep.py, ~15 s), takes BOARD-LOCK itself (BOARD-WANT/rga3-nv15
while waiting, first come first served), runs a baseline session on stock 15 (v4l2-compliance, RGA2 + RGA3
regressions, the new cases), installs and boot-checks 15rga1, runs the same session again, copies results to
run-rga1/out every 30 s, restores stock 15 (k14/install-check.sh) and checks `uname -v` before it releases the lock,
on every exit path. Stall watchdog: 8 min without new board output; 60 min limit per session. Honours BOARD-PAUSE
(stops at the next case/phase).

## End condition (for your watcher, check at most every 10 min)
- `grep -q 'lock released' ~/orangepi5/work/_out/k15/rga3-nv15/run-rga1/host.log`, or
- the run.sh process is gone: `ps -eo pid,args | grep '[b]ash tools/run.sh'` prints nothing.

If host.log ends with "BOARD-PAUSE: paused in session ..., rerun to resume" and the lock was released: wait until
work/_out/BOARD-PAUSE is gone and no other agent's BOARD-WANT file is older, then run the same command once more; it
resumes (finished phases and cases are skipped, a finished stock session is not repeated). Record both sessions.
If host.log shows "RESTORE FAILED", "BOOT CHECK FAILED", "INSTALL FAILED", "PREP FAILED" or "PUSH FAILED": BLOCKED,
report the lines, do nothing else.

## Pass/fail (mechanical)
Run:
```
python3 -I ~/orangepi5/work/_out/k15/rga3-nv15/tools/check.py ~/orangepi5/work/_out/k15/rga3-nv15/run-rga1 15rga1 \
  | tee ~/orangepi5/work/_out/k15/rga3-nv15/run-rga1/check.txt
```
Each line is PASS/FAIL/INFO. The job is PASS only if the last line is `OVERALL PASS`. The checks:
1. stock-restored: last `uname -v:` in host.log is "#15 SMP ... Wed Nov  4 20:25:22" and "lock released" is present.
2. boot-15rga1: boot-15rga1.txt shows `#15rga1`, warn=0, usb_missing empty, iommu_err=0.
3. rga3-formats / rga3-controls: the RGA3 node lists NV15 and P010 on OUTPUT and CAPTURE, and the
   horizontal_flip / vertical_flip / rotate controls (out/test/info.txt).
4. compliance-rga2 / compliance-rga3: v4l2-compliance on the test kernel has Failed: 0 and no more failures than
   on stock 15 (out/{stock,test}/compliance-*.txt). Totals may grow (new controls).
5. rga2-regress-test: the k15 RGA2 regression (k14/datasheet/d2/rga2-regress-judge.py) is OVERALL PASS.
6. rga3-regress-cases / -gst / -kernel: the k12 RGA3 conversion matrix (k12/rga3/board-tests.sh func) gives the
   same per-frame CRC set per case as on stock 15, rc=0, errors 0; v4l2convert outputs identical; 0 kernel rga errors.
7. case <id> (one line per case in tools/cases.txt, judge.py, test kernel only):
   - NV15 -> NV12 of decoded HEVC Main10, VP9 Profile 2 and the WPP_A_ericsson_MAIN10_2 conformance stream:
     PSNR >= 45 dB against the FFmpeg software decode / 4 and max |diff| <= 1 (truncation or rounding both pass);
   - NV15 -> P010, NV15 -> NV15, P010 -> NV15: bit-exact against the FFmpeg software decode;
   - P010 -> NV12 as NV15 -> NV12; NV12 -> P010 >= 45 dB (10-bit);
   - NV15 -> XR24 with BT.709 / BT.2020 limited range: >= 30 dB against a float reference;
   - scaling (NV15 1080p -> NV12 720p; NV12 rot90 + 2:1 scale): >= 30 dB against FFmpeg bicubic;
   - rotation/flip on the RGA3 (XR24, NV12, NV15->P010, NV16 flips): bit-exact against the software transform
     (flips applied to the source, then clockwise rotation); the line names the transform the hardware produced;
   - r-nv16-r90: the rotate=90 control is refused for NV16 (exit code 4);
   - oversized imported DMA-BUFs (RGA2 +1 MiB, RGA3 +4 MiB, RGA3 NV15 +1 MiB): accepted and output correct;
   - m2-nm12: RGA2 NV12M (two memory planes) gives the same output as NV12.
   INFO lines (not criteria): the stock-15 baseline of every case (most new cases fail there: expected) and the
   RGA2 rotation cases r2-*.
8. dmesg-clean-test: 0 lines with WARNING/BUG:/Oops/Call trace/IOMMU fault/page fault/job timed out/error
   interrupt/"Failed to map video buffer"/"soft reset timed out" in any out/test/**/dmesg*.txt.

## Files (already on the host; nothing extra to copy)
run-rga1/host.log, run-rga1/boot-15rga1.txt, run-rga1/boot-15.txt, run-rga1/dpkg.txt, run-rga1/dmesg-end.txt,
run-rga1/out/board.log, run-rga1/out/{stock,test}/ (info.txt, compliance-rga2.txt, compliance-rga3.txt, rga2reg/,
rga2reg-verdict.txt, k12func/func.txt, cases.tsv, <case>.log, <case>.raw, judge.txt, dmesg-*.txt), run-rga1/check.txt.

## Summary must list (run-rga1/RUNNER-SUMMARY.md)
- start/end time, the command, number of sessions (resumes);
- every line of check.txt verbatim (INFO lines included);
- the compliance `Total for ...` lines of stock and test for both nodes;
- any host.log line with STALL, TIMEOUT, FAILED, BOARD-PAUSE;
- the file list (top level of run-rga1 and of out/test).

Precondition: build-15rga1.log ends with "exit 0" (it does: built 2026-11-05 23:12).
