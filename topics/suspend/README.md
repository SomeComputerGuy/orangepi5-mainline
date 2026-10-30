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
- [notes/tools/resume-delay/resume_delay.c](notes/tools/resume-delay/resume_delay.c)
- [notes/tools/resume-wd/resume_wd.c](notes/tools/resume-wd/resume_wd.c)
- [notes/tools/rtc-set.py](notes/tools/rtc-set.py)
- [notes/tools/susp-check.sh](notes/tools/susp-check.sh)
- [notes/tools/susp-run.sh](notes/tools/susp-run.sh)
