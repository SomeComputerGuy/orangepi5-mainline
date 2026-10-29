# Orange Pi 5 (SATA) reboot hang: results

Branch: `opi5/shutdown-hang-7.3`, which holds the full fix (0001-0005, fast-forwarded
to the same tip as `opi5/shutdown-hang-7.3-clk`), on top of the Orange Pi 5
M.2 SATA DTS commit 5e33b74b0. The patches are in `patches/` (0001-0005).
`dt/` (0001-0002) is the power-domain-only first step. They are wired into
`~/orangepi5/patches/linux/` as 0130-0134.

## Symptom

Every reboot with the SATA DTB (`rk3588s-orangepi-5-sata.dtb`) hangs after
`systemd-shutdown[1]: Rebooting.`. `reboot: Restarting system` never
appears, and SPL starts ~90 s later when the dw_wdt that systemd-shutdown
armed fires.

The trigger is the DTB, not the root device. The first hang
(`out/serial-boot.log`, around 10:33) still had `root=LABEL=rootfs` (SD
root), but U-Boot had already picked the SATA DTB (ata1 is up in that
boot). The earlier boots used the NVMe/PCIe DTB with the same root, and
they rebooted in <1 s.

## Root cause

`mmu600_pcie` (arm,smmu-v3 at fc900000) is enabled for every RK3588 in
`rk3588-base.dtsi`, but its node describes neither its power domain
(RK3588_PD_PCIE) nor its clock (ACLK_MMU_PCIE, child of aclk_pcie_bridge).
Normally an enabled PCIe controller holds both: PD_PCIE through its
`power-domains`, and aclk_mmu_pcie because it is the parent of
`aclk_pcie_1lN_mstr`.

The SATA DTB disables pcie2x1l2, which leaves nothing holding either of
them:

- genpd turns PD_PCIE off as unused (`pcie off-0`, no devices).
- clk_disable_unused gates aclk_mmu_pcie/aclk_pcie_bridge (enable_count 0,
  hw N).

arm-smmu-v3 (built in) probed at 0.25 s, while both were still on from
TF-A/U-Boot, and then sat idle. At reboot, device_shutdown() calls
arm_smmu_device_shutdown() → arm_smmu_device_disable(), which writes CR0
and polls CR0ACK on an unclocked/unpowered block. That stalls the
interconnect, the UART stops too, and the board waits for the watchdog.

Why the 13:08 `initcall_debug` attempt showed no "shutdown" lines: the 8250
console is nbcon in 7.3. During device_shutdown() printk only hands
messages to the printer kthread, which is stopped later in printk's
syscore shutdown. The stall killed the kthread before it could print. A
kept legacy boot console makes printk synchronous:
`earlycon=uart8250,mmio32,0xfeb50000 keep_bootcon initcall_debug
ignore_loglevel printk.devkmsg=on`.

### Serial evidence

Reboot C (16:39:48), with power-domains added but the clock still gated,
using the synchronous console (`serial-hang.log` line ~36147):

```
[   88.024735] systemd-shutdown[1]: Rebooting.
...
[   89.388918] hub 3-0:1.0: shutdown
[   89.396327] ohci-platform fc8c0000.usb: shutdown
[   89.406648] arm-smmu-v3 fc900000.iommu: shutdown
<nothing for 89 s>
U-Boot SPL 2026.10-dirty ...
```

Board state in that boot (boot B, with dt/0002):
- pm_genpd_summary: `pcie on`, `fc900000.iommu unsupported 0 SW`.
  PD_PCIE is now held.
- clk_summary: `aclk_pcie_bridge 0 0 0 ... N` and `aclk_mmu_pcie 0 0 0 ... N`.
  The clock is still gated, and that is enough to hang.

So the power domain is necessary for a correct description, but on its own
it does not fix the hang. The clock must be held as well.

## Fix

1. `dt-bindings: iommu: arm,smmu-v3: allow a power domain` (power-domains, maxItems 1).
2. `arm64: dts: rockchip: add the PCIe power domain to the RK3588 PCIe SMMU`
   (Fixes: da92d3dfc871 "enable the mmu600_pcie IOMMU on the rk3588 SoC").
3. `dt-bindings: iommu: arm,smmu-v3: allow clocks` (1-4).
4. `iommu/arm-smmu-v3: enable optional clocks`: devm_clk_bulk_get_all_enabled()
   in probe, before the first MMIO access (before impl_probe).
5. `arm64: dts: rockchip: add the clock of the RK3588 PCIe SMMU`
   (`clocks = <&cru ACLK_MMU_PCIE>`).

Patch 4 changes built-in code (CONFIG_ARM_SMMU_V3=y), so this needs a full
kernel build, not a drop-in module. 3/5 also go into the combined DTB.

I rejected the board-level workaround (`&mmu600_pcie { status = "disabled"; }`
in the SATA DTS, which is on opi5/suspend-7.3) per the user's decision. It
hides the problem for one board only, and any RK3588 board that enables no
PCIe controller hits the same hang.

### Review of patch 4 (arm-smmu-v3 users)
- ACPI/IORT: `clk_bulk_get_all()` returns 0 when there is no `dev_of_node()`.
  devm_clk_bulk_get_all_enabled() then returns 0 and does nothing.
- DT without `clocks`: of_clk_get_parent_count() returns 0, so the result is
  the same, and existing SMMUv3 systems are unaffected.
- `ret` holds the clock count afterwards. It is overwritten before its next
  use (arm_smmu_device_hw_probe()).
- Errors (including -EPROBE_DEFER from the CRU) are reported through
  dev_err_probe(). Later probe failures release the clocks through devres.
  The reset-failure path calls arm_smmu_device_disable() while the clock is
  still held.
- remove/shutdown: devres disables the clocks only after the driver
  callbacks, so the clock is on for CR0 writes in shutdown.
  `suppress_bind_attrs = true`, so there is no sysfs unbind.
- The clock stays always-on while bound. That is correct for 7.3, which has
  no runtime PM in arm-smmu-v3. Pranjal Shrivastava's runtime-PM series
  (patch.msgid.link/20260728210928.1050849-*, picked into Collabora
  rockchip-devel, not in linux-next) enables runtime PM only when
  dev->pm_domain is set, and does rpm_get around shutdown. Once that lands,
  the clocks should be disabled/enabled in its runtime suspend/resume. Until
  then, holding the clock while PD_PCIE is runtime-off would be harmless
  (the CRU gate is in an always-on domain).

### Cost
PD_PCIE and aclk_mmu_pcie (500 MHz, idle TCU) now stay on while the SMMU is
bound, on boards without PCIe. Boards with PCIe enabled are already in this
state. I estimate a few mW to ~10-20 mW of leakage and idle clock power,
not measured.

Separate issue, outside this fix: on system suspend genpd powers PD_PCIE
off, and 7.3's arm-smmu-v3 has no resume handler. This is unchanged from
PCIe boards today. The runtime-PM series above addresses it.

## Upstream status
- torvalds/master, next/master and rockchip/for-next (2026-10-28): the
  mmu600_pcie node is unchanged (no power-domains/clocks), arm-smmu-v3 has
  no clk/runtime-PM code, and the binding has neither property. No fix exists.
- Collabora rockchip-devel: carries the arm-smmu-v3 runtime-PM series but
  no DT/binding change for mmu600_pcie.
- Nothing has been sent upstream. Before sending, the binding change for
  `clocks` needs to be justified to the SMMU maintainers (Will/Robin): an
  SMMUv3 with an OS-controlled clock is new.

## Verification
- Compile: arm-smmu-v3.o builds with W=1 and no new warnings.
  CHECK_DTBS=y is clean for rk3588s-orangepi-5{,-sata} and rock-5b.
  dt_binding_check on arm,smmu-v3.yaml is clean. checkpatch --strict shows
  only the missing SoB, plus an unknown Fixes id because the clone is
  shallow.
- Board: reboot C with power-domains only still hung at
  `arm-smmu-v3 fc900000.iommu: shutdown`, as shown above.
- Board, full fix (0001-0005 = ~/orangepi5/patches/linux/0130-0134,
  kernel `#2 SMP PREEMPT_DYNAMIC Thu Oct 29 16:45:00 UTC 2026`, combined
  board-dt DTB): **PASS**.
  - 3 consecutive reboots each printed `reboot: Restarting system`, and SPL
    followed 0.59 s later (serial wall times 20026.899 → 20027.485,
    20122.305 → 20122.890, 20163.581 → 20164.166). Before the fix, SPL came
    ~89 s later, from the watchdog.
  - clk_summary: `aclk_pcie_bridge 1 1 ... Y` and
    `aclk_mmu_pcie 1 2 ... Y  iommu@fc900000`.
  - pm_genpd: `pcie on`, `fc900000.iommu unsupported`.
  - arm-smmu-v3 probes at 0.275 s, as before.
  - SATA: link up at 6.0 Gbps, UDMA/133, 0 ata error/exception/reset lines.
    `tune2fs -l /dev/sda1`: `Filesystem state: clean`.
- The first boot of the new kernel failed. It never mounted root because
  the initramfs/modules came from the previous build with the same release
  string, so `failed to validate module [...] BTF: -22` rejected
  spi_rockchip, combphy, fixed and others (CONFIG_DEBUG_INFO_BTF_MODULES=y,
  MODULE_ALLOW_BTF_MISMATCH unset). That was a packaging problem, unrelated
  to these patches, and was fixed by reinstalling the modules and
  initramfs. Recommendation: give each kernel build a distinct release
  string.

## Lessons
- **Why SD-root (non-SATA DTB) boots never hit this.** The normal Orange Pi 5
  DTB keeps pcie2x1l2 enabled for the M.2 slot. Its power-domains holds
  RK3588_PD_PCIE on, and its `aclk_pcie_1l2_mstr` clock (a child of
  aclk_mmu_pcie) holds the SMMU clock on, whether or not an NVMe device is
  present. The SMMU's missing resources were masked by its neighbour. Only a
  DTB that disables every PCIe controller in the domain (the SATA variant
  here, or any RK3588 board with no PCIe) exposes it.
- **BTF mismatch.** With CONFIG_DEBUG_INFO_BTF_MODULES=y and
  MODULE_ALLOW_BTF_MISMATCH unset, modules from another build with the same
  release string (`7.3.0-opi5`) pass the vermagic check but are rejected
  with `failed to validate module [...] BTF: -22`. Swapping only vmlinuz
  therefore leaves the board without spi_rockchip (so no PMIC or
  regulators), combphy and fixed, and SATA root never appears. Always
  install the kernel, modules and initramfs together (the deb), and
  preferably give each build a distinct release string.
- **Debugging shutdown hangs on 7.3.** The 8250 console is nbcon, and
  messages printed during device_shutdown() go through the printer thread,
  so they are lost if the bus stalls. Use
  `earlycon=uart8250,mmio32,0xfeb50000 keep_bootcon initcall_debug
  ignore_loglevel` to get synchronous output.
- The verification run used the deb-installed 16:45 kernel with the normal
  cmdline (debug params removed).
