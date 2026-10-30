# suspend: System suspend analysis (TF-A PHP CRU gate fix)

- Workspace branch: `opi5/suspend-7.3` (exported 2026-10-30)
- Kernel fork branch: `opi5/suspend` (see PUBLISH.md)
- Sits on: `board-sata` (base commit `5e33b74b04cf`)
- Hardware test: not run (analysis only; TF-A patch in patches/tf-a)
- Next upstream step: test deep suspend on the board; send the TF-A fix to TF-A Gerrit
- Patches: 0 = 0 ours, 0 carried from others, 0 local-only

Apply with `git am` in the order listed in [`series`](series), on top of the parent topic (or check out the fork branch). Patch numbers are the position in that order.

## Notes, results and test tools

- [notes/ANALYSIS.md](notes/ANALYSIS.md)
- [notes/RESULTS.md](notes/RESULTS.md)
- [notes/TEST-PLAN.md](notes/TEST-PLAN.md)
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
- [notes/tools/susp-check.sh](notes/tools/susp-check.sh)
- [notes/tools/susp-run.sh](notes/tools/susp-run.sh)
- [notes/tools/xhci-delay/xhci_delay.c](notes/tools/xhci-delay/xhci_delay.c)
