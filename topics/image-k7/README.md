# image-k7: Earlier image kernel (tag image-7.3.0+opi5.7): image-k6 + usb3-port (1501-1504) + rkvdec-reset (1801/1802/1804); rkvdec-ccu sits on it. The current image kernel is branch opi5/image

- Workspace branch: `opi5/image-k7-7.3` (exported 2026-11-07)
- Kernel fork: tag `image-7.3.0+opi5.7` (retired branch `opi5/image-k7`; see PUBLISH.md)
- Sits on: `usb3-port` (base commit `398229c00d6f`)
- Hardware test: yes: ran on the board (rkvdec-reset proven on a KASAN kernel)
- Next upstream step: none (integration only); provenance in docs/image-kernel/MANIFEST.md
- Patches: 3 = 3 ours, 0 carried from others, 0 local-only

Apply with `git am` in the order listed in [`series`](series), on top of the parent topic (or check out the fork branch). Patch numbers are the position in that order.

## (a) Ours, intended for upstream (`ours/`)

| # | Subject | Author | Link |
|---|---|---|---|
| 0001 | media: rkvdec: Handle interrupts of a core that has no job | Arun Iyengar |  |
| 0002 | media: rkvdec: Reset a core whose job failed or timed out | Arun Iyengar |  |
| 0003 | iommu/rockchip: Don't walk a page table that a reset took away | Arun Iyengar |  |

## Notes, results and test tools

- [notes/MANIFEST.md](notes/MANIFEST.md)
- [notes/checkdtbs-extra.txt](notes/checkdtbs-extra.txt)
- [notes/checkpatch.txt](notes/checkpatch.txt)
- [notes/checks.txt](notes/checks.txt)
- [notes/dtb-diff.txt](notes/dtb-diff.txt)
- [notes/tools/export-stack.sh](notes/tools/export-stack.sh)
- [notes/w1-extra.txt](notes/w1-extra.txt)
- [notes/w1-media.txt](notes/w1-media.txt)
- [notes/w1-other.txt](notes/w1-other.txt)
