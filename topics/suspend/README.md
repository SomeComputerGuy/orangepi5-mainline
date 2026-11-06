# suspend: System suspend: analysis, TF-A PHP CRU gate fix, s2idle root cause (RTC minute alarm, patches/linux 1917)

- Workspace branch: `opi5/suspend-7.3` (exported 2026-11-06)
- Kernel fork branch: `opi5/suspend` (see PUBLISH.md)
- Sits on: `board-sata` (base commit `5e33b74b04cf`)
- Hardware test: s2idle works: 47/47 cycles on kernel 10 + 1917, 10/10 on kernel 11 and 10/10 on kernel 12, with the TF-A fix in SPI NOR; one deep (mem) cycle on kernel 12 resumed with every dock device back; more deep cycles pending
- Next upstream step: run the deep-suspend test; send 1917 to linux-rtc (prepared) and the TF-A fix to TF-A Gerrit
- Patches: 0 = 0 ours, 0 carried from others, 0 local-only

Apply with `git am` in the order listed in [`series`](series), on top of the parent topic (or check out the fork branch). Patch numbers are the position in that order.

## Notes, results and test tools

- [notes/ANALYSIS.md](notes/ANALYSIS.md)
- [notes/RESULTS.md](notes/RESULTS.md)
- [notes/TEST-PLAN.md](notes/TEST-PLAN.md)
- [notes/persist-pd1/dmesg.txt](notes/persist-pd1/dmesg.txt)
- [notes/persist-pd1/drives.txt](notes/persist-pd1/drives.txt)
- [notes/proof-susp2/ohci-rpm.txt](notes/proof-susp2/ohci-rpm.txt)
- [notes/proof-susp2/proof-copy-usb/summary.txt](notes/proof-susp2/proof-copy-usb/summary.txt)
- [notes/proof-susp2/proof30/summary.txt](notes/proof-susp2/proof30/summary.txt)
- [notes/proof-susp2/proof50/summary.txt](notes/proof-susp2/proof50/summary.txt)
- [notes/tools/bisect-attempt.sh](notes/tools/bisect-attempt.sh)
- [notes/tools/ohci-rpm-cycles.sh](notes/tools/ohci-rpm-cycles.sh)
- [notes/tools/pd-keep/pd_keep.c](notes/tools/pd-keep/pd_keep.c)
- [notes/tools/pd-keep2/pd_keep2.c](notes/tools/pd-keep2/pd_keep2.c)
- [notes/tools/pd-keep3/pd_keep3.c](notes/tools/pd-keep3/pd_keep3.c)
- [notes/tools/pd-keep4/pd_keep4.c](notes/tools/pd-keep4/pd_keep4.c)
- [notes/tools/pm-exclude/pm_exclude.c](notes/tools/pm-exclude/pm_exclude.c)
- [notes/tools/pm-marker/pm_marker.c](notes/tools/pm-marker/pm_marker.c)
- [notes/tools/resume-delay/resume_delay.c](notes/tools/resume-delay/resume_delay.c)
- [notes/tools/resume-wd/resume_wd.c](notes/tools/resume-wd/resume_wd.c)
- [notes/tools/rtc-alarm-selftest.sh](notes/tools/rtc-alarm-selftest.sh)
- [notes/tools/rtc-set.py](notes/tools/rtc-set.py)
- [notes/tools/s2idle-cycles.sh](notes/tools/s2idle-cycles.sh)
- [notes/tools/s2idle-temp.sh](notes/tools/s2idle-temp.sh)
- [notes/tools/susp-check.sh](notes/tools/susp-check.sh)
- [notes/tools/susp-run.sh](notes/tools/susp-run.sh)
- [notes/tools/xhci-delay/xhci_delay.c](notes/tools/xhci-delay/xhci_delay.c)
