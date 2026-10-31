# usbdp-keep-usb3: USBDP PHY: keep USB3 running when DP AltMode (pin D) is entered or left

- Workspace branch: `opi5/usbdp-keep-usb3-7.3` (exported 2026-10-31)
- Kernel fork branch: `opi5/usbdp-keep-usb3` (see PUBLISH.md)
- Sits on: `dp-smooth` (base commit `24b75a5854fb`)
- Hardware test: yes: 0 USB3 disconnects over 6 DP exit/entry transitions with read traffic on the dock, 2 runs; in patches/linux (0270)
- Next upstream step: send to linux-phy with the Collabora usbdp series (it fixes "Add USB-C state without DP enabled", not in mainline yet)
- Patches: 1 = 1 ours, 0 carried from others, 0 local-only

Apply with `git am` in the order listed in [`series`](series), on top of the parent topic (or check out the fork branch). Patch numbers are the position in that order.

## (a) Ours, intended for upstream (`ours/`)

| # | Subject | Author | Link |
|---|---|---|---|
| 0001 | phy: rockchip: usbdp: Keep USB3 running when entering or leaving DP AltMode | Arun Iyengar | [link](https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/b6c756709db3ae6f85ef8133de754a8e7b7ec894) |

## Notes, results and test tools

- [notes/RESULTS.md](notes/RESULTS.md)
- [notes/weston/NOTES.md](notes/weston/NOTES.md)
- [notes/weston/logs/testlog-after-fix.txt](notes/weston/logs/testlog-after-fix.txt)
- [notes/weston/logs/testlog-before-fix.txt](notes/weston/logs/testlog-before-fix.txt)
- [notes/weston/scripts/env.sh](notes/weston/scripts/env.sh)
