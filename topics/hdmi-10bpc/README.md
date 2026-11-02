# hdmi-10bpc: dw_hdmi_qp: pass the colour depth to the HDPTX PHY in FRL mode (fix for the carried FRL glue)

- Workspace branch: `opi5/hdmi-10bpc-topic-7.3` (exported 2026-11-02)
- Kernel fork branch: `opi5/hdmi-10bpc` (see PUBLISH.md)
- Sits on: `hdmi-frl` (base commit `4c18b22e48cf`)
- Hardware test: partly: in the image (patches/linux 1203); 4K60 10 bpc RGB over FRL shows correctly on the TCL TV with and without it, so it is a consistency fix, not a fix for an observed failure
- Next upstream step: fold into the FRL glue patch of the Collabora series (0300-098) or report it on that thread (dri-devel, linux-rockchip)
- Patches: 1 = 1 ours, 0 carried from others, 0 local-only

Apply with `git am` in the order listed in [`series`](series), on top of the parent topic (or check out the fork branch). Patch numbers are the position in that order.

## (a) Ours, intended for upstream (`ours/`)

| # | Subject | Author | Link |
|---|---|---|---|
| 0001 | drm/rockchip: dw_hdmi_qp: Pass color depth to the PHY in FRL mode | Arun Iyengar |  |

## Notes, results and test tools

- [notes/RESULTS.md](notes/RESULTS.md)
- [notes/batch1/conn.txt](notes/batch1/conn.txt)
- [notes/batch1/summary.txt](notes/batch1/summary.txt)
- [notes/edid-hdmi-blocks.txt](notes/edid-hdmi-blocks.txt)
- [notes/tools/ab.sh](notes/tools/ab.sh)
- [notes/tools/caseA.sh](notes/tools/caseA.sh)
- [notes/tools/hdmi-batch.sh](notes/tools/hdmi-batch.sh)
