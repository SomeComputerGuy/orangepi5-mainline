# Suspend / s2idle on Orange Pi 5 (RK3588S, 7.3.0-opi5, mainline TF-A v2.15) — analysis

Written by the coordinator from the suspend agent's final report (the agent couldn't write files). Nothing was suspended; all board inspection was read-only.

## Verdict
- Mainline TF-A v2.15 implements PSCI SYSTEM_SUSPEND for RK3588 and the board advertises it (`/sys/power/mem_sleep` = `s2idle [deep]`, PSCIv1.1). Deep sleep can be *tried* without rkbin BL31; no public report of a mainline RK3588 board resuming end to end was found.
- **s2idle is the safer first real test** (no PSCI SYSTEM_SUSPEND, no TF-A PMU code): it separates driver bugs from firmware bugs.

## Firmware (TF-A v2.15, ~/orangepi5/src/tf-a da738d5)
- `plat/rockchip/common/plat_pm.c:385-397` registers suspend ops; `lib/psci/psci_setup.c:272` advertises SYSTEM_SUSPEND.
- `plat/rockchip/rk3588/drivers/pmu/pmu.c` `rockchip_soc_sys_pwr_dm_suspend()` (l.1288): saves/ungates clock gates, powers off GPU/NPU/VCODEC/RGA/AV1/VDPU/VO/VI/AUDIO/GMAC/PCIE/PHP/SDIO/NVM/SDMMC/CRYPTO, DDR self-refresh, PLLs down, drives PMIC_SLEEP (GPIO0_A4), warm boot from PMUSRAM.
- Wake sources hard-coded: GPIO0 interrupts + CPU0 interrupt. No `rockchip,pm-config` SIP.
- OPi5 DT sets RK806 PWRCTRL1-3 to `pin_fun0`, so PMIC_SLEEP is ignored and VDD_LOG/DDR rails stay up (little power saved, but safer: TF-A doesn't save the GIC distributor).
- **TF-A bugs:**
  1. PHP CRU clock-gate save/restore index slip (`clk_gate_con_save/restore`, l.197-246, also in master): on resume `PHPCRU_CLKGATE_CON0` gets the secure-CRU gate 0 value (bits 5-8 = combphy APB clocks, incl. SATA combphy0). Patch: `tf-a/0001-fix-rk3588-save-and-restore-the-PHP-CRU-clock-gate-s.patch` (compiles; not tested/flashed; not sent upstream).
  2. `rockchip_soc_soft_reset()` writes `BUSSCRU+0x280 = 0x0003000` without write-mask bits (no-op).
  3. BL31 boot console garbled at 115200 (takes baud from U-Boot `stdout-path` 1500000); needs a U-Boot `-u-boot.dtsi` override.
- Collabora runs upstream TF-A (their `rockchip` branch = v2.15.0 + CI) and LAVA PM tests (`pm_test=core`, `rtcwake -m mem -s 120`); their open issue #43: RK3576 never resumes from RTC wake; RK3588 TBD. HYM8563 alarm has 1-minute resolution → use wake times >= 120 s.

## Kernel drivers (7.3) on this board
| Area | Status | Risk |
|---|---|---|
| SATA root (ahci_dwc + combphy0) | PM ops; SSD loses power (`vcc3v3_pcie20` target-supply); resume re-inits PHY/host | main risk (root FS loss; kernel alive) |
| GMAC | stmmac PM; Collabora has a Realtek PHY re-init fix | low |
| USB / fusb302 / tcpm | PM ops; tcpm wakeup enabled | low–medium (early wake) |
| pmdomain, VOP2/HDMI, panthor, rocket, iommus | runtime PM + force | low |
| out-of-tree media modules in updates/ | runtime PM | exclude from first runs |
| arm-smmu-v3 (fc900000) | no PM ops; PD off | not used (PCIe disabled) |
| dw_wdt | frozen while suspended | can't rescue mid-suspend hangs |
| hym8563 RTC | wakeup-source, irq_wake | 1-min resolution |

Wake sources now: hym8563 (IRQ 60, GPIO0_B0), rk805-pwrkey (no known power button), tcpm psy. UART can't wake; sysrq doesn't work while suspended.

## Reboot hang (handed to the shutdown-hang agent)
Every SATA-root reboot hangs before PSCI (arm-smmu-v3 shutdown on powered-off PD_PCIE); SD-root reboots are fine, so the TF-A reset path works. RK806 is never reset on reboot (OPi5 DT lacks `rockchip,reset-mode`; jaguar/tiger use `RK806_RESTART`), and the watchdog/TSADC first-global-reset keeps PMU1 GRF/IOC/SGRF — possibly why the 12:51 hang wasn't recovered by the watchdog (unconfirmed).
