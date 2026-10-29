# Orange Pi 5 MIPI DSI LCD: results

Branch `opi5/dsi-7.3` in `~/orangepi5/work/dsi-7.3` (based on `opi5/multicore-7.3` + SATA DTS commit).

```
d70f3be42 arm64: dts: rockchip: Add Orange Pi 5 MIPI LCD overlays
5771b0283 drm/rockchip: dsi2: Add missing sentinel to the RK3588 chip data
fb2833fab drm/panel: ilitek-ili9881c: Add Innolux AFJ101-BA2131 support
f2096b6f1 dt-bindings: display: panel: ilitek,ili9881c: Add Innolux AFJ101-BA2131
```

Status: compiled and DT-checked only. No panel was attached, so nothing has run on hardware yet.

## 1. Connector mapping

The Orange Pi 5 (RK3588S, non-Plus) has **two** 4-lane MIPI DSI LCD connectors. The user manual v0.7, §3.31, calls them
"lcd1" and "lcd2"; the feature table lists "2*MIPI D-PHY TX 4Lane".

| | LCD1 | LCD2 |
|---|---|---|
| DSI host | dsi0 `dsi@fde20000` (rockchip,rk3588-mipi-dsi2) | dsi1 `dsi@fde30000` |
| PHY | mipidcphy0 `phy@feda0000` (rockchip,rk3588-mipi-dcphy), D-PHY mode | mipidcphy1 `phy@fedb0000` |
| Lanes | 4 | 4 |
| VOP2 port (our choice) | VP3 → MIPI0 (same routing as mainline gameforce-ace / tiger-haikou) | VP2 → MIPI1 |
| LCD power enable (vendor "enable-gpios") | GPIO1_A0, active high | GPIO1_A1, active high |
| Panel reset | GPIO1_B1, active low | GPIO1_B3, active low |
| Backlight PWM | PWM2_M0 (GPIO0_C4) | PWM6_M0 (GPIO0_C7) |
| Touch I2C | I2C7_M0 (GPIO1_D0/D1). Disabled in the base DT. | I2C2_M0, shared with the vdd_npu_s0 RK8602 at 0x42 |
| Touch INT / RESET | GPIO1_B5 / GPIO1_B4 | GPIO1_A7 / GPIO1_A4 |
| Touch IC | Goodix GT9271 at 0x14 | Goodix GT9271 at 0x14 |

None of these pins is used by the mainline `rk3588s-orangepi-5{,-5b}.dtsi` / `-sata.dts`. I checked for conflicts.

Sources:
- Orange Pi BSP, `orangepi-xunlong/linux-orangepi`, branch `orange-pi-6.1-rk35xx`: the files
  `arch/arm64/boot/dts/rockchip/rk3588s-orangepi-5.dts`, `rk3588s-orangepi-5.dtsi` (pwm2/pwm6 backlights, lcd reset
  pinctrl), `rk3588s-orangepi-5-lcd.dtsi` (reset/enable GPIOs, touch buses, dcphy) and `rk3588s-orangepi.dtsi` (panel nodes),
  plus the overlays `overlay/rk3588-lcd1.dts` (dsi0 + dsi0_in_vp2) and `overlay/rk3588-lcd2.dts` (dsi1 + dsi1_in_vp3). The
  `orange-pi-5.10-rk35xx` branch has the same wiring. Copies are in `~/orangepi5/work/_downloads/dsi/`.
- Orange Pi 5 user manual v0.7 (`_downloads/dsi/manual/opi5-manual.pdf`), §1.3 and §3.31.
- Schematic: not available. The files in `_downloads/dp-altmode/schematic/` are Google Drive "quota exceeded" HTML pages,
  not PDFs. Without it I can't confirm the connector's power rails (VCC5V0/3V3/1V8 pins) or what GPIO1_A0/A1 switch.
  The vendor driver raises them before reset, so I modelled each as a GPIO-gated fixed regulator, which is the panel's
  `power-supply`. The rail voltage is left unspecified. If GPIO1_A0/A1 turn out to be the backlight enable, this model
  still turns them on before the backlight.

VOP2 port choice: on RK3588 the MIPI0 mux takes VP2 or VP3, and MIPI1 takes VP1, VP2 or VP3. The vendor uses
dsi0←VP2 and dsi1←VP3. I swapped that so LCD1 uses the VP3→MIPI0 path that mainline boards already use. This leaves
VP0 (HDMI0) and VP1 free, for example for DP0 alt-mode. If the coordinator's merged DT puts DP0 on VP2, LCD2 cannot run
at the same time as DP: move one of them to VP1 (MIPI1 accepts VP1).

## 2. Panels

- The official panel is the **Orange Pi 10.1" MIPI LCD**: 800x1280 portrait, 4 lanes, GT9271 touch. The vendor DT
  compatible is `innolux,afj101-ba2131`, driven by the BSP driver `drivers/gpu/drm/panel/panel-innolux-afj101-ba2131.c`.
  Its init sequence uses the ILI9881C page-select command (`FF 98 81 0x`), so the controller is an **Ilitek ILI9881C**.
  Retail listings also say ILI9881C.
- Mainline had no entry for this panel. I compared its init table against all 11 tables in `panel-ilitek-ili9881c.c` and
  none matches; the closest is feixin,k101-im2byl02, with 103 of 191 commands the same. So I added a new entry to the
  existing ILI9881C driver:
  - compatible `"innolux,afj101-ba2131", "ilitek,ili9881c"`
  - the vendor init pages 3, 4 and 1
  - mode 800x1280: clock 62.1 MHz, h 40/5/20, v 30/5/12 (about 54 Hz, as in the vendor driver), 136x217 mm
  - flags VIDEO | VIDEO_BURST | LPM, 4 lanes
  - the vendor's trailing page-0 commands (sleep out, display on, TE on) are left out because the driver sends them itself.

  Provenance is recorded in the commit message. The binding change is in its own commit.
- Other panels for this connector: none are documented for the OPi5. Any 4-lane DSI panel with a mainline driver can be
  added by copying one of the overlays and changing only the `panel@0` node. Panels already in mainline include ILI9881C
  variants, `panel-simple-dsi` and `boe,tv101wum`.

## 3. Device tree

New overlays: `arch/arm64/boot/dts/rockchip/rk3588s-orangepi-5-lcd1.dtso` and `rk3588s-orangepi-5-lcd2.dtso`.

Each overlay:
- enables its dsiN and mipidcphyN
- adds the VP endpoint and the panel@0 node, with backlight, power-supply and reset-gpios
- adds a pwm-backlight node and enables pwm2 or pwm6
- adds the GT9271 touch node, with inverted-x, swapped-x-y and size 1280x800 as in the vendor DT
- adds the pinctrl for the GPIOs it uses.

The two overlays can be applied together. The board DTS is unchanged, so boards without a panel are unaffected.

The Makefile also gains overlay application tests:
- `rk3588s-orangepi-5-lcd1.dtb` and `rk3588s-orangepi-5-lcd2.dtb` (NVMe base)
- `rk3588s-orangepi-5-sata-lcd1-lcd2.dtb` (SATA base with both overlays).

Through `base-dtb-y`, these make kbuild build **`rk3588s-orangepi-5.dtb` and `rk3588s-orangepi-5-sata.dtb` with `-@`**.
I checked that both now contain `__symbols__`.

`build-kernel.sh` needs no change: `bindeb-pkg` builds all `dtb-y` targets, so the two base DTBs get symbols, and
`dtbs_install` puts the `.dtbo` files into `/usr/lib/linux-image-<ver>/rockchip/`. The board's current DTB has no
`__symbols__`; `/sys/firmware/devicetree/base/__symbols__` is absent. Overlays only work after a kernel package or DTB
built from this branch, or from the coordinator's merged DT, is installed.

Note for the coordinator: if the merged board DTB is built outside this Makefile, it must be built with `DTC_FLAGS=-@`.
The overlays reference these labels:
- dsi0/dsi1, dsi0_in/out, dsi1_in/out
- mipidcphy0/1
- vp2, vp3
- i2c2, i2c7
- pwm2, pwm6
- gpio1, pinctrl.

DT patch: `_out/dsi/dt/0001-arm64-dts-rockchip-Add-Orange-Pi-5-MIPI-LCD-overlays.patch`. Built blobs are in
`_out/dsi/dt/`: `rk3588s-orangepi-5{,-sata}.dtb` with symbols, and `rk3588s-orangepi-5-lcd{1,2}.dtbo`.

## 4. Kernel side review (v7.3)

- VOP2: `rk3588_set_intf_mux()` handles ROCKCHIP_VOP2_EP_MIPI0 and MIPI1 (MIPI0 mux: VP2=0, VP3=1; MIPI1 also VP1=3),
  and `rk3588_calc_cru_cfg()` has the MIPI clock path. No bugs found. MIPI pin polarity isn't programmed on RK3588; DSI
  video mode carries sync in packets, so that's fine.
- dw-mipi-dsi2 Rockchip glue: **bug fixed**. `rk3588_chip_data[]` had no `{ }` sentinel, but probe walks the array until
  `.reg == 0`, so a node whose address matches neither DSI host reads past the end of the array. dsi0 and dsi1 match before
  the end, so this is not a functional fix for this board. Patch: `_out/dsi/patches/0003-...`. The Fixes: hash is left
  out because the shallow clone can't resolve it.
  - `CONFIG_ROCKCHIP_DW_MIPI_DSI2=y` is built into **rockchipdrm.ko** (`CONFIG_DRM_ROCKCHIP=m`), so this needs only a
    module rebuild, not a full kernel build. A signed `rockchipdrm.ko` is in `_out/dsi/modules/`; it isn't needed to light
    the panel.
- Samsung DCPHY (`phy-rockchip-samsung-dcphy.c`): D-PHY mode is implemented; C-PHY returns -EOPNOTSUPP. The glue never
  calls `phy_init()`, but `phy_power_on()` runtime-resumes the provider through the PHY core, so this works. It is the same
  path used by the mainline gameforce-ace and tiger-haikou DSI boards.
- Lane rate: 62.1 MHz × 24 / 4 × 10/9 ≈ 414 Mbit/s per lane, well inside the 4.5 Gbit/s limit.
- Behaviour to know: once dsiN is enabled, the rockchip DRM master waits for the DSI component, which registers when the
  panel driver attaches. HDMI also comes up only after `panel-ilitek-ili9881c` loads. That usually happens from the rootfs
  shortly after boot. To avoid the delay, add `panel-ilitek-ili9881c` and `phy-rockchip-samsung-dcphy` to
  `/etc/initramfs-tools/modules`.
- Required modules are all `=m` in the board config and load from OF aliases:
  - phy-rockchip-samsung-dcphy
  - panel-ilitek-ili9881c
  - pwm_bl
  - pwm-rockchip
  - goodix_ts
  - i2c-rk3x
  - reg-fixed-voltage

## 5. Enabling a panel on the board (U-Boot extlinux)

Board facts:
- U-Boot 2026.10 has `CONFIG_OF_LIBFDT_OVERLAY=y`, and `fdtoverlay_addr_r` is set in `rk3588_common.h`. Its pxe/extlinux
  code applies `fdtoverlays` after loading the DTB, including with `fdtdir`.
- Ubuntu `u-boot-menu` 4.2.4 supports `U_BOOT_FDT_OVERLAYS` and `U_BOOT_FDT_OVERLAYS_DIR`.

Steps:

1. Install a kernel package built from this branch, or from the merged board DT, so the DTBs have symbols and the
   `.dtbo` files exist in `/usr/lib/linux-image-7.3.0-opi5/rockchip/`.
2. Add these lines to `/etc/default/u-boot`:
   ```sh
   U_BOOT_FDT_OVERLAYS_DIR="/usr/lib/linux-image-"
   U_BOOT_FDT_OVERLAYS="rockchip/rk3588s-orangepi-5-lcd1.dtbo"
   # both panels: U_BOOT_FDT_OVERLAYS="rockchip/rk3588s-orangepi-5-lcd1.dtbo rockchip/rk3588s-orangepi-5-lcd2.dtbo"
   ```
   `u-boot-update` appends the kernel version to the directory, so the overlays follow the installed kernel and still
   apply to whichever DTB U-Boot picks (NVMe or SATA).
   - Leave `U_BOOT_FDT_OVERLAYS` non-empty. If it is empty, `u-boot-update` adds *every* `*.dtbo` at the top of that
     directory. There are none, so nothing happens.
   - Don't use the default `/boot/dtbo` with the version suffix: the script tests `/boot/dtbo7.3.0-opi5`, with no slash.
3. Run `sudo u-boot-update`. Check that `/boot/extlinux/extlinux.conf` now has
   `fdtoverlays /usr/lib/linux-image-7.3.0-opi5/rockchip/rk3588s-orangepi-5-lcd1.dtbo`, then reboot. If an overlay fails
   to apply, U-Boot prints "Failed loading overlay …" or "Invalid overlay …" on the serial console and boots the base DTB.

Image scripts (I did not edit them):
- `scripts/pi-apply-update.sh` installs `overlay/etc/default/u-boot` over `/etc/default/u-boot`, so the two lines must also
  go into `~/orangepi5/overlay/etc/default/u-boot`, or the next `pi-update.sh` will drop them.
- `build-kernel.sh` and `customize-rootfs.sh` need no change: the base DTBs get `-@` from the overlay-test Makefile entries.

Panel orientation: the panel is natively portrait. If the desktop should be landscape, add `rotation = <90>` (or 270) to
`panel@0`; the ILI9881C binding allows it. Alternatively, rotate in the compositor.

## Verified vs not

Verified (build host):
- `make CHECK_DTBS=y` for:
  - rk3588s-orangepi-5.dtb and rk3588s-orangepi-5-sata.dtb
  - both .dtbo files
  - all three overlay-applied test DTBs.

  No dtc or dtschema warnings. The applied DTB has dsi0/dsi1, the dcphys, the touch nodes and the VP endpoints as expected.
- `dt_binding_check DT_SCHEMA_FILES=display/panel/ilitek,ili9881c.yaml` is clean.
- `panel-ilitek-ili9881c.o` and `dw-mipi-dsi2-rockchip.o` build with W=1 and no warnings. sparse isn't installed.
- `checkpatch --strict`: only "Missing Signed-off-by" (expected) and the usual MAINTAINERS note for new .dtso files.
  spdxcheck was skipped because python `ply` is missing.
- Signed modules for 7.3.0-opi5 are in `_out/dsi/modules/`: `panel-ilitek-ili9881c.ko` and `rockchipdrm.ko`.
  vermagic is `7.3.0-opi5 SMP preempt mod_unload modversions aarch64`.

Hardware check (read-only, 13:00):
- `i2cdetect -y -r 2` (LCD2's touch bus) shows only the NPU regulator (UU at 0x42), with nothing at 0x14 or 0x5d.
  **No panel on LCD2.**
- LCD1's touch bus (i2c7) isn't enabled in the running DT, so it can't be probed read-only.
- `/sys/class/drm` has only HDMI-A-1.

So no panel was detected. Everything above is **unverified on hardware**: init sequence, timings, power-enable semantics,
touch orientation and the VP2/VP3 choice.

Not done: the board was offline (hung by another agent) for part of the session, and no install/reboot slot was
requested because there is no panel to test.

## On-board test procedure (once a 10.1" panel is connected)

Prerequisites:
1. Get a slot from the coordinator.
2. Install a kernel/DTBs from this branch, or copy `_out/dsi/dt/rk3588s-orangepi-5{,-sata}.dtb` and the `.dtbo` files
   into `/usr/lib/linux-image-7.3.0-opi5/rockchip/`, keeping the old DTBs as backups.
3. Install the signed `panel-ilitek-ili9881c.ko` into `/lib/modules/7.3.0-opi5/updates/` and run `depmod`.
4. Follow §5 to enable lcd1 (or lcd2).

Rollback: delete the `U_BOOT_FDT_OVERLAYS*` lines, run `u-boot-update`, restore the DTBs. Hang risk is low: a failed DSI
transfer only fails `prepare`.

Checks:
1. `sudo dmesg | grep -iE 'dsi|dcphy|ili9881|goodix|vop2'`. Expect no -EPROBE_DEFER loop and a "dw-mipi-dsi2" bind.
2. `ls /sys/class/drm` should show `card*-DSI-1`. `cat .../card*-DSI-1/status` gives `connected`; `modes` gives `800x1280`.
3. `modetest -M rockchip -c` shows the DSI connector. `modetest -M rockchip -s <conn>@<crtc>:800x1280` shows the test
   pattern, with no shift, flicker or wrong colours.
4. Backlight: `/sys/class/backlight/backlight-lcd1/brightness` can be set from 0 to max and the brightness changes.
5. Touch: `evtest` shows a "Goodix Capacitive TouchScreen" device. Touching the top-left of the panel in portrait should
   report coordinates near (0,0). If not, adjust `touchscreen-inverted-*`/`swapped-x-y`.
6. Run `kmscube` on the DSI connector.
7. Simultaneous HDMI + DSI: both connectors light up, on VP0 and VP3.

Pass: steps 2 to 5 all succeed. Fail: any of them fails. Capture dmesg, `/sys/kernel/debug/dri/*/state` and
`cat /sys/kernel/debug/clk/clk_summary | grep -i -E 'vp2|vp3|dsi|dcphy'`.

Common failures:
- Black screen with backlight on: check the init sequence and lane rate. Try `MIPI_DSI_MODE_VIDEO_SYNC_PULSE` instead of
  BURST, or a longer post-reset delay: the vendor waits 200 ms, mainline 20 ms.
- No backlight: GPIO1_A0 may be the backlight enable rather than LCD power.
