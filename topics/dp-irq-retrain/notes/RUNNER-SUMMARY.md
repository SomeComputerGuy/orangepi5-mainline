# RUNNER-SUMMARY dp-black-1
Start 07:42:34Z End 10:01:51Z 2026-11-06. Command: nohup bash tools/run-dpblack.sh. Result: FAIL (OVERALL FAIL, black-rate check only; not INCONCLUSIVE: baseline 1/180 black).
Anomaly: block B2 first failed 08:27:58 'BLOCK FAILED: B2 rc=1' (2 s after start; run-B2/host.log overwritten by the rerun, cause not retained). The same command was restarted by someone else at 08:31:37 (not by this runner) and resumed; B2 then completed. Board sessions (session start lines): 7. Stock restored at end: #15 SMP ... Wed Nov 4 20:25:22; BOARD-LOCK absent.

## check.txt
PASS stock-restored-B1: #15 SMP PREEMPT_DYNAMIC Wed Nov  4 20:25:22 UTC 2026
PASS boot-B1: #15 SMP warn=0 usb_missing empty
PASS stock-restored-B2: #15 SMP PREEMPT_DYNAMIC Wed Nov  4 20:25:22 UTC 2026
PASS boot-B2: #15 SMP warn=0 usb_missing empty
PASS stock-restored-B3: #15 SMP PREEMPT_DYNAMIC Wed Nov  4 20:25:22 UTC 2026
PASS boot-B3: #15 SMP warn=0 usb_missing empty
PASS iterations-baseline(15): 180 rows (need >= 170)
PASS valid-verdicts-baseline(15): 180 (need >= 150)
INFO black-baseline(15): 1 of 180 valid; persistent non-GOOD 1; failed commits 0
INFO log-baseline(15): error lines 0, types []; 'Get hpd irq - short' 384, 'new mode:' 384
INFO nongood-baseline(15): B1 27	DP=BLACK	DP2=BLACK	HDMI=GOOD	commit=1	dpcd=4100777781031111 pwr=01 esi=41000000 | dpcd=4100777701031111 pwr=01 esi=41000000	err=0
PASS stock-restored-F1: #15 SMP PREEMPT_DYNAMIC Wed Nov  4 20:25:22 UTC 2026
PASS boot-F1: #15dpirq1 SMP warn=0 usb_missing empty
PASS stock-restored-F2: #15 SMP PREEMPT_DYNAMIC Wed Nov  4 20:25:22 UTC 2026
PASS boot-F2: #15dpirq1 SMP warn=0 usb_missing empty
PASS stock-restored-F3: #15 SMP PREEMPT_DYNAMIC Wed Nov  4 20:25:22 UTC 2026
PASS boot-F3: #15dpirq1 SMP warn=0 usb_missing empty
PASS iterations-fix(15dpirq1): 180 rows (need >= 170)
PASS valid-verdicts-fix(15dpirq1): 180 (need >= 150)
INFO black-fix(15dpirq1): 1 of 180 valid; persistent non-GOOD 1; failed commits 0
INFO log-fix(15dpirq1): error lines 0, types []; 'Get hpd irq - short' 384, 'OOB HPD event' 384, 'link status:' 384, 'new mode:' 384
INFO nongood-fix(15dpirq1): F2 53	DP=BLACK	DP2=BLACK	HDMI=GOOD	commit=1	dpcd=4100777701031111 pwr=01 esi=41000000 | dpcd=4100777701031111 pwr=01 esi=41000000	err=0
PASS no-new-errors: fix-only error types: none (baseline [])
PASS commits: failed commits fix 0 vs baseline 0
FAIL black-rate: baseline 1/180, fix 1/180, one-sided Fisher p=0.7507 (need fix < baseline, p < 0.05)
OVERALL FAIL

## non-GOOD DP rows
B1: 27 DP=BLACK DP2=BLACK ...
F2: 53 DP=BLACK DP2=BLACK ...
(full rows in INFO nongood lines above)
## STALL/TIMEOUT/etc lines: only 'BLOCK FAILED: B2 rc=1' (above)
Files: run-dpblack.log, run-dpblack.nohup.log, check.txt, run-{B1,F1,B2,F2,B3,F3}/
