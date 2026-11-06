# dw-dp-pcon: dw-dp: DP branch device / protocol converter (PCON) support as in i915 (HDMI/DVI output, downstream port limits, re-detect on downstream port changes) + CEC-Tunneling-over-AUX

- Workspace branch: `opi5/dw-dp-pcon-7.3` (exported 2026-11-06)
- Kernel fork branch: `opi5/dw-dp-pcon` (see PUBLISH.md)
- Sits on: `dp-altmode` (base commit `ed5f4cb40a40`)
- Hardware test: partly: 1204-1206 verified through a USB-C dock PCON (1080p/1440p/4K30 bars by camera, sink CRCs unchanged); dock replug, audio by ear and the Zerlon 4K30 batch pending; 1210 (CEC) builds W=1 clean, board check pending (needs a CEC-tunnelling adapter); in patches/linux (1204-1206, 1210)
- Next upstream step: send 1204-1206 to dri-devel after the dw-dp series lands; 1210 after a board test with a CEC-capable adapter
- Patches: 4 = 4 ours, 0 carried from others, 0 local-only

Apply with `git am` in the order listed in [`series`](series), on top of the parent topic (or check out the fork branch). Patch numbers are the position in that order.

## (a) Ours, intended for upstream (`ours/`)

| # | Subject | Author | Link |
|---|---|---|---|
| 0001 | drm/bridge: synopsys: dw-dp: Configure DP protocol converters | Arun Iyengar |  |
| 0002 | drm/bridge: synopsys: dw-dp: Respect the limits of a branch's downstream port | Arun Iyengar |  |
| 0003 | drm/bridge: synopsys: dw-dp: Re-detect when a branch's downstream port changes | Arun Iyengar |  |
| 0004 | drm/bridge: synopsys: dw-dp: Add CEC-Tunneling-over-AUX support | Arun Iyengar |  |

## Notes, results and test tools

- [notes/RESULTS.md](notes/RESULTS.md)
- [notes/tools/build-mod.sh](notes/tools/build-mod.sh)
- [notes/tools/crc.sh](notes/tools/crc.sh)
- [notes/tools/edid-add-rb.py](notes/tools/edid-add-rb.py)
- [notes/tools/modeset.sh](notes/tools/modeset.sh)
- [notes/tools/zerlon-batch.sh](notes/tools/zerlon-batch.sh)
- [notes/tools/zerlon-scramble.sh](notes/tools/zerlon-scramble.sh)
