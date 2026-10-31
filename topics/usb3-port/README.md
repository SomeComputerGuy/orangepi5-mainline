# usb3-port: IN THE IMAGE (patches/linux 1501-1504): pair the Type-A USB3 port's EHCI and xHCI ports through a usb-a-connector node and retry SuperSpeed for a device stuck at 480M

- Workspace branch: `opi5/usb3-port-k6-7.3` (exported 2026-10-31)
- Kernel fork branch: `opi5/usb3-port` (see PUBLISH.md)
- Sits on: `image-k6` (base commit `c257cc692edd`)
- Hardware test: yes: a SanDisk Extreme present at boot is moved from 480M to 5000M by the retry; a SanDisk Ultra Fit ignores USB2 resets and needs a VBUS cycle (port VBUS is always on)
- Next upstream step: send to linux-usb
- Patches: 4 = 4 ours, 0 carried from others, 0 local-only

Apply with `git am` in the order listed in [`series`](series), on top of the parent topic (or check out the fork branch). Patch numbers are the position in that order.

## (a) Ours, intended for upstream (`ours/`)

| # | Subject | Author | Link |
|---|---|---|---|
| 0001 | dt-bindings: usb: generic-ehci: Allow describing the root hub ports | Arun Iyengar |  |
| 0002 | usb: core: Pair ports of different hubs through their connector | Arun Iyengar |  |
| 0003 | usb: hub: Retry SuperSpeed for a device stuck on its USB 2.0 peer | Arun Iyengar |  |
| 0004 | arm64: dts: rockchip: Describe the USB3 Type-A connector on Orange Pi 5/5B | Arun Iyengar |  |

## Notes, results and test tools

- [notes/RESULTS.md](notes/RESULTS.md)
- [notes/check-usb3-port.sh](notes/check-usb3-port.sh)
