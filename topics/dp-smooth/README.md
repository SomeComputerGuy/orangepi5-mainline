# dp-smooth: USB-C DP alt-mode re-train fixes (typec DP HPD notify, dw-dp OOB HPD as IRQ_HPD, usbdp lane re-enable)

- Workspace branch: `opi5/dp-smooth-7.3` (exported 2026-10-30)
- Kernel fork branch: `opi5/dp-smooth` (see PUBLISH.md)
- Sits on: `integration` (base commit `1afa8d268718`)
- Hardware test: yes: pin-assignment retrain fixed on the board; in patches/linux
- Next upstream step: send per subsystem (usb, dri-devel, phy)
- Patches: 3 = 3 ours, 0 carried from others, 0 local-only

Apply with `git am` in the order listed in [`series`](series), on top of the parent topic (or check out the fork branch). Patch numbers are the position in that order.

## (a) Ours, intended for upstream (`ours/`)

| # | Subject | Author | Link |
|---|---|---|---|
| 0001 | phy: rockchip: usbdp: Re-enable DP lanes after a re-init with DP powered on | Arun Iyengar |  |
| 0002 | drm/bridge: synopsys: dw-dp: Treat OOB HPD events with HPD high as IRQ_HPD | Arun Iyengar |  |
| 0003 | usb: typec: altmodes/displayport: Notify HPD after reconfiguring with HPD high | Arun Iyengar |  |

## Notes, results and test tools

- [notes/RESULTS.md](notes/RESULTS.md)
- [notes/TESTING.md](notes/TESTING.md)
- [notes/meas/idle_c0.txt](notes/meas/idle_c0.txt)
- [notes/meas/idle_c1.txt](notes/meas/idle_c1.txt)
- [notes/tools/cadence.py](notes/tools/cadence.py)
- [notes/tools/flipmeasure.sh](notes/tools/flipmeasure.sh)
- [notes/tools/idlecommits.sh](notes/tools/idlecommits.sh)
- [notes/tools/jitter.sh](notes/tools/jitter.sh)
- [notes/tools/vblwait.c](notes/tools/vblwait.c)
