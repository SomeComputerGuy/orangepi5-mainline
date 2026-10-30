# dw-dp-redetect: PARKED, NOT IN THE IMAGE: dw-dp re-detect after a missed HPD (patch 0275)

- Workspace branch: `opi5/dw-dp-redetect-7.3` (exported 2026-10-30)
- Kernel fork branch: `opi5/dw-dp-redetect` (see PUBLISH.md)
- Sits on: `dp-smooth` (base commit `24b75a5854fb`)
- Hardware test: not needed: the USBDP re-init (0270 v2) fixed the boot-time AUX -110 it targeted
- Next upstream step: none (parked)
- Patches: 1 = 1 ours, 0 carried from others, 0 local-only

Apply with `git am` in the order listed in [`series`](series), on top of the parent topic (or check out the fork branch). Patch numbers are the position in that order.

## (a) Ours, intended for upstream (`ours/`)

| # | Subject | Author | Link |
|---|---|---|---|
| 0001 | drm/bridge: synopsys: dw-dp: Detect the sink again on HPD IRQs when it was not found | Arun Iyengar |  |
