# hdmi-wedge: dw-hdmi-qp: wait for the video input clock to stop on a modeset (HDMI0 "No Signal" wedge after leaving YCbCr 4:2:0)

- Workspace branch: `opi5/hdmi-wedge-7.3` (exported 2026-11-05)
- Kernel fork branch: `opi5/hdmi-wedge` (see PUBLISH.md)
- Sits on: `hdmi-frl` (base commit `4c18b22e48cf`)
- Hardware test: yes: trigger 10/10, 4:2:0->1080p 5/5, run-2 order 13/13, regressions good (camera + IPI lock bit); in patches/linux (1208-1209)
- Next upstream step: send 1208 (bridge helper) + 1209 (Rockchip glue) together to dri-devel + linux-rockchip
- Patches: 2 = 2 ours, 0 carried from others, 0 local-only

Apply with `git am` in the order listed in [`series`](series), on top of the parent topic (or check out the fork branch). Patch numbers are the position in that order.

## (a) Ours, intended for upstream (`ours/`)

| # | Subject | Author | Link |
|---|---|---|---|
| 0001 | drm/bridge: dw-hdmi-qp: Add helper to wait for the video input clock to stop | Arun Iyengar |  |
| 0002 | drm/rockchip: dw_hdmi_qp: Let the controller see DCLK stop on a modeset | Arun Iyengar |  |

## Notes, results and test tools

- [notes/RESULTS.md](notes/RESULTS.md)
- [notes/repro/hdmipoke.py](notes/repro/hdmipoke.py)
- [notes/repro/hdmiregs.py](notes/repro/hdmiregs.py)
- [notes/repro/hunt.sh](notes/repro/hunt.sh)
- [notes/repro/hunt2.sh](notes/repro/hunt2.sh)
- [notes/repro/minimal-repro.sh](notes/repro/minimal-repro.sh)
- [notes/repro/poke-test.sh](notes/repro/poke-test.sh)
- [notes/repro/recover-test.sh](notes/repro/recover-test.sh)
- [notes/repro/run.sh](notes/repro/run.sh)
- [notes/repro/seq.sh](notes/repro/seq.sh)
- [notes/repro/seqrun.py](notes/repro/seqrun.py)
- [notes/repro/wedge.py](notes/repro/wedge.py)
