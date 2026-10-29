# Orange Pi 5 board hygiene (7.3.0-opi5): results

Branch `opi5/board-hygiene-7.3` in `~/orangepi5/work/board-hygiene-7.3`. It's based on 5e33b74b0, the SATA DTS commit.

```
36f38f3be arm64: dts: rockchip: set the RK806 reset mode on Orange Pi 5 boards
facdfbd3a arm64: dts: rockchip: add the SPI NOR flash supply on Orange Pi 5
646d82276 arm64: dts: rockchip: use rgmii-id for the Orange Pi 5/5B ethernet PHY
a7e4bd60c ASoC: rockchip: i2s-tdm: add the reset value of XFER to the regmap defaults
3a599e12d net: stmmac: dwmac-rk: only read the delays the MAC applies
```

Artifacts:
- `dt/0001..0003-*.patch`: the DT commits. They apply cleanly on `opi5/board-dt` (4bfc6a759).
- `patches/0400-*.patch`, `patches/0401-*.patch`: the driver commits. They apply on `src/linux` v7.3 for `scripts/build-kernel.sh`.
- `modules/dwmac-rk.ko`, `modules/snd-soc-rockchip-i2s-tdm.ko`: built against the 7.3.0-opi5 config and Module.symvers, debug-stripped and signed (vermagic `7.3.0-opi5 SMP preempt mod_unload modversions aarch64`). Both drivers are `=m` in the board config, so they are drop-in replacements.

Build status:
- `CHECK_DTBS=y` on rk3588s-orangepi-5, -5-sata, -5b and -5-pro: no warnings.
- Both modules build with no warnings.
- `checkpatch --strict`: clean, apart from one long line in 0401, which is a quoted kernel log message and is kept as is.

Correction to the brief: the PHY on the OPi5/5B is a **Motorcomm YT8531C**, not an RTL8211F. dmesg shows `PHY [stmmac-0:01] driver [YT8531 Gigabit Ethernet]`.

---

## 1. gmac1 `Can not read property: rx_delay` / `set rx_delay to 0x10`

**Root cause.** There are two problems:
- **Driver.** `dwmac-rk` parses `tx_delay` and `rx_delay` on every probe and logs `dev_err` for any that is missing. It does this even when the PHY mode means the MAC never uses that value: `rgmii-rxid` ignores rx_delay, and `rgmii-id`/RMII ignore both. Today's warning comes from this. This is unchanged in next-20261028.
- **Board DT.** The DT says `phy-mode = "rgmii-rxid"` with `tx_delay = <0x42>`, copied from the vendor kernel. Under `ethernet-controller.yaml`, `rgmii-rxid` means "the PCB provides the TX delay". That isn't true here: the MAC delay line inserts it.

The correct description is `rgmii-id`: the PCB adds no delay and the PHY adds both. That is the binding's recommended default. The same vendor's Orange Pi CM5 already uses it in mainline (`rk3588s-orangepi-cm5-base.dts`: YT8531C on gmac1 of the same SoC, no MAC delays).

**Fix.**
- `3a599e12d` (driver, module `dwmac-rk.ko`): parse only the delays the MAC applies (TX for rgmii/rgmii-rxid, RX for rgmii/rgmii-txid). Behaviour for every mode is unchanged.
- `646d82276` (board dtsi `rk3588s-orangepi-5-5b.dtsi`, so OPi5 NVMe, OPi5 SATA and 5B): `phy-mode = "rgmii-id"`, and `tx_delay` removed.

**Effect.** TX timing moves from the MAC delay line (0x42) to the YT8531C internal delay (1950 ps, the motorcomm.c default). RX stays at the PHY's 1950 ps. With the driver patch, no delay messages are printed at all.

**Risk and fallback.** The rgmii-id DT change alters TX timing, so it **must be tested on the board** before it is kept.
- If the link or throughput degrades, drop 0001 (DT) and keep 0400. With 0400 alone, the current `rgmii-rxid` DT no longer warns either.
- If TX needs fine tuning, add `tx-internal-delay-ps` on the PHY node. Don't go back to MAC delays.

**Verification (board slot).**
1. Install dwmac-rk.ko and the new DTB.
2. `dmesg | grep -E "delay|rgmii"` should show `init for RGMII_ID` and no `Can not read property`.
3. `ethtool end0` should show 1000/Full.
4. `iperf3 -c <host> -t 30` and `iperf3 -R -c <host> -t 30` should both reach ≥ 900 Mb/s.
5. `ethtool -S end0 | grep -iE "crc|err"` must not increase.
6. `ping -f -c 100000` should have 0 % loss.

## 2. Missing `*-supply`

| Message | Result | Layer |
|---|---|---|
| `spi-nor spi5.0: supply vcc not found` | **Fixed** (`facdfbd3a`): `vcc-supply = <&vcc_1v8_s3>` on the OPi5 `&sfc` flash@0. See the evidence below. Only the OPi5 enables `sfc`; on 5B/5 Pro the FSPI M0 pins belong to the eMMC. | board dts |
| `rk_gmac-dwmac ...: supply phy not found` | **Not changed.** The vendor DT has no PHY regulator for gmac1, and the schematic isn't available (both PDFs in `_downloads/dp-altmode/schematic/` are Google Drive "quota exceeded" HTML pages). The PHY is almost certainly on the always-on `vcc_3v3_s3`, but I didn't add a rail I can't confirm. | board dtsi, once the schematic confirms |
| `ahci-dwc fe210000.sata: supply ahci / phy not found` (×7, once per deferred probe) | **No board regulator exists to describe.** `ahci-supply` and `phy-supply` are for board-switched controller or PHY rails. On the RK3588 the AHCI controller is on the SoC logic rail. The SATA PHY is combphy0, a separate node with two analog rails (0.85 V and 1.8 V) that `ahci phy-supply` can't describe. No mainline RK35xx board sets them. The rail that is switched, the M.2 3.3 V, is already described as `target-supply` (SATA DTS). The messages are the regulator core's standard warning for an absent optional supply, because libahci_platform uses `devm_regulator_get()`. That is unchanged in next. | none |

**Flash supply evidence.**
- The flash reports JEDEC ID `20 41 18` (sysfs `jedec_id`). That is an XMC XM25QU128C, a 1.65–2.0 V part.
- FSPI M0 (GPIO2_A0, GPIO2_D0–D6) is in the 1.8 V eMMC I/O domain. That domain is fed from VCC_1V8_S3 (RK806 BUCK10) in Rockchip's RK3588 reference design.
- `vcc_1v8_s3` is always-on, so nothing changes functionally.
- To confirm against the schematic when it can be downloaded: check the flash VCC net and the PHY 3V3 net.

**Verification.** After the DTB install:
- `dmesg | grep "supply vcc"` should print nothing.
- `regulator_summary` should list `spi5.0-vcc` under `vcc_1v8_s3`.
- `flashrom`/`mtd_debug read` of `/dev/mtd0` should still work.

## 3. `rockchip-pm-domain ... Failed to create device link (0x180) with supplier 2-0042 / spi2.0`

**Root cause.**
- `0x180` is `DL_FLAG_SYNC_STATE_ONLY | DL_FLAG_INFERRED`, a fw_devlink *proxy* link. The consumer fwnodes are the child nodes `power-domain@8` (NPU, `domain-supply = <&vdd_npu_s0>`, i2c2 0x42) and `power-domain@12` (GPU, `domain-supply = <&vdd_gpu_s0>`, RK806 on spi2). These children never get a struct device.
- So when the regulator device is added, and again when it binds (`__fw_devlink_link_to_consumers()` from `device_add()` and `device_links_driver_bound()`), fw_devlink proxies the link to the nearest ancestor device, the power-controller.
- `device_link_add()` refuses SYNC_STATE_ONLY links to a consumer that has already probed (drivers/base/core.c, "SYNC_STATE_ONLY links are useless once a consumer device has probed"). The power-controller has to probe long before its regulators, because the regulators' bus controllers sit in its domains.
- The result is the `dev_err`. That is why 2-0042 appears twice (at 2.69 s on add, at 3.24 s on bind) and spi2.0 once.

**Why it's harmless.**
- The link would only have deferred the regulator's `sync_state()`. fan53555 and rk806 have none.
- The driver gets the supply itself, lazily, on the first power-on (`devm_of_regulator_get(pmu->dev, pd->node, "domain")` in `rockchip_pd_regulator_enable()`). That creates a working stateless link.
- `regulator_summary` confirms both supplies are held: `fd8d8000...power-controller-domain` appears under `vdd_npu_s0` and `vdd_gpu_s0`.

**Upstream.**
- torvalds/master and next-20261028 have the same code.
- Collabora's `sre/pm-domain-cleanup` (Sebastian Reichel, 2026-09-25) has three prep commits: e2e1a975, 1b2408a2, 47b36fc5. They restructure the domain-adding code "for handling the power-domains via auxiliary sub-devices (required for proper dependency handling of domain specific regulator resources)", noting the regulators "cannot be acquired at probe time due to a dependency cycle".
- The per-domain aux devices themselves aren't written or posted yet. Once they exist, each domain node gets its own device, the fw_devlink links become real and the message goes away.

**Fix.** None locally. The proper fix is that driver rework, and adding a local copy would diverge from it. There is no smaller correct fix:
- `fw_devlink_purge_absent_suppliers()` purges a node's *consumer* links, not its supplier links.
- Silencing core.c would be a workaround.

**Verification.** Nothing to test.

## 4. `rockchip-i2s-tdm fddf0000.i2s: using zero-initialized flat cache`

**Root cause.**
- `I2S_XFER` (0x1c) is writeable and not volatile, so it is cached. It is the only cached register with no entry in `rockchip_i2s_tdm_reg_defaults[]`.
- `regcache_flat_read()` warns on its first cached access. That access is the `regmap_update_bits(I2S_XFER)` in trigger/stop, or `regcache_sync()` after runtime suspend (HDMI i2s5 at 6.7 s).
- There's no upstream fix in next-20261028 or in the vendor BSP, which has the same defaults table.

**Fix.** `a7e4bd60c` (driver, module `snd-soc-rockchip-i2s-tdm.ko`): add `{0x1c, 0x00000000}`, the reset value (TX and RX stopped). This is the same value the zero cache assumed, so no hardware write changes.

**Verification.**
1. Install the module and reload it (or reboot).
2. `dmesg | grep "flat cache"` should print nothing.
3. `speaker-test -D hw:<hdmi>,0 -c2 -t sine -l1` plays on HDMI. Analog output via es8388/i2s1 should play too.

## 5. Thermal: package/center/npu zones without cooling devices, no fan

**Facts.**
- The **OPi5 has no fan header.** The vendor `rk3588s-orangepi-5.dts` does define a `pwm-fan` on `pwm12` with `pwm12m1_pins`. That pin is GPIO4_B5, which is the active-low enable of `vcc_3v3_sd_s0` (SD card power) in both the vendor and the mainline DT.
- On the board, debugfs shows `gpio4-13 regulator-vcc-3v3-sd`, pin "MUX UNCLAIMED", and SD boot works.
- So the vendor node is a copy-paste from the 5 Plus/5 Pro, which do have fan headers. Enabling it would make the PWM drive the SD power switch. The vendor 5B DTS has no fan.
- The mainline 5 Pro DT already has its fan (pwm2) with package-zone trips.

**Mainline convention.**
- `package-thermal`, `center-thermal` and `npu-thermal` in rk3588-base.dtsi only have a 115 °C critical trip.
- Boards add active trips and maps on `package_thermal` only when they have a fan (rock-5a/5b/5c, armsom-w3, odroid-m2, nanopc-t6, cm3588-nas, 5 Pro).
- No mainline board adds passive maps to center or npu. Passive CPU and GPU cooling is already mapped on the per-cluster and GPU zones (4 cooling devices on this board).

**NPU.** The rocket driver (drivers/accel/rocket) has no devfreq and no OPP table in torvalds/master or next, so there's no NPU cooling device to map. That has to wait for rocket DVFS support upstream.

**Fix.** None. The current DT matches the hardware and mainline conventions.

## 6. DDR frequency scaling (RK3588 DMC devfreq)

**State.**
- Mainline and next have only the DFI event counter (`rockchip,rk3588-dfi` in drivers/devfreq/event/rockchip-dfi.c, node in rk3588-base.dtsi), used for DDR bandwidth perf events.
- There is no `rockchip,rk3588-dmc` driver or binding in torvalds/master, next-20261028 or rockchip/for-next. `rk3399_dmc.c` is RK3399-only.
- On the RK3588 the DDR frequency change runs in firmware. The vendor `rockchip_dmc` driver calls `ROCKCHIP_SIP_DRAM_FREQ` / `SIP_DRAM_CONFIG` SMCs implemented by the closed rkbin BL31.
- Our mainline TF-A v2.15 (`src/tf-a` da738d5) has no RK3588 DRAM code: `plat/rockchip/rk3588` has only pmu/scmi/secure/soc, and DRAM DFS exists only for rk3399.
- I found no posted upstream series in the trees available. A lore search wasn't possible because lore returns HTTP 403 (bot protection) to the tools here.

**Fix.** Not implementable. It needs DDR DVFS in TF-A first: the rkbin BL31 or a new open implementation, which would require the DDR PHY training data and timing code that Rockchip hasn't published. A kernel driver would come after that. DDR stays at the boot-time frequency (no regression).

## 7. `sync_state() pending due to fdb90000.video-codec / fdbb0000.deinterlace`

**Expected; no fix needed.**
- `fw_devlink.sync_state` defaults to strict. At the end of the deferred-probe timeout, `fw_devlink_dev_sync_state()` prints `dev_info` "sync_state() pending" for each consumer that has no driver bound yet: here the encoder and IEP, whose modules load later or not at all.
- Once their drivers bind, the link goes active and genpd's `sync_state` runs.
- Even when it never runs, nothing is held: the rockchip domains are registered with `GENPD_FLAG_NO_STAY_ON`, so genpd doesn't keep unused domains on waiting for `sync_state`.

## 8. RK806 `rockchip,reset-mode` and TSADC tshut (coordinator follow-up)

**Binding.** `mfd/rockchip,rk806.yaml` defines `rockchip,reset-mode` (0/1/2, macros in `arch/arm64/boot/dts/rockchip/rk8xx.h`). The value is written to `SYS_CFG3[7:6]` (RST_FUN) at probe, and sets the PMIC's response to a reset request on RESETB or on a PWRCTRL pin configured as reset:
- 0 = RK806_RESTART: power-cycles the PMIC and all its rails, so the whole board, including SoC PMU1/GRF/IOC/SGRF, returns to its power-on state.
- 1 = RK806_RESET: resets the "power off reset" registers and goes to ACTIVE. The rails stay up and the SoC isn't reset.
- 2 = RK806_RESET_NOTIFY: as 1, and pulls RESETB low for 5 ms.

**Current state.**
- `SYS_CFG3` reads **0x02** on the running board (regmap debugfs), so RST_FUN is already 0 (RESTART).
- The vendor BSP programs 1 (`pmic-reset-func = <1>`). That comes from the generic Rockchip `rk3588-rk806-single.dtsi`, not a board-specific choice.
- In mainline DTs: jaguar and tiger use RESTART, orangepi-cm5 uses RESET.
- Mainline U-Boot's rk8xx driver reads the same property and programs **2** when it's absent.

**Fix.** `36f38f3be` (SoC-board dtsi `rk3588s-orangepi-5.dtsi`, so 5/5-SATA/5B/5 Pro): `rockchip,reset-mode = <RK806_RESTART>`. This makes the current behaviour explicit and independent of the firmware. It's the only mode that recovers a hung SoC.

**Important.** The coordinator's premise that the PMIC isn't reset on reboot *because* the property is missing doesn't hold:
- Nothing on these boards requests a PMIC reset. PSCI SYSTEM_RESET and the watchdog use the CRU global reset (first global reset, which keeps PMU1 state).
- The RK806 PWRCTRL1-3 pins are `pin_fun0` (no function).
- The TSADC uses CRU tshut mode.
- So the property doesn't change reboot or watchdog behaviour. Making the watchdog power-cycle the board would need a SoC-to-PMIC reset path in hardware.

**TSADC.**
- rk3588-base sets `hw-tshut-mode = <0>` (CRU) and `hw-tshut-polarity = <0>`. OPi5 doesn't override them, and neither does the vendor OPi5 DT.
- GPIO0_A1 is muxed as `tsadc-shut-org` (debugfs).
- GPIO mode (1), as on rock-5c, is only correct if TSADC_SHUT is wired to the RK806 RESETB/PWRCTRL on the PCB. That can't be confirmed without the schematic, so it isn't changed. If the schematic shows that wiring, set `rockchip,hw-tshut-mode = <1>` with polarity 0 (active low, matching RK806 RESETB) on `&tsadc` in `rk3588s-orangepi-5.dtsi`, and use reset-mode RESTART as now.

**Verification (board slot).**
1. After the DTB install: `sudo cat /sys/kernel/debug/regmap/spi2.0/registers | grep ^72:` should still read `02` (bits 7:6 = 0).
2. Reboot and power-off still work (`reboot`, `poweroff`).

---

## Deployability

| Item | Type | How |
|---|---|---|
| dwmac-rk (0400) | module | drop-in `modules/dwmac-rk.ko` → `/lib/modules/7.3.0-opi5/updates/`, `depmod`. Also in `patches/` for the next full build. |
| i2s-tdm (0401) | module | drop-in `modules/snd-soc-rockchip-i2s-tdm.ko`, same procedure |
| DT 0001–0003 | DTB | merge `dt/*.patch` into `opi5/board-dt` and rebuild the combined DTB |

No built-in code changes. pm-domains is built in, but needs no change here.

**Needs a board slot:**
- Ethernet with rgmii-id (item 1): the main risk. Test it before keeping DT patch 0001.
- Confirming the absence of the flat-cache, rx_delay and spi-nor vcc messages.
- Reading SYS_CFG3 after the DTB install.

**Needs the schematic:** gmac `phy-supply` rail, the flash rail cross-check, and TSADC_SHUT wiring.
