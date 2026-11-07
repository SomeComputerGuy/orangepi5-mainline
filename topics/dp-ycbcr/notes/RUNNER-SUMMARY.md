# RUNNER-SUMMARY 002-dp-ycc (SUMMARISE-ONLY)
Result: PASS (run script ended normally; "all units done (test 15ycc1)"; no cases judged by the runner)
Log: ~/orangepi5/work/_out/k15/dp-ycc/ycc.log, last write 2026-11-06 04:30:02, no ycc.sh process alive. Dev unit finished 12:15:26 (Nov 5), test unit 04:30:02.
Stock restored: "restore rc=0: 7.3.0-opi5 #15 SMP PREEMPT_DYNAMIC Wed Nov  4 20:25:22 UTC 2026 usb_missing=" and "lock released" (04:30:02). (BOARD-LOCK file currently exists but belongs to another job.)
Last 20 log lines:
dpkg=0
ii 7.3.0-15
initrd=86102328
7.3.0-opi5 #15 SMP PREEMPT_DYNAMIC Wed Nov  4 20:25:22 UTC 2026
warn=0
resets=axi ahb dclk_vp0 dclk_vp1 dclk_vp2 dclk_vp3 
root=/dev/sda1 sata=1
usb3=3
usb_missing=
card0-DP-1 connected
card0-HDMI-A-1 connected
card 0: hdmi0 [hdmi0], device 0: fddf0000.i2s-i2s-hifi i2s-hifi-0 [fddf0000.i2s-i2s-hifi i2s-hifi-0]
card 1: dp0 [dp0], device 0: fddb0000.spdif-tx-spdif-hifi spdif-hifi-0 [fddb0000.spdif-tx-spdif-hifi spdif-hifi-0]
devlink_fail=0
deferred=0
failed_units=0
rtc=rtc-hym8563 6-0051
[04:30:02] restore rc=0: 7.3.0-opi5 #15 SMP PREEMPT_DYNAMIC Wed Nov  4 20:25:22 UTC 2026 usb_missing=
[04:30:02] lock released
[04:30:02] all units done (test 15ycc1)
Result files: cmp.md (04:30:10), REPORT.md (04:31:53), list-15ycc1.json, run-15ycc1-* dirs/logs, dev-*.out, test-ycc1.out.
cmp.md:

### before: stock 7.3.0-15 (370 cases)

| requested | cases | commit accepted | rejected (errno) | bus format = request | camera GOOD (of accepted) |
|---|---|---|---|---|---|
| AUTO | 74 | 74 | 0  | 74/74 | 74/74 |
| RGB | 74 | 74 | 0  | 74/74 | 74/74 |
| 444 | 74 | 74 | 0  | 0/74 | 74/74 |
| 422 | 74 | 74 | 0  | 0/74 | 74/74 |
| 420 | 74 | 74 | 0  | 0/74 | 74/74 |

### after: 15ycc1 (k15-dpycc) (370 cases)

| requested | cases | commit accepted | rejected (errno) | bus format = request | camera GOOD (of accepted) |
|---|---|---|---|---|---|
| AUTO | 74 | 74 | 0  | 74/74 | 74/74 |
| RGB | 74 | 74 | 0  | 74/74 | 74/74 |
| 444 | 74 | 74 | 0  | 74/74 | 74/74 |
| 422 | 74 | 74 | 0  | 74/74 | 74/74 |
| 420 | 74 | 0 | 74 22 | 0/0 | 0/0 |

### after: accepted cases that are not GOOD or not the requested format


cases in before but not after: 0 
