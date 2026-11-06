# board-hygiene: Board fixes: dwmac-rk delay parsing, i2s-tdm regmap default, rgmii-id, SPI NOR supply, RK806 reset mode

- Workspace branch: `opi5/board-hygiene-7.3` (exported 2026-11-06)
- Kernel fork branch: `opi5/board-hygiene` (see PUBLISH.md)
- Sits on: `board-sata` (base commit `5e33b74b04cf`)
- Hardware test: yes: all in the image kernel (patches/linux 0400-0401, 1001-1003); rgmii-id runs on the board since kernel 4 (940 Mbit/s, 0 errors); the SPI NOR supply and RK806 reset-mode DT changes boot but their effect is not measured
- Next upstream step: send the dwmac-rk fix (netdev), the i2s-tdm fix (ASoC) and the DT patches (linux-rockchip): all prepared
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
