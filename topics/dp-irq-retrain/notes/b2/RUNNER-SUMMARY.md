# RUNNER-SUMMARY dp-black-2 (SUMMARISE-ONLY)
Job: 048-dp-black-2. Start 00:35:32, end 07:58:28 (run-dpb2.log "run-dpb2: finished").
Command (run earlier): cd b2 && nohup bash tools/run-dpb2.sh > run-dpb2.nohup.log 2>&1 &
Checks run now: bash tools/check-dpb2.sh | tee check.txt  -> last line OVERALL FAIL (also INCONCLUSIVE on black-rate).
Board sessions per block (lines "session start" in run-dpb2.log): D1..D7 = 1 each (7 total), each rc=0, 200 of 200 done.

## Stock-restore check
check-dpb2.sh reports FAIL stock-restored-D1..D7 (last uname -v "#15 SMP PREEMPT_DYNAMIC Wed Nov  4 20:25:22 UTC 2026"; lock released: True).
Stock changed to kernel 16 after the run, so per coordinator the check was taken from the logs only: every host.log has
"restoring stock 15 before releasing the lock", "uname -v: #15 ... Nov  4 20:25:22", "lock released" (all 7 blocks). Board not checked.
The 7 stock-restored FAIL lines are in check.txt and count toward OVERALL FAIL.

## check.txt verbatim
```
FAIL stock-restored-D1: last uname -v: #15 SMP PREEMPT_DYNAMIC Wed Nov  4 20:25:22 UTC 2026; lock released: True
PASS boot-D1: #16dpb1 SMP warn=0 usb_missing empty
FAIL stock-restored-D2: last uname -v: #15 SMP PREEMPT_DYNAMIC Wed Nov  4 20:25:22 UTC 2026; lock released: True
PASS boot-D2: #16dpb1 SMP warn=0 usb_missing empty
FAIL stock-restored-D3: last uname -v: #15 SMP PREEMPT_DYNAMIC Wed Nov  4 20:25:22 UTC 2026; lock released: True
PASS boot-D3: #16dpb1 SMP warn=0 usb_missing empty
FAIL stock-restored-D4: last uname -v: #15 SMP PREEMPT_DYNAMIC Wed Nov  4 20:25:22 UTC 2026; lock released: True
PASS boot-D4: #16dpb1 SMP warn=0 usb_missing empty
FAIL stock-restored-D5: last uname -v: #15 SMP PREEMPT_DYNAMIC Wed Nov  4 20:25:22 UTC 2026; lock released: True
PASS boot-D5: #16dpb1 SMP warn=0 usb_missing empty
FAIL stock-restored-D6: last uname -v: #15 SMP PREEMPT_DYNAMIC Wed Nov  4 20:25:22 UTC 2026; lock released: True
PASS boot-D6: #16dpb1 SMP warn=0 usb_missing empty
FAIL stock-restored-D7: last uname -v: #15 SMP PREEMPT_DYNAMIC Wed Nov  4 20:25:22 UTC 2026; lock released: True
PASS boot-D7: #16dpb1 SMP warn=0 usb_missing empty
PASS valid-verdicts-gate0(old order): 700 of 700 rows (need >= 600)
INFO black-gate0(old order): 0 of 700 valid; persistent non-GOOD 0; HDMI non-GOOD 0; failed commits 0
INFO fifo-overflow-gate0(old order): iterations with an overflow 283 (in the client's modeset 0)
INFO log-gate0(old order): error lines 0, types []
INFO black-with-overflow-gate0(old order): 0 of 0 black iterations had an overflow in the client's modeset
PASS valid-verdicts-gate1(fix): 700 of 700 rows (need >= 600)
INFO black-gate1(fix): 0 of 700 valid; persistent non-GOOD 0; HDMI non-GOOD 0; failed commits 0
INFO fifo-overflow-gate1(fix): iterations with an overflow 0 (in the client's modeset 0)
INFO log-gate1(fix): error lines 0, types []
INFO black-with-overflow-gate1(fix): 0 of 0 black iterations had an overflow in the client's modeset
PASS iterations: 1400 rows (need >= 1300)
PASS kernel-warnings: 0 WARNING/BUG/Oops/Call trace lines in kmsg-all*.txt (need 0)
PASS no-new-errors: gate1-only error types: none (gate0 [])
PASS fifo-overflow-gate1: 0 gate=1 iterations with a video FIFO overflow (need 0)
PASS commits: failed commits gate1 0 vs gate0 0
INFO black-rate: gate1 0/700, reference 2/1060 (gate0 0/700 + dp-black-1 2/360), one-sided Fisher p=0.3626 (lower but p >= 0.05: INCONCLUSIVE)
OVERALL FAIL
```

## iter.tsv rows with DP not DP=GOOD
run-D4 (row 25 in file):
25	DP=WRONGCASE	DP2=GOOD	HDMI=GOOD	commit=1	dpcd=4100777701031111 pwr=01 esi=41000000 | dpcd=4100777701031111 pwr=01 esi=41000000	err=0	gate=0	ovf=0	ovfall=0

## ovfall not 0 rows
gate=0: 283
gate=1: 0

## Rows per block
run-D2/out/iter.tsv:200
run-D7/out/iter.tsv:200
run-D1/out/iter.tsv:200
run-D3/out/iter.tsv:200
run-D6/out/iter.tsv:200
run-D5/out/iter.tsv:200
run-D4/out/iter.tsv:200

## STALL/TIMEOUT/FAILED/BOARD-PAUSE/BOARD-WANT/PAUSED/CALIBRATION FAILED
Only hit: first line of each run-D*/host.log: "TEST run: waiting for a free lock and an empty BOARD-WANT/" (normal start line). No STALL, TIMEOUT, FAILED, PAUSED, CALIBRATION FAILED lines in run-dpb2.log, host.log or board.log.

## Files
b2/: check.txt HANDOFF.md run-D1 run-D2 run-D3 run-D4 run-D5 run-D6 run-D7 run-dpb2.log run-dpb2.nohup.log RUNNER-SUMMARY.md tools 
run-D1/: boot-15.txt boot-16dpb1.txt dmesg-end.txt dpkg.txt host.log out restore15.log  | out/: board.log cal cal-1.log cal-2.log iter.tsv kmsg-all.txt 
run-D2/: boot-15.txt boot-16dpb1.txt dmesg-end.txt dpkg.txt host.log out restore15.log  | out/: board.log cal cal-1.log iter.tsv kmsg-all.txt 
run-D3/: boot-15.txt boot-16dpb1.txt dmesg-end.txt dpkg.txt host.log out restore15.log  | out/: board.log cal cal-1.log iter.tsv kmsg-all.txt 
run-D4/: boot-15.txt boot-16dpb1.txt dmesg-end.txt dpkg.txt host.log out restore15.log  | out/: board.log cal cal-1.log iter.tsv kmsg-all.txt 
run-D5/: boot-15.txt boot-16dpb1.txt dmesg-end.txt dpkg.txt host.log out restore15.log  | out/: board.log cal cal-1.log iter.tsv kmsg-all.txt 
run-D6/: boot-15.txt boot-16dpb1.txt dmesg-end.txt dpkg.txt host.log out restore15.log  | out/: board.log cal cal-1.log iter.tsv kmsg-all.txt 
run-D7/: boot-15.txt boot-16dpb1.txt dmesg-end.txt dpkg.txt host.log out restore15.log  | out/: board.log cal cal-1.log iter.tsv kmsg-all.txt 
- 2026-11-07 coordinator: check-dpb2.sh stock-restore check now accepts any stock kernel ("#N SMP"); rerun: all 7 stock-restored PASS, OVERALL INCONCLUSIVE.
