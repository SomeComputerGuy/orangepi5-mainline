# hdmi-frl-fixes: Fixes for the carried HDMI 2.1 FRL series: drm/display hdmi helper no longer resets an active FRL link on every connector probe (1207); dw-hdmi-qp clears the FRL link state on TMDS fallback and disable (1213)

- Workspace branch: `opi5/hdmi-frl-fixes-7.3` (exported 2026-11-05)
- Kernel fork branch: `opi5/hdmi-frl-fixes` (see PUBLISH.md)
- Sits on: `hdmi-frl` (base commit `4c18b22e48cf`)
- Hardware test: yes: connector probes no longer force a modeset + FRL re-train; TMDS modes after FRL clean (see topics/hdmi-wedge and topics/vop2-hdmi-clk notes); in patches/linux (1207, 1213)
- Next upstream step: report on the Collabora FRL thread: 1207 for the drm/display HDMI helper maintainers, 1213 for the dw-hdmi-qp bridge (dri-devel)
- Patches: 2 = 2 ours, 0 carried from others, 0 local-only

Apply with `git am` in the order listed in [`series`](series), on top of the parent topic (or check out the fork branch). Patch numbers are the position in that order.

## (a) Ours, intended for upstream (`ours/`)

| # | Subject | Author | Link |
|---|---|---|---|
| 0001 | drm/display: hdmi: Don't reset an active FRL link on every connector probe | Arun Iyengar |  |
| 0002 | drm/bridge: dw-hdmi-qp: Clear the FRL link state when leaving FRL | Arun Iyengar |  |
