# dp-irq-retrain: dw-dp: on an IRQ_HPD that reports link loss, retrain with a full pipeline reset under the modeset locks (rate limited)

- Workspace branch: `k15-dpirq` (exported 2026-11-06)
- Kernel fork branch: `opi5/dp-irq-retrain` (see PUBLISH.md)
- Sits on: `image` (base commit `bb1a61971a26`)
- Hardware test: built, NOT yet tested on hardware
- Next upstream step: board A/B against the stock kernel is queued
- Patches: 1 = 1 ours, 0 carried from others, 0 local-only

Apply with `git am` in the order listed in [`series`](series), on top of the parent topic (or check out the fork branch). Patch numbers are the position in that order.

## (a) Ours, intended for upstream (`ours/`)

| # | Subject | Author | Link |
|---|---|---|---|
| 0001 | drm/bridge: synopsys: dw-dp: Retrain a lost link with a pipeline reset | Arun Iyengar |  |

## Notes, results and test tools

- [notes/HANDOFF.md](notes/HANDOFF.md)
- [notes/RUNNER-SUMMARY.md](notes/RUNNER-SUMMARY.md)
- [notes/STATE.md](notes/STATE.md)
- [notes/b2/HANDOFF.md](notes/b2/HANDOFF.md)
- [notes/b2/tools/camcal.sh](notes/b2/tools/camcal.sh)
- [notes/b2/tools/camverdict.py](notes/b2/tools/camverdict.py)
- [notes/b2/tools/check-dpb2.sh](notes/b2/tools/check-dpb2.sh)
- [notes/b2/tools/dpblack-board.sh](notes/b2/tools/dpblack-board.sh)
- [notes/b2/tools/kmsctl.py](notes/b2/tools/kmsctl.py)
- [notes/b2/tools/run-dpb2.sh](notes/b2/tools/run-dpb2.sh)
- [notes/b2/tools/run.sh](notes/b2/tools/run.sh)
- [notes/check.txt](notes/check.txt)
- [notes/tools/camcal.sh](notes/tools/camcal.sh)
- [notes/tools/camverdict.py](notes/tools/camverdict.py)
- [notes/tools/check-dpblack.sh](notes/tools/check-dpblack.sh)
- [notes/tools/dpblack-board.sh](notes/tools/dpblack-board.sh)
- [notes/tools/kmsctl.py](notes/tools/kmsctl.py)
- [notes/tools/run-dpblack.sh](notes/tools/run-dpblack.sh)
- [notes/tools/run.sh](notes/tools/run.sh)
