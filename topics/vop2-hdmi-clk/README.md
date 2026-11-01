# vop2-hdmi-clk: VOP2 HDMI clocking on RK3588: uninitialised dividers, HDMI sync polarity, DCLK source chosen from the FRL state, reject modes the CRU cannot clock exactly

- Workspace branch: `opi5/vop2-hdmi-clk-7.3` (exported 2026-11-01)
- Kernel fork branch: `opi5/vop2-hdmi-clk` (see PUBLISH.md)
- Sits on: `hdmi-frl` (base commit `4c18b22e48cf`)
- Hardware test: yes: pixel clock measured from vblank timestamps (~20 ppm) + camera over TMDS/FRL modes, wedge trigger 10/10; in patches/linux (1211, 1212, 1214, 1215)
- Next upstream step: send to dri-devel + linux-rockchip (VOP2 maintainers); 1214/1215 use the FRL series' state, so they go after it
- Patches: 4 = 4 ours, 0 carried from others, 0 local-only

Apply with `git am` in the order listed in [`series`](series), on top of the parent topic (or check out the fork branch). Patch numbers are the position in that order.

## (a) Ours, intended for upstream (`ours/`)

| # | Subject | Author | Link |
|---|---|---|---|
| 0001 | drm/rockchip: vop2: Don't use uninitialised dividers on RK3588 | Arun Iyengar |  |
| 0002 | drm/rockchip: vop2: Fix the HDMI sync polarity on RK3588 | Arun Iyengar |  |
| 0003 | drm/rockchip: vop2: Don't take DCLK from the HDMI PHY PLL in FRL mode | Arun Iyengar |  |
| 0004 | drm/rockchip: vop2: Reject HDMI modes the CRU cannot clock exactly | Arun Iyengar |  |

## Notes, results and test tools

- [notes/RESULTS.md](notes/RESULTS.md)
- [notes/tools/clkrun.py](notes/tools/clkrun.py)
- [notes/tools/hdmiregs-safe.sh](notes/tools/hdmiregs-safe.sh)
- [notes/tools/matrix.sh](notes/tools/matrix.sh)
- [notes/tools/snap.py](notes/tools/snap.py)
- [notes/tools/vblank.py](notes/tools/vblank.py)
