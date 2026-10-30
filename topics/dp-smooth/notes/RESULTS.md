# USB-C DP alt mode as smooth as HDMI: results (2026-10-29)

Board: Orange Pi 5, kernel 7.3.0-opi5 #3 (patches/linux, 292 patches). DP-1 (connector 86, CRTC 84 =
video_port2) goes through the USB-C hub dongle to the Dell P2415Q. HDMI-A-1 (connector 88, CRTC 83 =
video_port0) goes to the TCL TV at 3840x2160@60.

## TL;DR
1. **The choppiness is mostly not the DP link. It comes from how kmssink is used.** kmssink's default
   (`skip-vsync=false`) waits for vblank twice on atomic drivers. `drmModeSetPlane` is already a
   blocking atomic commit, and then kmssink waits for another vblank. A new frame can then only be
   shown every 2 refreshes, and late-buffer drops follow. At the DP's 30 Hz that gives **~10 fps** with
   60 fps clips and **~12 fps** with 30 fps clips. HDMI at 60 Hz gets ~30 fps. That is why DP looked so
   much worse than HDMI.
2. The second cause is the **fbcon cursor blink**. The text console stays under the video plane on both
   CRTCs. Every 200 ms the blink does a dirtyfb commit on each CRTC that shows the console. The video's
   blocking commit then waits one more refresh, which drops a frame (DP: 24 instead of 30 fps).
3. Only after those two fixes does the 30 Hz refresh matter. 60 fps content can then only be shown at 30 fps.
   The vblank/flip timing itself is clean on both CRTCs (σ ≈ 25–35 µs). No vop2, dw-dp or PSR pacing
   problem was found.
4. **4K60 is not possible on this cable and monitor input, with any pin assignment.** The dongle is a
   DP→HDMI converter (PCON). It reports 2 lanes at HBR2 even in pin assignment C, and its HDMI side
   runs at ≤ 340 MHz TMDS. The Dell's EDID on that input allows only 300 MHz TMDS (HDMI 1.4 VSDB) and
   has no YCbCr 4:2:0 support. 4K30 is the ceiling there. 4K60 on the Dell needs its DP or mDP input:
   a USB-C→DP cable or adapter, DP 1.2 enabled in the Dell OSD, and pin assignment C/E.
5. Bug found while testing: **after any pin-assignment change the DP link stays dead** (black screen)
   until something does a full modeset. Fixed in the kernel (2 patches, below). The modules are
   installed on the board and take effect after a reboot.

## Measurements
Tools are in `tools/`. `flipmeasure.sh` plays a clip with v4l2codecs and kmssink while recording
`drm_vblank_event*` in a private tracefs instance. `cadence.py` turns the trace into a histogram of
vblank-sequence deltas between successive frame commits: 1 means a new frame on every refresh.
`vblwait.c` is a vblank-timestamp logger that needs no DRM master. Raw data is in `meas/`. Each run is
8 s, with the HEVC reference clips from `~/codecsweep/work`. fps is fpsdisplaysink's average.

| case | DP (30 Hz) | HDMI (60 Hz) |
|---|---|---|
| kmssink default, 1080p60 clip | 9.4 fps, Δseq {3:33, 4:4} | 30 fps, Δseq {2:98} |
| kmssink default, 1080p30 clip | 12 fps, Δseq {2:50, 3:22} | 30 fps |
| kmssink default, 2160p60 clip | 9.7 fps | 19 fps |
| `skip-vsync=true`, 1080p30 | 23.7 fps (cursor blink drops) | – |
| `skip-vsync=true`, 1080p60 | 20.6 fps | 51.5 fps |
| `skip-vsync=true` + cursor hidden, 1080p30 | **30.1 fps, 0 dropped**, Δseq {1:162} | – |
| `skip-vsync=true` + cursor hidden, 1080p60 | **29.3 fps** (every other frame dropped, as expected at 30 Hz) | **60.0 fps, 0 dropped**, Δseq {1:242} |
| `skip-vsync=true` + cursor hidden, 2160p60 | 21.7 fps (60→30 decimation is uneven, Δseq {1:81, 2:20}) | **60 fps, 0 dropped** |

* Vblank intervals: CRTC 83 16.666 ms σ 0.02–0.03 ms, CRTC 84 33.431 ms σ 0.02–0.04 ms. These hold idle,
  during decode to fakesink, and during kmssink playback. (The first run used `GST_DEBUG=*:7` and showed
  ±10 ms IRQ-time jitter. That jitter did not reproduce without the debug logging, so treat it as a
  measurement artifact.) Timestamps are `high-prec=false`, because vop2 has no
  `get_scanout_position`. They are taken in the IRQ handler, which is fine here.
* With the cursor visible and no client running, 5 dirtyfb commits/s land on each CRTC
  (`tools/idlecommits.sh`: 24 per CRTC in 5 s). With `\e[?25l` or `cursor_blink=0` there are none.
* Kernel path behind cause 1: `drm_atomic_helper_update_plane()` uses a blocking `drm_atomic_commit()`.
  kmssink 1.28.7 `gst_kms_sink_show_frame()` calls `drmModeSetPlane()` and then
  `gst_kms_sink_sync()` → `drmWaitVBlank(RELATIVE 1, EVENT)`. kmssink's own property doc says
  "Should be used for atomic drivers to avoid double vsync". The default is still FALSE.

## DP link / 4K60 findings
* Alt mode VDO 0x00000c05: UFP_D, plug, DP1.3 signalling, pin assignments C and D. The kernel picks D
  because the partner sets *multi-function preferred* (`dp_altmode_configure()`). That is per spec and
  not a mis-negotiation. The upstream policy knob is `/sys/bus/typec/devices/port0-partner.0/displayport/pin_assignment`,
  and a udev rule can write it.
* DPCD: rev 1.2, max rate 0x14 (HBR2), **max lanes 2 (0x02 = 0xc2), also after switching to pin C,
  re-detecting and modesetting**. DOWNSTREAMPORT_PRESENT 0x1d with port 0 type HDMI (0x80 = 0x0b), max
  TMDS 340 MHz (0x81 = 0x88), and 4:4:4→4:2:0 conversion supported (0x83 = 0x17). Branch OUI 00-10-fa.
* Pin C test: the USBDP PHY re-inits "USB3=off and DP=on (4 lanes)", the dongle's AX88179 drops to
  480M, and dw-dp trains **2 lanes at 5400 MHz** (CR + EQ OK). The mode list does not change.
* Trained link: HBR2 × 2 lanes = 8.64 Gbit/s, which is enough for 4K30 (262.75 MHz CVT-RB, 6.3 Gbit/s
  RGB888). RK3588 dw-dp (`max_link_rate = 810000`) and the USBDP PHY (`max_link_rate = 8100`) both
  support HBR3, but the dongle is HBR2.
* Dell EDID (`dell-p2415q.edid`): DTDs are 4K@29.98 RB (preferred), 4K30, 1440p60 and 1080p60.
  The range descriptor gives max 300 MHz pixel clock, and the HDMI VSDB max TMDS is 300 MHz. There is no
  HF-VSDB and no Y420 block, so 4K60 4:2:0 over 2 lanes is not possible on this input either. dw-dp
  supports 4:2:0 output (`ycbcr_420_allowed`, YCBCR420 bus formats), so 4:2:0 would work with a sink
  that advertises it.
* **Policy decision: keep the kernel default (D) for this dongle.** C gives no extra bandwidth and costs
  USB 3. `overlay/etc/udev/rules.d/90-opi5-dp-altmode-pin-c.rules.disabled` is an optional,
  documented rule for real 4-lane adapters into a DP 1.2+ sink. It is not installed.
* If 60 Hz matters more than 4K on the Dell over this dongle: 2560x1440@60 (241.5 MHz) and 1080p60 fit
  both the link and the HDMI 1.4 input, for example `video=DP-1:2560x1440@60` on the kernel cmdline.
  This trades resolution for refresh rate. Not applied.

## Bug found and fixed: link not retrained after a pin-assignment change
Reproduced 3 times: switching D→C or C→D left DPCD 0x202–0x203 = 00 00 (no CR/EQ on any lane). The
screen stayed black until a modeset (`modetest -s 86@84:...`). dw-dp logged nothing, because:
1. `dw_dp_bridge_oob_notify()` only forces the HPD level (`hpd_sw_cfg`). An OOB event that keeps HPD
   high creates no controller edge, so IRQ_HPD from DP Alt Mode Attention is dropped. In pin C the
   dongle kept sending Attention with IRQ_HPD every ~2.3 s (irq_hpd 5→14), and nobody acted on it.
2. `dp_altmode_configured()` sends no event after a Configure while HPD is high. After C→D the dongle
   sent no Attention at all.

**Update 22:11 (after the first reboot):** with only the dw-dp and typec fixes, the short-pulse path ran
("Get hpd irq - short", "Retraining link") but clock recovery failed on every lane. Cause: in
`rk_udphy_update_power_state()`, a mux-driven re-init (`rk_udphy_init()`) leaves all DP lanes disabled.
They are only enabled in `rk_udphy_dp_phy_power_on()`, which is why a modeset (PHY off/on) recovered.
I added a third patch (now 0267) for the PHY, and dw-dp now retries the retrain on a later IRQ_HPD
after a failed attempt. Both are installed, but not yet tested on the board: **they need another reboot.**

Fixes on branch `opi5/dp-smooth-7.3` (worktree `~/orangepi5/work/dp-smooth-7.3`, based on
`opi5/integration-7.3`). Exported as `patches/0267..0269-*.patch`; they apply after 0266:
* `0267 phy: rockchip: usbdp: Re-enable DP lanes after a re-init with DP powered on`.
* `0268 drm/bridge: synopsys: dw-dp: Treat OOB HPD events with HPD high as IRQ_HPD`: an OOB event that
  keeps HPD asserted queues the HPD work as a short pulse (unless a long pulse is pending). That path
  checks the link status and retrains.
* `0269 usb: typec: altmodes/displayport: Notify HPD after reconfiguring with HPD high`: after the new
  configuration is applied to the mux, send an OOB "connected" event, so the DP driver can retrain.

checkpatch --strict: clean except the expected missing Signed-off-by. Built `W=1` against
`build/linux` with no warnings.
Limitation (documented, not addressed): a short-pulse retrain keeps the lane count from the last full
detect. Moving a real 4-lane sink from C to D needs a modeset to drop to 2 lanes; the 2-lane dongle
here is not affected.

## GStreamer fix (upstream candidate, draft, not compile-tested)
`gstreamer/kmssink-skip-redundant-vsync-on-atomic.diff` (against 1.28.7). In `get_drm_caps()` it
probes `DRM_CLIENT_CAP_ATOMIC` on kmssink's own fd, then resets it to 0, which restores the default
client caps. If the driver is atomic and kmssink presents with `drmModeSetPlane()` (not in modesetting
mode), it skips the extra `gst_kms_sink_sync()`. Measured equivalent: `skip-vsync=true` (table above).
Not compile-tested: there are no gst or libdrm dev headers on the host or the board.
Not sent anywhere.

## What to use now (userspace config, nothing hacky)
* `overlay/usr/local/bin/opi5-play <file> [dp|hdmi]` (also at `~/dpsmooth/opi5-play` on the board,
  tested: DP 30 fps clip, Δseq {1:139}). It runs `playbin3` → v4l2sl* decoder (rank primary+1) →
  `kmssink connector-id=… plane-id=65 (DP) / 59 (HDMI) skip-vsync=true`, and hides the cursor on the
  foreground VT while it plays.
* For any hand-written pipeline, add `skip-vsync=true` to kmssink (never together with
  `force-modesetting=true`: in modesetting mode kmssink's sync is the page flip itself) and hide the
  console cursor (`setterm --cursor off > /dev/tty1` or `printf '\e[?25l' > /dev/tty1`).
* System-wide alternative for a media box: add `vt.global_cursor_default=0` to `U_BOOT_PARAMETERS` in
  `overlay/etc/default/u-boot`. Not done, because it hides the console cursor for everyone. A
  compositor (weston/cage + waylandsink) avoids the issue too, because it puts the VT in KD_GRAPHICS.

## Board state after this work
* `pin_assignment` restored to **D**. The DP link was retrained by a modeset and is up at 4K30, 2×HBR2.
  The AX88179 was moved back to 5000M with a hub-port disable/enable cycle. The fbcon cursor and
  cursor_blink were restored, and dynamic debug was turned off.
* Installed for the next boot: `/lib/modules/7.3.0-opi5/updates/opi5-dp-smooth/{phy-rockchip-usbdp,dw-dp,typec_displayport}.ko`
  (signed, no BTF, modversion CRCs identical to the in-tree modules), then `depmod -a` and
  `update-initramfs -u` (both modules are in the initramfs). Backup:
  `/var/tmp/initrd.img-7.3.0-opi5.pre-dp-smooth`. **Needs a reboot** to load. To undo: remove the dir,
  `depmod -a`, `update-initramfs -u` (or restore the backup initrd).
* After the reboot, test with `TESTING.md`.

## "4K60 looks good, then warped for a bit" (investigated 22:15)
* Buffer lifetime: kmssink with `skip-vsync=true` is safe. `show_frame()` releases the previous buffer
  (`gst_buffer_replace(&last_buffer, …)`) only after `drmModeSetPlane()` returns. On rockchip that
  call is a blocking commit (`drm_atomic_helper_commit_tail_rpm` → `wait_for_vblanks`), so the new fb
  is already latched by then. Planes 59 and 65 are Overlay planes, not cursor planes, so there is no
  `legacy_cursor_update` shortcut. The v4l2slh265dec CAPTURE pool has 8 buffers, cycled round-robin
  (2160p60 clip), so a released buffer is not reused for ~8 frames.
* What does match the symptom: **vop0 `POST_BUF_EMPTY` underflow bursts**. They appear in this boot at
  127, 135, 140 and 193 s, and 10 messages (rate-limited) came in an 8 s window with no playback at
  all. A 4K60 HDMI playback window had 0 with `skip-vsync=true` and 10 with `false`, so they track
  whatever else is loading DDR (codec/RGA agents' jobs), not the sink setting. There is no DMC devfreq,
  so DDR frequency switching is not the cause. Likely fixes are in the VOP2/NoC QoS area (VOP read
  priority, as the vendor kernel sets it). Scanout load also matters: the 4K XR24 console plane stays
  enabled under the video on both CRTCs. That belongs to the VOP2 agent's work, and I did not change it.

## Verified after the 22:23 reboot (all three modules from updates/opi5-dp-smooth)
D→C→D: DPCD 0x202 read `77 00` at t+1/2/3 s after each switch, with no black screen and no modeset.
dw-dp logged "short HPD → Retraining link → 2 lanes at 5400 MHz, CR and EQ succeeded" ~0.36 s after
each switch. No SError or oops. The AX88179 stayed at 5000M after returning to D.
