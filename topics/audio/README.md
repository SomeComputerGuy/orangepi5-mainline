# audio: Audio: dw-hdmi-qp N/CTS after a link rate change, DP0 audio for RK3588 / Orange Pi 5

- Workspace branch: `opi5/audio-7.3` (exported 2026-10-31)
- Kernel fork branch: `opi5/audio` (see PUBLISH.md)
- Sits on: `integration` (base commit `1afa8d268718`)
- Hardware test: partly: HDMI audible through FRL/TMDS mode changes; DP audio signal-level only; headphone jack not checked by ear
- Next upstream step: listen test on DP and the jack, then send (dri-devel, linux-rockchip)
- Patches: 2 = 2 ours, 0 carried from others, 0 local-only

Apply with `git am` in the order listed in [`series`](series), on top of the parent topic (or check out the fork branch). Patch numbers are the position in that order.

## (a) Ours, intended for upstream (`ours/`)

| # | Subject | Author | Link |
|---|---|---|---|
| 0001 | arm64: dts: rockchip: Add DP0 audio to RK3588 and Orange Pi 5/5B | Arun Iyengar |  |
| 0002 | drm/bridge: dw-hdmi-qp: Reprogram audio N/CTS after a link rate change | Arun Iyengar |  |

## Notes, results and test tools

- [notes/RESULTS.md](notes/RESULTS.md)
- [notes/TESTING.md](notes/TESTING.md)
- [notes/listen-test.sh](notes/listen-test.sh)
- [notes/modeswitch-listen.sh](notes/modeswitch-listen.sh)
- [notes/seq.sh](notes/seq.sh)
