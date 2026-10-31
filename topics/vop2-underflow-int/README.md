# vop2-underflow-int: VOP2: balance window fetches across both AXI ports on RK3588, rate-limit POST_BUF_EMPTY

- Workspace branch: `opi5/vop2-underflow-int-7.3` (exported 2026-10-31)
- Kernel fork branch: `opi5/vop2-underflow-int` (see PUBLISH.md)
- Sits on: `integration` (base commit `1afa8d268718`)
- Hardware test: yes: 4K120 + overlay and dual display with 0 underflows; in patches/linux (1301-1302)
- Next upstream step: send to dri-devel + linux-rockchip
- Patches: 2 = 2 ours, 0 carried from others, 0 local-only

Apply with `git am` in the order listed in [`series`](series), on top of the parent topic (or check out the fork branch). Patch numbers are the position in that order.

## (a) Ours, intended for upstream (`ours/`)

| # | Subject | Author | Link |
|---|---|---|---|
| 0001 | drm/rockchip: vop2: Balance window fetches across both AXI ports on RK3588 | Arun Iyengar |  |
| 0002 | drm/rockchip: vop2: Report POST_BUF_EMPTY at most once per frame | Arun Iyengar |  |

## Notes, results and test tools

- [notes/RESULTS-interim-1.md](notes/RESULTS-interim-1.md)
- [notes/RESULTS.md](notes/RESULTS.md)
- [notes/opi5ssh.sh](notes/opi5ssh.sh)
- [notes/tools/clkpoke/clkpoke.c](notes/tools/clkpoke/clkpoke.c)
- [notes/tools/ddrbw.c](notes/tools/ddrbw.c)
- [notes/tools/devmem.c](notes/tools/devmem.c)
- [notes/tools/irqrate.sh](notes/tools/irqrate.sh)
- [notes/tools/memhog.c](notes/tools/memhog.c)
- [notes/tools/planetest.c](notes/tools/planetest.c)
- [notes/tools/play.sh](notes/tools/play.sh)
- [notes/tools/portload.py](notes/tools/portload.py)
- [notes/tools/qos.sh](notes/tools/qos.sh)
- [notes/tools/rc.sh](notes/tools/rc.sh)
- [notes/tools/regpeek/regpeek.c](notes/tools/regpeek/regpeek.c)
- [notes/tools/regpeek3/regpeek.c](notes/tools/regpeek3/regpeek.c)
- [notes/tools/rt.sh](notes/tools/rt.sh)
- [notes/tools/rtb.sh](notes/tools/rtb.sh)
- [notes/tools/rtl.sh](notes/tools/rtl.sh)
- [notes/tools/runtest.sh](notes/tools/runtest.sh)
- [notes/tools/vm.sh](notes/tools/vm.sh)
- [notes/tools/watch.sh](notes/tools/watch.sh)
