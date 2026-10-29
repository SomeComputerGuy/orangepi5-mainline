# hantro-multicore: Hantro multi-core: the four RK3588 VEPU121 JPEG encoder cores behind one device

- Workspace branch: `opi5/hantro-multicore` (exported 2026-10-29)
- Kernel fork branch: `opi5/hantro-multicore` (see PUBLISH.md)
- Sits on: `multicore` (base commit `d1b5768a932b`)
- Hardware test: yes: drop-in modules on the board, throughput scales across cores
- Next upstream step: send as RFC to linux-media
- Patches: 4 = 4 ours, 0 carried from others, 0 local-only

Apply with `git am` in the order listed in [`series`](series), on top of the parent topic (or check out the fork branch). Patch numbers are the position in that order.

## (a) Ours, intended for upstream (`ours/`)

| # | Subject | Author | Link |
|---|---|---|---|
| 0001 | media: verisilicon: Split probe into hardware init and device registration | Arun Iyengar |  |
| 0002 | media: verisilicon: Pick the hardware core for each job | Arun Iyengar |  |
| 0003 | media: verisilicon: Add multi-core support | Arun Iyengar |  |
| 0004 | media: verisilicon: Don't hold a VPU behind an IOMMU in reset after remove | Arun Iyengar |  |

## Notes, results and test tools

- [notes/RESULTS.md](notes/RESULTS.md)
- [notes/scripts/build.sh](notes/scripts/build.sh)
- [notes/scripts/dec.sh](notes/scripts/dec.sh)
- [notes/scripts/mkinputs.sh](notes/scripts/mkinputs.sh)
- [notes/scripts/parity.sh](notes/scripts/parity.sh)
- [notes/scripts/ppar.sh](notes/scripts/ppar.sh)
- [notes/scripts/reload.sh](notes/scripts/reload.sh)
- [notes/scripts/tput.sh](notes/scripts/tput.sh)
