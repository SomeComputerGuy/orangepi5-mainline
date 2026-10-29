# v7.4-hdmi-frl: 7.4 base: first HDMI FRL commit

- Workspace branch: `opi5/hdmi-frl` (exported 2026-10-29)
- Kernel fork branch: `opi5/v7.4-hdmi-frl` (see PUBLISH.md)
- Sits on: `c339f4010` (base commit `c339f4010dea`)
- Hardware test: via hdmi-frl (v7.3)
- Next upstream step: rebase onto 7.4-rc1
- Patches: 1 = 0 ours, 1 carried from others, 0 local-only

Apply with `git am` in the order listed in [`series`](series), on top of the parent topic (or check out the fork branch). Patch numbers are the position in that order.

## (b) Carried from others, authorship kept (`carried/`)

| # | Subject | Author | Link |
|---|---|---|---|
| 0001 | drm/drm_scdc_helper: Add SCDC helper funcs for FRL | Ankit Nautiyal | [link](https://lore.kernel.org/r/20261012035806.3361439-5-ankit.k.nautiyal@intel.com) |
