# USB-C DisplayPort AltMode for Orange Pi 5 on 7.3.0-opi5: results

Branch `opi5/dp-altmode-7.3` (worktree `~/orangepi5/work/dp-altmode-7.3`), on top of
`5e33b74b0` (v7.3 + rga/rkvdec sync + multicore + SATA DTS). 67 commits:
65 kernel commits (`patches/0201..0265`) and 2 DT commits (`dt/0001..0002`).
**Nothing has been tested on hardware yet.**

## 1. Sources

| Part | Source | Status upstream |
|---|---|---|
| USBDP cleanup part 1 (16) and part 2 (11), v15 | lore mboxes (`_downloads/dp-altmode/usbdp-part{1,2}`), applied with `b4 am -l` | merged for 7.4 (`torvalds/master` c339f4010). The ported file is **byte-identical** to the 7.4 `phy-rockchip-usbdp.c`, Kconfig and binding |
| "usb: dwc3: introduce Rockchip glue driver" v18 (7) | lore mbox, 2026-10-21 | on list (needs the 7.4 PHY patches, which this branch has) |
| USBDP cleanup part 3 (5): Disable USB3 port during normal power-on, Drop -EPROBE_DEFER hack, Rename mode to hw_mode, Fix power state handling, Re-init PHY on mux change, Add USB-C state without DP enabled | Collabora `sre/usbdp-rework` (based on 7.3-rc7), GitLab API; `Link:` to the Collabora commit | not posted yet in this form (v14 patches 34-38 plus one newer patch) |
| "Synopsys DisplayPort Controller improvements for Rockchip platforms" v11 (21) | lore mbox, `b4 am -l` | on list; v9 got Tested-by on the Orange Pi 5 Plus (USB-C DP AltMode) |
| typec: mux: initialize orientation/mux switch array (2) | lore (Haobo Cheng) and Collabora | fixes for a 7.3 bug in duplicate detection (the new graph links the PHY to the connector twice) |
| drm/connector: Cache out-of-band hotplug events (1) | Collabora `sre/usbdp-rework` | not posted; **built-in** code (see section 4) |
| arm64: dts: rockchip: Fix DP sound-dai-cells on RK3588 | Collabora | needed by the dw-dp audio binding change (`#sound-dai-cells = <1>`) |
| Orange Pi 5/5B DT (new) | written here, modelled on Collabora's ROCK 5B DP AltMode commit (7983809d) and its VDO fix (c2d2e2b1) | ours |

The DRM side does not need the 7.4 generic "USB Type-C DP HPD bridge" (Chaoyi Chen): in 7.3 `fusb302`
already registers a DP HPD bridge on its `connector` node (Collabora reverted the removal of this for the same
reason). The chain is: VOP2 VP2 → dw-dp → USBDP aux bridge (port@0) → fusb302 HPD bridge (usb-c-connector).
TCPM's DP altmode driver sends `drm_connector_oob_hotplug_event()` on the connector fwnode, and that matches the
bridge connector's fwnode (the last bridge). dw-dp then forces HPD through the VO GRF (`oob_notify`).

## 2. What the old `.rej` was
`~/orangepi5/work/dp-altmode/drivers/phy/rockchip/phy-rockchip-usbdp.c.rej` is the Collabora commit
**"phy: rockchip: usbdp: Rename mode to hw_mode"** (v14 35/38, Collabora 9b236627). It no longer applies after
dwc3-glue v18, because v18's "Track PHY power state" reworked `rk_udphy_usb3_phy_init/exit` (`sw_mode`; exit
always clears USB). Three hunks failed: the struct field, `usb3_phy_init` and `usb3_phy_exit`. The earlier
branch also lacked the rest of part 3. Here:
- **Rename mode to hw_mode:** redone mechanically on the current code. The commit message says so.
- **Fix power state handling (713114cb):** ported onto v18. `sw_mode` already exists and the reset handler
  returns void in v18, so its error path is dropped. `usb3_phy_exit` always clears `UDPHY_MODE_USB`, as in v18.
  Commit note `[opi5: ...]`.
- **The other part-3 patches** applied unchanged.

## 3. Local change (no upstream equivalent)
`drm/bridge: Keep oob_notify at the end of drm_bridge_funcs`. Upstream puts the new callback after
`hpd_disable`, which shifts the offsets of every HDMI, DP-audio and debugfs callback. DRM core, the KMS helpers and
the panel bridge are built in (`DRM=y`, `DRM_KMS_HELPER=y`), so appending the field keeps their view of the
struct intact. This is what makes a module-only deployment possible. Drop the commit when the upstream patch
lands.

## 4. Built-in vs module (`build/linux/.config`)
- **Modules:** `TYPEC`, `TYPEC_TCPM`, `TYPEC_FUSB302`, `TYPEC_DP_ALTMODE`, `PHY_ROCKCHIP_USBDP`, `USB_DWC3`,
  new `USB_DWC3_ROCKCHIP` (olddefconfig gives `=m`; it is the only config change), `DRM_DW_DP`,
  `DRM_ROCKCHIP` (`ROCKCHIP_DW_DP=y` is inside rockchipdrm.ko), `DRM_DISPLAY_HELPER` (contains
  `drm_bridge_connector`), `DRM_AUX_BRIDGE`, `DRM_AUX_HPD_BRIDGE`.
- **Built-in:** `DRM`, `DRM_KMS_HELPER`, `DRM_BRIDGE`, `GENERIC_PHY`, `USB`.
- **Only commit 0265** (`drm/connector: Cache out-of-band hotplug events`) changes built-in code
  (`drm_connector.c`, `drm_drv.c`). It fixes a monitor that is already plugged in at boot and finishes AltMode
  negotiation before rockchipdrm binds: without it, that monitor is not detected until it is replugged. The
  other 64 commits are module-only.

Modversions: I compared the export CRCs of the rebuilt modules against `build/linux/Module.symvers`.
`drm_display_helper` and `typec` are unchanged. These changed:
- `dwc3`: `struct dwc3` changed.
- `dw-dp`: new functions and a changed `struct dw_dp`.
- `analogix_dp`, `dw-mipi-dsi`, `dw-mipi-dsi2` and `imx-ldb-helper`: their exported types embed
  `struct drm_bridge`, which reaches `drm_bridge_funcs`.

The only board modules that import a changed symbol and are not rebuilt are for other SoCs: dwc3-google, -apple,
-imx, -qcom, -generic-plat (rebuilt anyway), meson/stm dw-mipi-dsi, imx ldb. On the Orange Pi 5 every importer
is in the drop-in set. All six directories are rebuilt, so every bridge in the DP chain sees the new
`drm_bridge_funcs` layout. This matters: `drm_bridge_connector` reads `funcs->oob_notify`, and a bridge module
built with the old header has no such member.

## 5. Build and checks
- `olddefconfig` and `modules_prepare` (kernelrelease 7.3.0-opi5). W=1 build of `drivers/phy/rockchip/`,
  `drivers/usb/dwc3/`, `drivers/usb/typec/`, `drivers/gpu/drm/{bridge,display,rockchip}/`, `drm_connector.o`
  and `drm_drv.o`: **0 warnings, 0 errors.** sparse is not installed. No full `Image` was built.
- External module build (M=/MO=, chained `KBUILD_EXTRA_SYMBOLS`), script `~/orangepi5/work/_tools-dp/build-mods.sh`.
  It produced 139 modules, which are debug-stripped and signed with `sign-file sha512`. Vermagic is
  `7.3.0-opi5 SMP preempt mod_unload modversions aarch64`.
- `CHECK_DTBS=y` for rk3588s-orangepi-5-sata / -5 / -5b: clean. The first version used
  `endpoint@ROCKCHIP_VOP2_EP_DP0` and dtc wanted `endpoint@a`; fixed.
- `dt_binding_check` for `phy-rockchip-usbdp.yaml` and `rockchip,dw-dp.yaml`: clean.
- `checkpatch --strict` on all 67 commits: none of the remaining items are in our own commits. They are:
  - "Unknown commit id" for every `Fixes:` tag (an artifact of the shallow clone);
  - upstream `Reported-by:` without `Closes:` in the dw-dp patches;
  - MAINTAINERS reminders for the new dwc3-rockchip.c and rockchip-usbdp.h;
  - two `udelay(10)` CHECKs and one alignment CHECK, all in upstream code.
- Patch stack check: `v7.3 + ~/orangepi5/patches/linux/*.patch` produces exactly the tree of the branch base.
  Adding `_out/dp-altmode/patches/*` and `dt/*` on top produces exactly the tree of the branch HEAD.

## 6. Board facts (read-only, 2026-10-29 13:17, board up 7 min after the power cycle)
- `uname -r` = 7.3.0-opi5, model "Xunlong Orange Pi 5 (M.2 SATA)".
- `typec/port0`: dual-role, data role host, orientation unknown. **No partner and no altmode devices**, so
  nothing is plugged into USB-C. The only DRM connector is card0-HDMI-A-1, and it is disconnected.
- Loaded today: fusb302, tcpm, aux_hpd_bridge (from fusb302), phy_rockchip_usbdp, typec, dwc3, dw_dp,
  rockchipdrm, drm_display_helper.
- **rockchipdrm, phy-rockchip-usbdp and dwc3 are in the initramfs**, so `update-initramfs -u` is required.
- `/lib/modules/7.3.0-opi5/updates/` holds opi5-iep, opi5-jpegd and opi5-multicore. depmod is set to
  `search updates ubuntu built-in`.
- **Schematic:** the two PDFs in `_downloads/dp-altmode/schematic/` are Google-Drive "Quota exceeded" HTML
  pages (2 KB), not schematics. The wiring evidence comes from the existing mainline DT (sbu1/sbu2 DC GPIOs and
  an SBU endpoint on usbdp_phy0) and Xunlong's BSP DT (`orange-pi-6.1-rk35xx` rk3588s-orangepi-5.dtsi), which
  enables `dp0` with the USBDP PHY0 DP AltMode mux (`svid 0xff01`) on the same FUSB302 connector. The board
  also advertises DP over Type-C. The real schematic should still be checked once it can be downloaded.

## 7. DT (`_out/dp-altmode/dt/`, for `opi5/board-dt`)
1. `arm64: dts: rockchip: Fix DP sound-dai-cells on RK3588`: changes rk3588-base and rk3588-extra
   `#sound-dai-cells` from 0 to 1. Pair it with the dw-dp audio binding and driver.
2. `arm64: dts: rockchip: Add USB-C DP AltMode for Orange Pi 5/5B` (in `rk3588s-orangepi-5-5b.dtsi`):
   - `dp0` okay, routed VP2 → dp0 (`endpoint@a`, as on the ROCK 5B), with `dp0_out` → usbdp port@2.
   - usbdp_phy0 moves to the `ports` scheme: port@0 SS ↔ connector port@1, port@1 ↔ xhci0 SS, port@2 ← dp0,
     port@3 → connector SBU port@2.
   - usb_host0_xhci gets `ports`: port@0 HS ↔ connector port@0, port@1 SS ↔ PHY.
   - The connector gets `altmodes { displayport { svid = /bits/ 16 <0xff01>; vdo = <0x00001c46>; }; }`
     (DFP_D, HBR3, receptacle, pin assignments C/D/E).
   - No DP audio card yet (follow-up).

   `_out/dp-altmode/dtb/rk3588s-orangepi-5-sata.dtb` is a test DTB from this branch only. It does not include
   other `opi5/board-dt` changes.

Compatibility: the new DTB works with the old modules (DP stays without HPD, USB as before), and the new
modules work with the old DTB (no aux bridge, USB only). So the two can be rolled out separately.

## 8. Deploy plan
### Option A: module drop-in (no new kernel image; no cached-boot-HPD fix)
Use `_out/dp-altmode/modules/updates/dp-altmode/` (139 .ko; list in `modules.list`).
```sh
# host
scp -r -i ~/orangepi5/.ssh/opi5_ed25519 ~/orangepi5/work/_out/dp-altmode/modules/updates/dp-altmode <user>@<board-ip>:/tmp/
# board (sudo)
sudo cp -a /boot/initrd.img-7.3.0-opi5 /boot/initrd.img-7.3.0-opi5.pre-dp
sudo cp -r /tmp/dp-altmode /lib/modules/7.3.0-opi5/updates/
sudo depmod -a 7.3.0-opi5 && modinfo -n dwc3 phy_rockchip_usbdp rockchipdrm dw_dp dwc3_rockchip   # all must be under updates/dp-altmode
sudo update-initramfs -u -k 7.3.0-opi5
# + install the merged board DTB (keep the old one), then reboot
```
Rollback: `rm -rf /lib/modules/7.3.0-opi5/updates/dp-altmode && depmod -a && update-initramfs -u`, restore the
DTB, reboot.

Do it in two stages if possible:
- **Stage 1:** modules only, old DTB, reboot. This tests the dwc3 glue and new PHY code for USB regressions.
- **Stage 2:** new DTB, reboot.

Do **not** hot-reload dwc3, usbdp or rockchipdrm at runtime. Reloading tears down xHCI, the PHY and DRM, which
risks SErrors. A reboot is the safe way to switch.

### Option B: full kernel (recommended final form)
Copy `_out/dp-altmode/patches/0201-*.patch … 0265-*.patch` to `~/orangepi5/patches/linux/` (they apply on top of
0001 + 0101..0122). Add `CONFIG_USB_DWC3_ROCKCHIP=m` to `scripts/opi5.config` (olddefconfig also picks it by
default). Then run `scripts/build-kernel.sh` and `pi-update.sh`, install the merged DTB and reboot. This adds 0265
(boot-time OOB HPD cache). If 0265 is not wanted, leave it out; the rest is the same as option A.

## 9. Hardware test plan (needs the user)
**Needs:** a DP AltMode sink. Use either a USB-C monitor, or a USB-C→DP or USB-C→HDMI adapter that does DP
AltMode (not a DisplayLink one). A USB-C hub with HDMI plus USB3 tests pin assignment D. Also a USB3 stick for
the regression test.

1. **Stage 1, USB regression (old DTB):**
   - `dmesg | grep -iE 'usbdp|dwc3|xhci|SError'`: no errors; `lsusb -t` still shows the 5000M root hub.
   - Plug a USB3 stick into USB-C: it appears at 5000M. Repeat with the cable flipped.
   - Gadget mode is not configured (`USB_DWC3_GADGET` is not set), so skip it.
2. **Stage 2, DP:** before plugging in, set
   `echo 'module phy_rockchip_usbdp +p; module dw_dp +p; module rockchipdrm +p' > /sys/kernel/debug/dynamic_debug/control`.
   Then plug in the sink and check:
   - `ls /sys/class/typec/` shows `port0-partner`.
   - `cat /sys/bus/typec/devices/port0-partner.*/svid` gives `ff01`, and `.../active` gives `yes`.
   - dmesg shows the usbdp "new mode" and "reinit PHY ... DP=on (2|4 lanes)" lines, plus dw-dp "Force HPD
     connected=yes".
   - `cat /sys/class/drm/card*-DP-1/status` gives `connected`; `modetest -M rockchip -c` lists DP modes;
     `modetest -M rockchip -s <conn>@<crtc>:1920x1080` (or kmscube) shows an image.
3. **Repeat and edge cases:**
   - Unplug and replug 10×, then flip the cable.
   - HDMI0 and DP at the same time.
   - 4K60 over 4 lanes on an adapter (pin assignment C/E). With 2 lanes (D), 4K30 or 1440p60 at HBR2.
   - USB3 device behind a hub while DP is active (2+2 lanes).
   - Reboot with the monitor already plugged in. Option A: replugging may be needed. Option B: it should be
     detected at boot.
4. **Pass:** stable picture, no SError or hang, USB still works afterwards. **Fail:** any SError or hang,
   `cmn ana lcpll lock timeout`, AUX timeouts, or no `port0-partner` (that would mean a PD/AltMode
   negotiation problem; Collabora's `sre/dp-altmode-enter-debug` has TCPM debug patches for this).

**Risk:**
- The reboot steps (both stages) carry boot-time risk. `dwc3-rockchip` becomes **mandatory** for the
  RK3588 DWC3 nodes, because core.c refuses `rockchip,rk3588-dwc3`. If it fails to load, the USB3 ports and the
  USB-C data role are lost. EHCI/OHCI, Ethernet, SATA and HDMI are not affected.
- The main failure mode is an SError or hang during USBDP PHY or DWC3 init at boot. Since these modules load
  from the initramfs, the hang would recur on every boot. Recovery needs the serial/U-Boot console: add
  `modprobe.blacklist=dwc3_rockchip,phy_rockchip_usbdp` to the boot command line, or boot the
  `initrd.img-7.3.0-opi5.pre-dp` backup. Prepare a fallback boot entry before rebooting.
- The series exists to fix exactly these SErrors, and v9 was tested on an Orange Pi 5 Plus (same RK3588
  PHY/DWC3).
- Plugging in or unplugging the monitor at runtime is low risk once boot works.

## 10. Next steps
- After the test passes: the DP audio card (`dp0` I2S/SPDIF and simple-audio-card), and a check of 10-bit/HDR
  over DP.
- Rebase onto 7.4-rc1. USBDP parts 1/2 drop out, since they are already merged. Keep dwc3-glue v18, part 3,
  dw-dp v11 (or newer) and the connector cache patch. Drop the local `oob_notify` reorder once upstream
  settles.
- The DT patch is ours to submit upstream later. That needs the dw-dp series merged first, plus a test report.
- Get the real schematic (Google Drive quota) to confirm the SBU/AUX routing.
