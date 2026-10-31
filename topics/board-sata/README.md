# board-sata: Orange Pi 5 M.2 SATA device-tree variant

- Workspace branch: `@boardbase` (exported 2026-10-31)
- Kernel fork branch: `opi5/board-sata` (see PUBLISH.md)
- Sits on: `multicore` (base commit `d1b5768a932b`)
- Hardware test: yes: the test board runs its root file system from an M.2 SATA SSD
- Next upstream step: send to linux-rockchip (arm64 dts)
- Patches: 1 = 1 ours, 0 carried from others, 0 local-only

Apply with `git am` in the order listed in [`series`](series), on top of the parent topic (or check out the fork branch). Patch numbers are the position in that order.

## (a) Ours, intended for upstream (`ours/`)

| # | Subject | Author | Link |
|---|---|---|---|
| 0001 | arm64: dts: rockchip: add Orange Pi 5 M.2 SATA variant | Arun Iyengar |  |
