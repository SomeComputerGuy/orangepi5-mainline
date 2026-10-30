# tcpm: DP Alt Mode discovery lost after a late Discover SVIDs response

Branch `opi5/tcpm-svid-retry-7.3` in `~/orangepi5/work/tcpm-7.3`. Base: `opi5/integration-7.3` + 0267-0269.
Author Arun Iyengar. Every commit has `Assisted-by: Claude:claude-opus-5-5` and no SoB.

## 1. What the failing log shows

Log: `work/_out/workaround-removal/board/tcpm-nopartner.txt`. Partner 057e:2003, PD rev3, we are Source/DFP.
For comparison, a good boot is in `board/boot-0503-tcpm.txt` (05:03 boot): the same requests get their
responses 9 ms after `PD TX complete`.

| time (s) | event | meaning |
|---|---|---|
| 5.8647 | AMS DISCOVER_SVIDS start, cc:=4 (SinkTxNG) | |
| 5.8892 / 5.8983 | PD TX 0x19af / TX complete | Discover SVIDs sent and GoodCRC'd. tcpm arms VDMResponseTimer: `PD_T_VDM_SNDR_RSP` = 30 ms |
| 5.9283 | AMS DISCOVER_SVIDS finished | **timer expired**: VDM_STATE_BUSY -> VDM_STATE_ERR_TMOUT. Nothing is logged and nothing queues discovery again |
| 5.9348 | PD RX 0x248f (VDM, 2 objects, msgid 2) | **the Discover SVIDs ACK, 36.5 ms after TX complete** (6.5 ms late). No "Rx VDM cmd" line: it is not processed as an SVDM |
| 5.9348 / 5.9477 | PD TX 0x0bb0 / complete | **tcpm sends Not_Supported** to that ACK (`tcpm_handle_vdm_request` else-branch: no matching altmode, no VDM AMS, `nr_snk_vdo == 0`) |
| 5.9478 | tcpm_vdm_discovery_work [PARTNER_IDENT], AMS DISCOVER_SVIDS start, cc:=4 | sending Not_Supported passed through SRC_READY again, which queues discovery (by accident, not as a retry). The VDM state machine holds Discover SVIDs for tSinkTx (16 ms, VDM_STATE_SEND_MESSAGE) |
| 5.9559 | PD RX 0x0690 (Not_Supported, msgid 3) | the dock answers our Not_Supported with a Not_Supported of its own, 8 ms later |
| 5.9559 | AMS DISCOVER_SVIDS finished | `tcpm_pd_ctrl_request()` SRC_READY: `vdm_state > VDM_STATE_READY`, so it takes the Not_Supported as the **reply to the Discover SVIDs it has not sent yet**: VDM_STATE_DONE. Discovery stays in PARTNER_IDENT for good. No altmode, DP-1 disconnected, USB3 unaffected |

Decoded headers: 0x19af = VDM, 1 object, msgid 4, Source/DFP rev3; 0x248f = VDM, 2 objects
(header + SVID word 0xff01/0x0000), Sink/UFP; 0x0bb0 / 0x0690 = control type 0x10 = Not_Supported.

## 2. Root cause: three tcpm defects in a chain (plus one found on the way)

1. **A timeout during discovery stops discovery silently** (`vdm_run_state_machine`, `case VDM_STATE_BUSY`).
   ERR_TMOUT ends the AMS but neither retries nor completes discovery. `vdm_retries` only covers
   transmit errors (no GoodCRC), and `tcpm_vdm_discovery_work` is only queued on entering Ready, on an
   AMS collision at start, or when the port is busy. Upstream 205dc9cb39f5 ("implement retry mechanism
   for Discover Identity VDMs", in 7.3) covers collisions at AMS start, not response timeouts.
   Why the response was late can't be proven from a tcpm-only log: the FUSB302 is on I2C with a
   threaded IRQ, so tcpm sees both the GoodCRC (which starts the timer) and the response later than
   they happened on the wire. At t=5.9 s many drivers are probing, and the dock's hub is enumerating.
   tcpm uses the maximum tVDMSenderResponse (30 ms), with no slack. tcpm already relaxes
   `PD_T_SENDER_RESPONSE` to 60 ms for this reason. The response timer was not changed here; retrying
   is the robust fix, and changing a spec timer would be a separate argument to make upstream.
2. **A late SVDM response is answered with Not_Supported** (`tcpm_handle_vdm_request`, from a20dcf53ea98).
   PD 3.x Not_Supported is the reply to a received *request* that the port does not support
   (Discover Identity to a port with no `sink-vdos` was the case a20dcf53ea98 meant). An ACK, NAK or
   BUSY is a response, not a request. Answering it starts a stray exchange, and here the dock replied
   with Not_Supported.
3. **Any Not_Supported in Ready is taken as the VDM reply while the VDM state machine is active**
   (`tcpm_pd_ctrl_request`, from f1fbd950b59b). That is valid only in VDM_STATE_BUSY, once the VDM is
   on the wire and the response timer runs. In VDM_STATE_SEND_MESSAGE (the PD3 Source tSinkTx
   collision-avoidance wait) or VDM_STATE_WAIT_RSP_BUSY, nothing has been sent, so the Message
   answers something else. Taking it as the reply drops the unsent VDM, and with it discovery.
4. (Found while reading, would hit the new retry path.) `tcpm_vdm_discovery_work()` resumes Discover
   Modes with `modep_prime->svids[modep->svid_index]` in both PARTNER_MODES and CABLE_MODES. It
   should use the partner's SVIDs with the partner's index, and the cable's SVIDs with the cable's
   index. This came in with 205dc9cb39f5 and is still in mainline master (checked 2026-10-30).

Should the partner's Not_Supported be retried? A genuine Not_Supported reply (in BUSY) means the
partner doesn't support the command, so it is not retried; behaviour there is unchanged. The one in
this log was not a reply, so it is now ignored and the Discover SVIDs goes out. A timeout is
different: the partner has proven SVDM support by answering Discover Identity, so the timeout is
treated as transient and retried.

Upstream: no existing fix. Checked torvalds/linux master tcpm.c history up to 2026-10-05
(98d00deb6ae4, 90156585765b, 205dc9cb39f5, c06e6cd48819 (DISCOVER_MODES NAK; already in 7.3), ...).
Master still has all four defects. Lore search was blocked by its bot check. A web search found
only the 2021 patches that introduced (2) and (3), and the 2026 DISCOVER_MODES NAK fix.

## 3. Fix (4 patches, `work/_out/tcpm/patches/`, copied to `patches/linux` as 0271-0274)

- **0271** `usb: typec: tcpm: Use the right SVID when resuming Discover Modes`
  (Fixes: 205dc9cb39f5): fixes the array index (4).
- **0272** `usb: typec: tcpm: Take Not_Supported as a VDM reply only once the VDM is sent`
  (Fixes: f1fbd950b59b): a reply only in VDM_STATE_BUSY. In SEND_MESSAGE or WAIT_RSP_BUSY it is
  logged ("Ignoring ctrl msg 16, VDM not sent yet") and the VDM is sent as planned (3).
- **0273** `usb: typec: tcpm: Retry discovery after a VDM response timeout`: on a timeout of
  Discover SVIDs or Discover Modes over SOP, re-queue `vdm_discovery_work` after 100 ms. It resends
  the request for the current step, up to 3 times without progress (the counter resets on every
  discovery state change). After that, register the modes found so far and mark discovery
  COMPLETE, like the existing transmit-error path. Discover Identity and SOP' are unchanged (1).
- **0274** `usb: typec: tcpm: Don't answer unexpected VDM responses with Not_Supported`
  (Fixes: a20dcf53ea98): a stray ACK, NAK or BUSY is dropped and logged (2).

Patch order keeps each step non-regressing. 0274 removes the accidental re-queue that the stray
Not_Supported caused, so it comes after the real retry (0273).
The whole `patches/linux` stack (314 patches) applies on clean v7.3 with build-kernel.sh's `git apply --index`
loop (scratch worktree, since removed). The resulting tcpm.c is identical to the branch.
checkpatch --strict: clean, except the expected missing SoB and "unknown commit id" (shallow clone).
Builds with W=1 and no warnings.

## 4. Modules

tcpm, fusb302 and typec are `=m`. tcpm.ko and fusb302.ko are **in the initramfs** (fusb302 probes at about 4 s).
- Production: `~/orangepi5/build/ext-tcpm/out/tcpm.ko` (external build against `build/linux` #4,
  debug-stripped, `sign-file sha512`, vermagic `7.3.0-opi5 SMP preempt mod_unload modversions aarch64`).
  Staged on the board at `/var/tmp/tcpm-test/fixed/tcpm.ko`. Only tcpm.ko changes.
- Test builds, for the measurement only: `/var/tmp/tcpm-test/{stock-test,fixed-test}/tcpm.ko`. They are
  stock and fixed plus a TEST-ONLY module parameter `test_late_svids_ms`. When it is non-zero, the first
  Discover SVIDs after each attach uses that response timeout, so the real ACK arrives "late"
  deterministically. Injection source: `~/orangepi5/build/ext-tcpm-test/inject.py`.
- Install: `sudo /var/tmp/tcpm-test/install-tcpm.sh <ko>`. It installs into `updates/opi5-tcpm/`, runs depmod and
  `update-initramfs -u`. `--remove` undoes it. A **reboot** is needed: tcpm can't be reloaded live,
  because unloading fusb302 removes the aux-HPD DRM bridge from the live rockchipdrm chain.

## 5. Test procedure and results

Script: `work/_out/tcpm/tools/discovery-cycle.sh` (on the board in `/var/tmp/tcpm-test/`).
Each cycle runs `port_type` dual -> sink -> dual. That gives a full PORT_RESET and re-attach,
equivalent to an unplug: the dock loses VBUS, and USB3, NIC, card reader and DP go away. A cycle
passes when `port0-partner.0/displayport/configuration` shows `[sink]` within 12 s. The tcpm log is
saved per cycle.
Note: the tcpm debugfs log is **consumed by reading**. Whoever reads it first gets the lines.

| variant | N | failures |
|---|---|---|
| stock (in-tree), natural | 0 | not measured. The board went to kernel 5 (fixes in-tree) before a slot. Boot observations: 1 failure (04:35 boot) in the boots with this dock where tcpm logs were captured |
| k5 + stock tcpm (k5-stock-test), test_late_svids_ms=2 | 20 | **20/20 FAIL**. Every cycle shows the field sequence exactly: TEST timeout, late ACK 0x248f, our Not_Supported 0x0bb0, the dock's Not_Supported 0x0690, then discovery dead (`board/inj/cycle-1.log`) |
| kernel 5 (0271-0274 in-tree), natural, 07:38-07:50 | 66 (stopped) | **0 discovery failures** (66/66 DP configured, typically in 0.9 s); 0 VDM timeouts or ignored messages; USB: 64/64 cycles re-enumerated all 5 dock devices (hub USB2+USB3, AX88179, Transcend, camera) in 1.3-1.9 s. Cycles 65-66 are confounded: a SanDisk stick was plugged into the dock (8-1.2) during cycle 65, so the device set changed; every device was present afterwards. Stopped so that the stick's owner wasn't disturbed. 3/66 cycles logged `usb 7-1.1 ... error -71` (the Transcend's USB2 side on hub port 1, while it comes up SuperSpeed on 8-1.1); in each case the Transcend did enumerate on 8-1.1, so it is cosmetic |
| k5 + fixed tcpm (k5-fixed-test), test_late_svids_ms=2 | 20 | **20/20 PASS**: 'VDM response timeout, retry discovery (1)', 'Ignoring unexpected VDM response 0xff00a042', then Discover SVIDs resent after 100 ms and discovery COMPLETE; DP configured about 1.0-1.1 s after attach |

Boot observations so far: failing boot (the log above) 1; good boot 05:03 (full discovery, Enter Mode,
Status Update and Configure all ACKed by 4.97 s).

## 6. Not a typec bug: "USB [sink]", the Attention loop, and DP-1 "disconnected" (05:03 boot)

**The typec side is correct.**
- `configuration` = `USB [sink]` means the partner is configured as UFP_D. `[USB]` would mean not configured.
- `pin_assignment` = `C [D]` means D is selected.
- The tcpm log has Enter Mode, Status Update and Configure all ACKed by 4.97 s (`Rx VDM cmd 0xff01a151 type 1 cmd 17`).
- After that the dongle sent Attention (HPD high, IRQ_HPD) about every 1-2 s until about 140 s. `irq_hpd` reached 13 and is still 13 at 05:19.
- DP-1 is `disconnected`/`disabled` all boot. No dw-dp message is logged: its detect failures are silent.

**Why DP-1 is disconnected: the detect path.** Each Attention goes:
- typec `drm_connector_oob_hotplug_event()`
- then `drm_bridge_connector_oob_hotplug_event()`, which runs dw-dp `oob_notify`: it forces the
  controller HPD and, with HPD already high, schedules hpd_work as a short pulse (0268);
- then `drm_bridge_connector_handle_hpd()`, which sets status=connected and sends a hotplug uevent.

So the connector is re-probed after *every* Attention: by fbcon's client hotplug and by the compositor.
`dw_dp_bridge_detect()` returns connected only if both checks pass:
- the controller HPD state reads PLUG (forced by `hpd_sw_cfg`);
- `dw_dp_hpd_detect_link()` works: PHY power-on, then the DPCD caps read over AUX in `dw_dp_link_parse()`.

It went back to disconnected 13+ times. **Re-detection did happen; the DPCD/AUX read (or the forced
HPD state) failed every time for about 2 minutes.**

The short-pulse branch in `dw_dp_hpd_work()` only checks link status when `link->enabled`. With no
modeset it does nothing, and that is fine, because the uevent re-probe already covers re-reading
the DPCD. So dw-dp does not need another retry on Attention+HPD. Two improvements are worth
making there:
1. Log a failed `dw_dp_link_parse()` (at least `dev_dbg`) and the reason (AUX timeout, NAK or DEFER).
2. As i915 does for branch devices, on IRQ_HPD read DPCD 0x200-0x205 (SINK_COUNT,
   DOWNSTREAM_PORT_STATUS_CHANGED) and, if they changed, send a full hotplug event even while the
   link is disabled.

Neither would have produced a picture here if AUX itself was dead.

**Correction to my earlier note:** the `/dev/drm_dp_aux0` read that returned nothing is *not*
evidence. dw-dp powers the PHY (which carries AUX) only inside detect, EDID read and link enable,
so a userspace AUX read with the link down is expected to fail.

**Why AUX failed: undecided, three candidates.**
1. *The dongle's DP->HDMI converter or the Dell input wedged.* A DP->HDMI branch answers DPCD
   0x000 caps itself, whatever the HDMI sink is doing. So a dead downstream Dell alone should not
   make the caps read fail, but a wedged converter MCU would. The steady IRQ_HPD stream fits a
   converter that keeps re-signalling a downstream HDMI HPD/link problem.
   Our earlier pin C/D switching and retrain churn (the dp-smooth / 0267-0269 tests, the 0270
   reproducer that switches the pin assignment) could have left the converter or the Dell in a bad
   state. It is plausible but unproven, and only a dongle replug or power cycle would show it.
2. *The PHY/AUX path after 0270* (`phy-rockchip-usbdp: Keep USB3 running…`, drop-in
   `updates/opi5-usbdp-keep-usb3`, installed 04:09). It changes the first DP entry after boot (pin D)
   from a full `rk_udphy_init()` with DP on to a DP-half-only start (`CMN_DP_INIT_RSTN`). If any of
   the DP/AUX setup depends on the init sequence with `UDPHY_MODE_DP`, AUX would time out on the
   first entry, and on every later entry while USB3 stays on. The journal shows boots -2, -1 and 0 all
   ran with 0270. The kernel log doesn't show whether DP-1 came up on boot -2.
3. HPD forcing (`hpd_sw_cfg`) not taking effect: unlikely, as it is unchanged since DP worked.

**To tell them apart (in my board slot, 2-3 min):**
- Turn on `dyndbg` for dw-dp and `drm.debug=0x100` (DP AUX), run
  `echo detect > /sys/class/drm/card0-DP-1/status`, and read the AUX results:
  - AUX *timeouts* (no reply at all) point to the PHY/SBU path, candidate 2;
  - NAK or DEFER means the dongle answers but is unhappy, candidate 1.
- If it is timeouts, boot once with the 0270 drop-in moved aside (that is the usbdp owner's call).
- If DP-1 stays dead after a dongle replug, that also points to candidate 2.

### 6a. AUX check on the board (boot 0, 05:21, `board/auxcheck.txt`, `board/dp-boot-timeline.txt`)
**What I ran:** dw-dp and usbdp dyndbg plus `drm.debug=0x106`, then `echo detect > card0-DP-1/status`.
Debug is now off again (`drm.debug=0`, dyndbg cleared); the connector was already in `detect`.
- **Every DPCD read times out:** `drm_dp_dpcd_probe 0x00102 AUX -> (ret=-110)` "Too many
  retries", four times in one probe, then DP-1 `disconnected`. -110 means *no AUX reply at all*. It is
  not a NAK or DEFER, so the dongle's AUX responder isn't answering. The DPCD comes from the
  dongle itself, so this is not the Dell.
- **0270 is not the cause, at least not alone:**
  - boot -2 (04:11) ran the same 0270 drop-in and had `DP-1=connected enabled` at both 37 s and 440 s
    (`workaround-removal/board/usb3-after*.txt`);
  - boot -1 (04:35) had no DP because of the tcpm discovery bug (§1);
  - boot 0 has DP Alt Mode configured but AUX dead.
- **Re-detect on Attention:** `check_connector_changed ... DP-1 Same epoch counter 16` shows the
  connector was changed (status set to connected by the OOB event, then probed back to
  disconnected) about 16 times this boot. That is about one per Attention, so re-probing *does*
  happen through `drm_bridge_connector_handle_hpd()`'s hotplug event. dw-dp's own short-pulse
  branch in `dw_dp_hpd_work()` does not re-detect, which is literally true and is the workaround
  agent's point. Either way it would not help while AUX gets no reply.
- **Side effect:** the forced probe sent a hotplug event. The compositor re-set the HDMI mode and
  FRL retrained at 1122.7 s, which may have caused a short HDMI blank in the max-everything session.
- **Next step:** replug the dongle, or power-cycle it by unplugging. If AUX then answers, the
  dongle's converter had wedged. If it is still -110, look at the PHY AUX path on this boot
  (orientation and AUX polarity in `rk_udphy_dp_lane_select()`).

### 5a. Final natural run on kernel 5 (r-k5b, 08:00-08:12): 100/100 PASS, 0 VDM timeouts
The baseline now includes the Ultra Fit (6 dock devices). Discovery and DP configure passed in all 100
cycles. The 4 "usbfail" cycles (23, 55, 71, 74, i.e. dock attaches 97, 129, 145 and 148 in the journal of
that boot) are all the **Transcend card reader coming up at High-Speed on the USB2 hub port 7-1.1
instead of SuperSpeed on 8-1.1**. In each case it was present 1.9-3.4 s after the hub attached and
needed no intervention. It stays at 480M until the next attach. No device was ever absent.
Across all 175 attaches that boot, the reader fell back to HS 5 times. About half of the
attaches log `usb 7-1.1: device descriptor read/64, error -71` (sometimes followed by
`7-1-port1: attempt power cycle`) before the reader comes up on SS.
**Root cause (where it isn't):** the SS link that fails is the one between the dock hub's downstream port 1
and the reader. Both PHYs are inside the dock, and the host only sees the hub report a USB2
connection. The other dock devices (AX88179 on port 3, Ultra Fit on port 2, the hub's own upstream
links) never fail. tcpm, usbdp and xhci are not in that link. No kernel fix applies; a host-side
"retry SS" would be a workaround. To split reader vs hub port: move the reader to another dock
port or to the board's Type-A port and repeat the cycles (each cycle takes about 8 s).
SanDisk Extreme on the top Type-A port (6-1): `speed` = 5000 on every boot of this session, first
enumeration `usb 6-1: new SuperSpeed USB device number 2 using xhci-hcd` at 3.79 s.
Final state: kernel #5, in-tree tcpm.ko (srcversion 040E7EF195D0AA5F11E2C01), `updates/` empty,
initramfs without drop-ins, DP-1 connected, port_type dual.
