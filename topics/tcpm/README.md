# tcpm: USB Type-C tcpm: DP alt-mode discovery fixes (right SVID when resuming Discover Modes, Not_Supported only as a reply to an outstanding VDM, retry discovery after a VDM response timeout, don't NAK unexpected responses)

- Workspace branch: `opi5/tcpm-svid-retry-7.3` (exported 2026-10-31)
- Kernel fork branch: `opi5/tcpm` (see PUBLISH.md)
- Sits on: `integration` (base commit `1afa8d268718`)
- Hardware test: yes: 100/100 dock attach cycles reach DP configured on kernel 5, 0 VDM timeouts; injected late-response stock-vs-fixed comparison in progress; in patches/linux (0271-0274)
- Next upstream step: send to linux-usb
- Patches: 7 = 7 ours, 0 carried from others, 0 local-only

Apply with `git am` in the order listed in [`series`](series), on top of the parent topic (or check out the fork branch). Patch numbers are the position in that order.

## (a) Ours, intended for upstream (`ours/`)

| # | Subject | Author | Link |
|---|---|---|---|
| 0001 | phy: rockchip: usbdp: Re-enable DP lanes after a re-init with DP powered on | Arun Iyengar |  |
| 0002 | drm/bridge: synopsys: dw-dp: Treat OOB HPD events with HPD high as IRQ_HPD | Arun Iyengar |  |
| 0003 | usb: typec: altmodes/displayport: Notify HPD after reconfiguring with HPD high | Arun Iyengar |  |
| 0004 | usb: typec: tcpm: Use the right SVID when resuming Discover Modes | Arun Iyengar |  |
| 0005 | usb: typec: tcpm: Take Not_Supported as a VDM reply only once the VDM is sent | Arun Iyengar |  |
| 0006 | usb: typec: tcpm: Retry discovery after a VDM response timeout | Arun Iyengar |  |
| 0007 | usb: typec: tcpm: Don't answer unexpected VDM responses with Not_Supported | Arun Iyengar |  |

## Notes, results and test tools

- [notes/RESULTS.md](notes/RESULTS.md)
- [notes/tools/discovery-cycle.sh](notes/tools/discovery-cycle.sh)
- [notes/tools/install-tcpm.sh](notes/tools/install-tcpm.sh)
