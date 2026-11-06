# dp-ycbcr: dw-dp: honour the connector colour format (YCbCr 4:4:4/4:2:2/4:2:0 output), 4:2:0 only for 4:2:0-capable modes, bus format negotiation fails with -EINVAL

- Workspace branch: `k15-dpycc` (exported 2026-11-06)
- Kernel fork branch: `opi5/dp-ycbcr` (see PUBLISH.md)
- Sits on: `image` (base commit `bb1a61971a26`)
- Hardware test: built and booted (part of the 7.3.0-16 candidate); the full DP YCbCr camera matrix is still running
- Next upstream step: finish the board matrix
- Patches: 4 = 4 ours, 0 carried from others, 0 local-only

Apply with `git am` in the order listed in [`series`](series), on top of the parent topic (or check out the fork branch). Patch numbers are the position in that order.

## (a) Ours, intended for upstream (`ours/`)

| # | Subject | Author | Link |
|---|---|---|---|
| 0001 | drm/bridge: synopsys: dw-dp: Offer YCbCr 4:2:0 only for 4:2:0 capable modes | Arun Iyengar |  |
| 0002 | drm/bridge: synopsys: dw-dp: Honour the connector color format | Arun Iyengar |  |
| 0003 | fixup! drm/rockchip: dw_dp: Attach the "color format" connector property | Arun Iyengar |  |
| 0004 | drm/bridge: Fail an unsatisfiable bus format negotiation with -EINVAL | Arun Iyengar |  |

## Notes, results and test tools

- [notes/tools/all.sh](notes/tools/all.sh)
- [notes/tools/ana.py](notes/tools/ana.py)
- [notes/tools/camcheck.py](notes/tools/camcheck.py)
- [notes/tools/camcheck_shared.py](notes/tools/camcheck_shared.py)
- [notes/tools/cmp.py](notes/tools/cmp.py)
- [notes/tools/dmodel.py](notes/tools/dmodel.py)
- [notes/tools/fmtck.py](notes/tools/fmtck.py)
- [notes/tools/hmodel.py](notes/tools/hmodel.py)
- [notes/tools/kmsctl.py](notes/tools/kmsctl.py)
- [notes/tools/levels.py](notes/tools/levels.py)
- [notes/tools/mklist.py](notes/tools/mklist.py)
- [notes/tools/probetab.py](notes/tools/probetab.py)
- [notes/tools/t1cmp.py](notes/tools/t1cmp.py)
- [notes/tools/ycc.sh](notes/tools/ycc.sh)
