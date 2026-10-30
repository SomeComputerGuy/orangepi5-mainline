# board-hygiene: Board fixes: dwmac-rk delay parsing, i2s-tdm regmap default, rgmii-id, SPI NOR supply, RK806 reset mode

- Workspace branch: `opi5/board-hygiene-7.3` (exported 2026-10-30)
- Kernel fork branch: `opi5/board-hygiene` (see PUBLISH.md)
- Sits on: `board-sata` (base commit `5e33b74b04cf`)
- Hardware test: partly: driver fixes in the image kernel; rgmii-id DT change still needs a board test
- Next upstream step: test rgmii-id on the board, then send driver fixes (netdev, ASoC) and DT patches separately
- Patches: 5 = 5 ours, 0 carried from others, 0 local-only

Apply with `git am` in the order listed in [`series`](series), on top of the parent topic (or check out the fork branch). Patch numbers are the position in that order.

## (a) Ours, intended for upstream (`ours/`)

| # | Subject | Author | Link |
|---|---|---|---|
| 0001 | net: stmmac: dwmac-rk: only read the delays the MAC applies | Arun Iyengar |  |
| 0002 | ASoC: rockchip: i2s-tdm: add the reset value of XFER to the regmap defaults | Arun Iyengar |  |
| 0003 | arm64: dts: rockchip: use rgmii-id for the Orange Pi 5/5B ethernet PHY | Arun Iyengar |  |
| 0004 | arm64: dts: rockchip: add the SPI NOR flash supply on Orange Pi 5 | Arun Iyengar |  |
| 0005 | arm64: dts: rockchip: set the RK806 reset mode on Orange Pi 5 boards | Arun Iyengar |  |

## Notes, results and test tools

- [notes/RESULTS.md](notes/RESULTS.md)
