# Orange Pi 5 USB3 Type-A port: USB 3 device present at boot comes up at 480M

## UPDATE 2026-10-30 07:40, kernel #5 (1501–1504 in): the mechanism is wrong, drop 1501–1504

On kernel #5 the pairing works, and 1503 fired; its retry message was at 3.539 s:
- `usb3-port1/peer -> usb6-port1`, and the reverse link exists too.
- `usb 3-1: SuperSpeed peer port available, resetting` at 3.539 s, followed by `reset high-speed USB device`.

The stick stayed at 480M. Test A on kernel #5, with the xHCI up and its SS port at `PORTSC 0x0a0002a0
Link=RxDetect PP`, the host waiting:

| action on the SanDisk 0781:5583 in the upper port | result |
|---|---|
| `usbreset` (USB 2.0 bus reset), long after the SS port is up | stays 480M |
| USB 2.0 runtime suspend + resume (usb-storage unbound, `runtime_status` suspended then active) | stays 480M |
| unbind + bind the EHCI (PHY off: the device fell to OHCI at 12M, then back) | stays 480M |
| unbind + bind dwc3 host 2 (combphy2 + xHCI re-init; 1503 reset fired again at 214.4 s) | stays 480M |
| hot-plug, i.e. a VBUS cycle (earlier today, twice) | 5000M |

This device searches for SuperSpeed only when VBUS rises. No USB 2.0 event (reset, suspend/resume, disconnect)
makes it search again, and nothing the host can do on the SS side reaches it, because its SS receiver is off.
On this board, VBUS of the Type-A ports is always on (no enable GPIO in the mainline or vendor DT, and no
schematic available). It rises at power-on, and through a reboot it never drops. Either way it happens long
before any software can power combphy2 and the xHCI (BootROM and DDR init alone take more than 100 ms).

So no kernel or DT fix can make a USB 3 device that is plugged in across power-on or reboot come up at
SuperSpeed on this port. It is a hardware limitation of the always-on VBUS. Hot-plug after boot is always SS.
All 7 boots with the stick present (kernels #4 and #5) came up HS. The "SS on some boots" was a hot-plug.

**Recommendation:** remove 1501–1504 from `patches/linux` for build 6. 1503 doesn't help this device. 1502 adds
cross-controller peering that nothing needs without 1503. 1501/1504 only exist to feed them. They are harmless on
#5 (one extra USB 2.0 reset per boot), but carrying ineffective new USB-core behaviour isn't a proper fix. A real
fix needs a switchable VBUS on the port (then `vbus-supply` on the connector, enabled after the SS host is up).
Check that against the OPi5 schematic if one turns up. Workaround for users: replug after boot.

---


Branch `opi5/usb3-port-7.3` in `~/orangepi5/work/usb3-port-7.3`: the 314-patch image stack (v7.3) plus 4 commits.
Build dir: `~/orangepi5/build/wt-usb3-port-7.3`.

## Root cause (confirmed read-only on the board, kernel #4)

- **Port wiring.** The upper blue Type-A port is USB 3. Its USB 2.0 lines go to u2phy3_host and usb_host1_ehci/ohci
  (fc880000/fc8c0000). Its SS lanes go to combphy2_psu and usb_host2_xhci (fcd00000). Host 2 is SuperSpeed-only:
  its own USB 2.0 root hub (bus 5) has no PHY behind it. The lower blue port is USB 2.0 only (u2phy2, host0
  fc800000), so the 05:52 replug at 480M on fc800000 was correct.
- **VBUS is not switchable.** No GPIO-switched host VBUS regulator exists, in mainline or in the vendor DT. The
  vendor DT has `vcc5v0_usb` always-on, fed from DC-in. So the stick is powered from board power-up, and a
  `phy-supply`/`vbus-supply` gating fix can't work on this board.
- **Mechanism.** A USB 3 device searches for an SS link when VBUS comes up, and connects at HS if it finds none. It
  searches again only after VBUS is cycled or after a USB 2.0 bus reset. At boot the EHCI enumerates and resets the
  port before the dwc3/xHCI host 2 has powered combphy2 and its root port:

  | boot | EHCI `new high-speed` | xhci-hcd.1 registers | result |
  |---|---|---|---|
  | -6 … 0 (6 boots, stick in at boot) | 6.79–7.18 s | 7–20 ms **later** | 480M on fc880000, every time |
  | -7 (03:45, hot-plug at 45 s) | — | 11.36 s | **5000M** on bus 6 |
  | 0, hot-plug back into the top port at 1441 s | — | — | **5000M** on bus 6 |

  So the failure is only the boot ordering: 6 of 6 boots failed, and every hot-plug worked. combphy2, xHCI and the SS
  link work, and nothing in 0270 (usbdp) or the board DT patches touches them. The 03:45 "SS at boot" was in fact a
  hot-plug.
- **Mainline status.** Mainline has nothing for this. rock-5a/5b put `phy-supply = <&vcc5v0_host>` on u2phy3_host,
  but that turns VBUS on at EHCI PHY power-on, which is the same race. The USB core pairs USB2/USB3 peer ports only
  inside one xHCI (`shared_hcd`), or through an ACPI `_PLD` location restricted to the same xHCI. The EHCI port
  therefore has no peer, and the SS port is paired with host 2's dead USB 2.0 port.

## Fix (patches for `patches/linux`: 1501–1504)

| # | patch | what it does |
|---|---|---|
| 1501 | `dt-bindings: usb: generic-ehci: Allow describing the root hub ports` | Adds a `ports` graph (port@N = root hub port N) to EHCI nodes, with the semantics `usb_of_get_connect_type()` already uses for hubs. |
| 1502 | `usb: core: Pair ports of different hubs through their connector` | New `usb_of_get_connector_peer()` (of.c). If a port's graph endpoint leads to a usb-{a,b,c}-connector whose other half (port@0 = HS, port@1 = SS) ends on a **different** hub or HCD node, it pairs the two ports as peers through `link_peers()`. Such ports are kept out of default pairing. When both halves end on the same node (Type-C on dwc3, host0), behaviour is unchanged. |
| 1503 | `usb: hub: Retry SuperSpeed for a device stuck on its USB 2.0 peer` | When an SS hub with connector-paired ports activates (init, post-reset, reset-resume; not plain resume), a work item locks the peer HS hub, which waits out any enumeration in progress. If a SuperSpeed-capable device (`bos->ss_cap`) is at HS there, it resets that device **once** (`usb_reset_device`). The device then trains SS and moves to the xHCI. A device whose SS really doesn't work stays at HS after that single reset, so it can't loop. |
| 1504 | `arm64: dts: rockchip: Describe the USB3 Type-A connector on Orange Pi 5/5B` | `usb-a-connector` (label "USB3", `vbus-supply = <&vcc5v0_sys>`). port@0 goes to `&usb_host1_ehci` port@1, port@1 goes to `&usb_host2_xhci` port@1 (dwc3 binding: port@1 = SS). |

Cases this covers:
- **Device present at boot.** The xHCI comes up after the EHCI, its activation resets the HS device, and the device
  moves to SS.
- **EHCI slower than the xHCI.** The EHCI's own reset happens with SS already up, so the device connects at SS.
- **Hot-plug.** Already works, and the patches don't change that path.
- **Enumeration in progress on the EHCI.** The work blocks on the EHCI root hub lock until enumeration finishes,
  then resets the device.
- **Bonus.** The EHCI and xHCI ports are now real peers (sysfs `peer` link), so the peer runtime-PM rule ("power the
  usb3 peer before the usb2 port") applies to them too.

### Build / checks
- `drivers/usb/core/` builds with W=1, no warnings, at HEAD and at 1502 alone (bisectable). sparse is not installed.
- `CHECK_DTBS=y DTC_FLAGS=-@` is clean for rk3588s-orangepi-5, -5-sata, -5b and -5-pro. `dt_binding_check
  DT_SCHEMA_FILES=usb/generic-ehci.yaml` is clean.
- `checkpatch --strict` gives only "Missing Signed-off-by" (intended) and one CHECK (no blank line between inline
  stubs in `include/linux/usb/of.h`, matching that file's existing style).
- **Not built or tested on hardware.** usbcore is built-in (`CONFIG_USB=y`), so 1502/1503 need a full kernel deb.
  Fold 1501–1504 into kernel build 5.

### Artifacts
- `patches/1501..1504-*.patch`: `git format-patch` of the 4 commits, applying on top of `patches/linux` 1408.
- `rk3588s-orangepi-5-sata-usb3port.dtb` (md5 9010d518…): the stack DTB with 1504, plus the board's
  `~/ccu/rk3588-vdec-ccu.dtbo` overlay applied (copied here as `rk3588-vdec-ccu.dtbo`). Apart from phandle
  renumbering, it differs from the board's current DTB (`board-current-sata.dtb`) only in the new connector/graph
  nodes. With kernel #4 it is harmless (the core ignores the graph except for the connect type), but it has no effect
  until 1502/1503 are in.
- `check-usb3-port.sh`: run it on the board each boot (`ssh … 'sh -s' < check-usb3-port.sh`). It prints PASS/FAIL,
  the EHCI port's `peer`, and the reset message.

## Board test plan

**A. Mechanism check (current kernel #4 and DTB, 1 reboot).** Stick in the upper port at boot. After boot,
`check-usb3-port.sh` should print FAIL (HS on fc880000). With the stress test off the stick, run
`sudo usbreset 0781:5583` and re-run the script.
- Expected: the stick disconnects from the EHCI, then `usb 6-1: new SuperSpeed`, then PASS. This is the behaviour 1503
  relies on.
- If it stays at HS, the fix needs rethinking: report back.

**B. Fix (kernel build 5 with 1501–1504, plus `rk3588s-orangepi-5-sata-usb3port.dtb` as the board DTB).**
- Reboot ≥10 times with the stick in the upper port. Each boot needs PASS, plus `EHCI port peer: …/usb6-port1`
  (bus number may vary). dmesg shows `SuperSpeed peer port available, resetting` once, when the EHCI won the race.
- After boot:
  - Hot-plug into the upper port: SS.
  - Hot-plug into the lower port: HS on fc800000.
  - Back into the upper port: SS.
- Regressions to check:
  - Type-C port (host0, usbdp): the dock still enumerates at SS.
  - A USB 2.0-only device in the upper port stays on the EHCI with no reset message (no `ss_cap`).
  - Optional: one suspend/resume with the stick in, which should stay SS or come back SS.
- Watch for noise: `onboard-usb-dev` now binds the connector node. That is expected and harmless.

## Open points / risks
- **Spec claim.** "The device retries SS after a USB 2.0 bus reset" comes from USB 3.x device behaviour (exit from
  eSS.Disabled on a USB 2.0 reset). Test A checks it on this stick.
- **Upstream reception.** Cross-HCD peering is new USB-core behaviour, and Alan Stern / Greg KH may want it shaped
  differently, e.g. as a usb-a-connector component instead of OF lookups in port.c. The DT description (connector
  graph) should hold up either way. On the dwc3 node, graph port@1 is "SS data bus" in the dwc3 binding and also the
  root hub port 1 the core looks up. For single-port host 2 these coincide, which the series relies on.
- Other RK3588 boards with the same split (rock-5a/5b/5c, orangepi-5-plus/max/ultra, nanopc-t6 …) would need the
  same connector nodes. Only OPi5/5B are done here.
