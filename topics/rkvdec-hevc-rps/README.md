# rkvdec-hevc-rps: rkvdec HEVC short-term RPS control handling fixes (allocation failure, rebuild, request controls, bounds)

- Workspace branch: `opi5/rkvdec-hevc-rps-7.3` (exported 2026-10-31)
- Kernel fork branch: `opi5/rkvdec-hevc-rps` (see PUBLISH.md)
- Sits on: `integration` (base commit `1afa8d268718`)
- Hardware test: see notes/TESTING.md
- Next upstream step: send to linux-media
- Patches: 6 = 6 ours, 0 carried from others, 0 local-only

Apply with `git am` in the order listed in [`series`](series), on top of the parent topic (or check out the fork branch). Patch numbers are the position in that order.

## (a) Ours, intended for upstream (`ours/`)

| # | Subject | Author | Link |
|---|---|---|---|
| 0001 | media: rkvdec: hevc: Apply the request controls before reading them | Arun Iyengar |  |
| 0002 | media: rkvdec: hevc: Notice SPS RPS controls set to their current value | Arun Iyengar |  |
| 0003 | media: rkvdec: hevc: Don't read past the end of the SPS RPS controls | Arun Iyengar |  |
| 0004 | media: rkvdec: vdpu383: Complete the request when rejecting a HEVC job | Arun Iyengar |  |
| 0005 | media: rkvdec: hevc: Rebuild the short-term RPS table when any set changes | Arun Iyengar |  |
| 0006 | media: rkvdec: hevc: Handle allocation failure of the short-term RPS sets | Arun Iyengar |  |

## Notes, results and test tools

- [notes/TESTING.md](notes/TESTING.md)
- [notes/scripts/board-hevc-extsps.sh](notes/scripts/board-hevc-extsps.sh)
- [notes/scripts/board-hevc-rps.sh](notes/scripts/board-hevc-rps.sh)
- [notes/scripts/build-dropin.sh](notes/scripts/build-dropin.sh)
- [notes/tools/spsdump-JCT-VC-HEVC_V1.txt](notes/tools/spsdump-JCT-VC-HEVC_V1.txt)
- [notes/tools/spsdump-all-JCT-VC-HEVC_V1.txt](notes/tools/spsdump-all-JCT-VC-HEVC_V1.txt)
- [notes/tools/spsdump.c](notes/tools/spsdump.c)
- [notes/tools/spsdump.sh](notes/tools/spsdump.sh)
