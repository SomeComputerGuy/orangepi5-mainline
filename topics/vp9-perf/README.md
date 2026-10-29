# vp9-perf: VDPU381 VP9 performance (count table caching)

- Workspace branch: `opi5/vp9-perf-7.3` (exported 2026-10-29)
- Kernel fork branch: `opi5/vp9-perf` (see PUBLISH.md)
- Sits on: `vp9-conf` (base commit `9cb9c761ed16`)
- Hardware test: yes: measured on the board (see RESULTS.md)
- Next upstream step: send with vp9-conf once the VP9 series is merged
- Patches: 1 = 1 ours, 0 carried from others, 0 local-only

Apply with `git am` in the order listed in [`series`](series), on top of the parent topic (or check out the fork branch). Patch numbers are the position in that order.

## (a) Ours, intended for upstream (`ours/`)

| # | Subject | Author | Link |
|---|---|---|---|
| 0001 | media: rkvdec: vdpu381-vp9: keep the count table cacheable | Arun Iyengar |  |

## Notes, results and test tools

- [notes/RESULTS.md](notes/RESULTS.md)
- [notes/base2.txt](notes/base2.txt)
- [notes/exp1.txt](notes/exp1.txt)
- [notes/md5-slot1.txt](notes/md5-slot1.txt)
- [notes/scripts/baseline.sh](notes/scripts/baseline.sh)
- [notes/scripts/bench.sh](notes/scripts/bench.sh)
- [notes/scripts/experiment.sh](notes/scripts/experiment.sh)
- [notes/scripts/gen.sh](notes/scripts/gen.sh)
- [notes/scripts/md5.sh](notes/scripts/md5.sh)
- [notes/scripts/parse.py](notes/scripts/parse.py)
- [notes/scripts/trace.sh](notes/scripts/trace.sh)
