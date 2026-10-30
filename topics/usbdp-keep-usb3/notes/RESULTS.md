# Workaround removal: kmssink, weston kiosk-shell, USB3 on DP AltMode entry

Status 2026-10-30 04:35, after the board slot (04:01-04:34, one reboot):
- **Item 3, USB3 on DP entry: fixed and verified on the board.**
- **Item 2, weston: fixed and tested on the host.**
- **Item 1, kmssink: partly verified.** The board test found a fatal bug in our own 0001 (fixed: series rework below). The cursor fix
  (now 0007) is verified. Two kmssink problems remain open: automatic plane choice, and 4K120 after a modeset. opi5-play therefore stays for now;
  the `video=` cmdline is removed on the board. Our patches carry `Assisted-by: Claude:claude-opus-5-5` only (no SoB, no Co-Authored-By).

## 1. GStreamer kmssink (opi5-play, `video=HDMI-A-1:3840x2160@60`)

What the workarounds covered, and where each is fixed:

| Symptom | Workaround | Root cause | Fix |
|---|---|---|---|
| 4K H.264 goes to the 1080p Hantro | (playbin pick) | v4l2codecs registers static sink caps, so every device looks the same | 0001 (per-device frame-size caps) |
| 60 fps → 30 fps | `skip-vsync=true` | SetPlane is already a blocking atomic commit, and kmssink waits for vblank again | 0002 |
| 4K120 capped at ~63 fps | — | blocking SetPlane per frame | 0005 (non-blocking atomic commits + flip events) |
| can't modeset with an overlay plane, no refresh choice | console `video=…@60` | legacy SetCrtc with the NV12 buffer on the Cluster primary; first WxH mode wins | 0003 (black XR24 primary, video on the overlay), 0004 (mode whose refresh is a multiple of the frame rate) |
| frame drops while the console cursor blinks | opi5-play hides the cursor | **new, 0006**: without modesetting kmssink leaves fbcon's fb on the primary plane. Each fbcon update (cursor blink every 200 ms) is flushed by `drm_atomic_helper_dirtyfb()`, a blocking atomic commit on every plane showing that fb, i.e. on the video's CRTC. That delays the next video commit by a refresh | **0006** "kmssink: Take over the CRTC when showing video on an overlay plane": a black XR24 buffer on the primary in the *current* mode (no full modeset: `drm_mode_equal` → `mode_changed` stays false), restored on stop (`restore-crtc`). Skipped when kmssink is not DRM master or the fd is the application's |

Right layer for the cursor issue: userspace (kmssink). The kernel behaves as designed. fbcon owns the VT while it
is in KD_TEXT, and fbdev emulation must flush its damage. A DRM client that shows video on a CRTC without owning
that CRTC's primary plane races with the primary's owner. A modeset (0003) already takes the CRTC over; 0006
does the same without changing the mode. The console comes back when the sink stops, and the kernel's
`drm_fb_helper` lastclose restore covers it as well.

Note on (c): kmssink only modesets with `force-modesetting=true`, or when the CRTC is off (upstream behaviour,
unchanged). The 4K120 mode comes from 0004: a 120 fps stream picks the 3840x2160@120 mode.

Files:
- `patches/gstreamer/0001-0005` (existing, built into `out/debs-media/*+opi5.1*`).
- `work/_out/workaround-removal/gstreamer/0006-kmssink-Take-over-the-CRTC-when-showing-video-on-an-.patch`. It is not
  yet in patches/gstreamer, and goes there after the board test. Source tree: `work/gst-kms-6/src` (git, 0002-0006
  on 1.28.6-1ubuntu1). arm64 build of just the plugin (0 warnings): `gstreamer/libgstkms-0006-arm64.so`
  (`work/gst-kms-6/scripts/run.sh`, mmdebstrap arm64).
- Board test: `board/gst-kmssink-test.sh` (decoder fd, CRTC mode and plane formats from debugfs dri state,
  fpsdisplaysink rendered/dropped).

### Board evidence (kernel #4, HDMI 3840x2160@60 console, logs `board/gst-*.txt` = board `~/wr/gst-*.txt`)
- **0001 was broken.** With the +opi5.1 debs, H.264 and HEVC on rkvdec could not link at all ("could not link h264parse0 to
  v4l2slvideo6h264dec0"; playbin3: "Missing element: H.264 (High Profile) decoder"). The sink caps query returned **VP9** caps.
  Cause: 0001 stored the probed sink caps in the `GstV4l2CodecDevice`, which all codecs of a device share. class_init runs lazily,
  when the element is first created and the plugin comes from the registry cache, so it saw the caps of the last codec probed. Upstream
  has the same latent bug for `device->src_caps`. Fix: new **0001 "v4l2codecs: Keep the src template caps per registered decoder"**
  (per-registration `GstV4l2DecoderClassData`, an upstream fix). **0002** is the old 0001, reworked to use that class data.
  kmssink 0003-0007 are the old 0002-0006. arm64 build: 0 warnings (`work/gst-v4l2cd/`). `patches/gstreamer/` now holds 0001-0007,
  with the old set in `patches/gstreamer.bak-20261030/`. REV bumped to 2 in `scripts/build-media-debs.sh`. **The +opi5.1 debs in out/debs-media must
  not be used. Rebuild gst-plugins-bad1.0 → +opi5.2.**
- (a) With the fix, playbin3 picks `v4l2slvideo6h264dec` = rkvdec (/dev/video6) for 4K H.264. Decode alone runs at 127 fps.
- (d) Cursor blink, plain kmssink with plane-id=Esmart0, cursor visible on tty1:
  - without 0007: rendered 1996, **dropped 72, 54.8 fps**;
  - with 0007: rendered 2199, **dropped 0, 59.95 fps**, and kmssink logs "showing a black buffer on the primary plane".
- (b, c) force-modesetting 4K60: 0 dropped, 59.95 fps, "setting mode 3840x2160@60.000", NV12 on Esmart0 with the black XR24 primary.
- **Open 1: automatic plane choice.** Plain `kmssink connector-id=` with no plane-id picks Cluster2. That is the first overlay
  plane of the CRTC, and the RK3588 Cluster planes can't scan out linear NV12. playsink then converts to YUYV on the CPU: 0.78 fps,
  and VOP2 `POST_BUF_EMPTY` errors (all of the 951-1037 s burst the coordinator saw, during that run and the next modeset run).
  kmssink's `find_plane_for_crtc()` ignores formats. Needed: a kmssink patch that prefers a plane that can scan out the
  negotiated format (or the decoder's formats). Not done yet.
- **POST_BUF_EMPTY answer:** none occurred with 0007's black XR24 Cluster0 primary plus an NV12 Esmart0 overlay at 4K60. The 180 errors
  all fell in the Cluster-plane YUYV CPU-copy runs (two Cluster planes, CPU-written frames), so 0007's primary buffer doesn't cause them. A 4K120
  check of that pair is still owed (see open 2). If the bandwidth is marginal there, the black primary could be a small buffer
  scaled up, or the primary could be disabled where VOP2 allows it.
- **Open 2: 4K120 after a modeset.** "setting mode 3840x2160@120.000" works, but the pipeline is ~7 s late right after the FRL mode
  switch, so QoS drops most of the 5 s yacht clip (7 rendered). Needs a longer 120 fps clip, and a check of what blocks after the modeset
  (first atomic commit / flip_done after FRL training).
- DP was not run in this slot.

## 2. weston kiosk-shell ignores `set_fullscreen(output)`

Root cause: in `kiosk-shell/kiosk-shell.c` `desktop_surface_committed()`, the first-commit block
`if (!shsurf->appid_output_assigned && app_id)` sets `shsurf->output = NULL` and re-runs
`kiosk_shell_surface_find_best_output()`. That throws away the output that `desktop_surface_fullscreen_requested()`
had already stored, and the configure was even sent with that output's size. The reset was meant only for the
output picked in `desktop_surface_added()` before the app_id was known. Clients without an app_id are not affected.

Fix: `kiosk_shell_surface::output_requested`, set when the client passes an output with fullscreen. The first-commit
reset is skipped then, so an explicit request wins over `[output] app-ids`. desktop-shell behaves the same way, as does
kiosk-shell after map.

Test: `tests/kiosk-shell-multi-output-test.c` (meson test `kiosk-shell-multi-output`). It runs two headless outputs,
two app_id surfaces fullscreen on "headless-1" and "headless", and checks `wl_surface.enter`. Before the fix:
"surface "headless-1" requested output headless-1, entered headless" (ERROR). After: pass. Full suite after the fix:
49 OK, 0 fail, 10 skipped (backends not built). Two supporting patches add the multi-output headless setup:
`--output-count` for headless, and `compositor_setup.output_count`.

Patches: `patches/weston/0001-0003` (on weston 16.0.0, which is Ubuntu 16.0.0-1 plus 2 unrelated debian patches).
Upstream: not fixed on main. Matches the open issue https://gitlab.freedesktop.org/wayland/weston/-/issues/1080.
Notes and logs: `weston/NOTES.md`, `weston/logs/`. No deb was built (arm64 under qemu takes hours). To add one:
`[weston]=16.0.0-1` in VERSION, `[weston]=1` in REV and `[weston]=weston` in PDIR of `scripts/build-media-debs.sh`.

## 3. USB-C dock USB3 drops on DP AltMode entry

Evidence before the fix (kernel #4, boot): hub 8-1 enumerated at 5.19 s and the AX88179 at 6.44 s, then
`usb 8-1: USB disconnect` at 8.05 s and re-enumeration at 9.74 s. On the 03:45 boot it was
`usb 8-1: can't set config #1, error -110`, then disconnect. Same cause: the PHY reset landed in the middle of enumeration.

Root cause (phy-rockchip-usbdp): patch 0240 ("Add USB-C state without DP enabled", Collabora, not in mainline yet)
gives USB-only its own hw_mode, and `rk_udphy_mode_set()` sets `phy_needs_reinit` on every hw_mode change. Entering DP
with pin assignment D (USB-only → USB3 + 2 lane DP) therefore runs the full `rk_udphy_init()`: all PHY resets
(init/cmn/lane/pcs_apb/pma_apb) are asserted for 10 ms, the DWC3 PIPE goes into reset (dwc3-rockchip reset handler), and
the USB3 port is disabled. The SuperSpeed link drops. The commit message of 0240 even expects "some more USB reconnections". The
same happens on every DP Configure, because `dp_altmode_configure_vdm()` puts the mux into TYPEC_STATE_SAFE (USB-only) first.
The reset isn't needed. USB-only and pin D have the same lane mux: `rk_udphy_set_lane_mux()` routes lanes 0/1 (2/3 flipped)
to USB3 in both. The DP half has no reset line of its own. It is gated by `CMN_DP_INIT_RSTN`, and its PLL by
`CMN_DP_CMN_RSTN`, which `rk_udphy_dp_phy_configure()` releases at link-rate setup.

Fix: kernel patch "phy: rockchip: usbdp: Keep USB3 running when entering or leaving DP AltMode". A full re-init is
requested only when the USB3 part turns on or off or the lane routing changes (4 lane DP, orientation). Otherwise only the
DP half is started or stopped through `CMN_DP_INIT_RSTN`, with no DWC3 reset handler and no u3 port toggle. The DP lanes are
restored in both paths, factored out of 0267. During pin C, USB3 still goes down by necessity: no lanes are left for it.
- Branch `opi5/usbdp-keep-usb3-7.3` (worktree `work/usbdp-keep-usb3-7.3` = v7.3 + patches/linux 0001-1408 + 1 commit).
- Patch: `usbdp/0001-phy-rockchip-usbdp-Keep-USB3-running-when-entering-o.patch`. checkpatch --strict: only "missing SoB"
  and one long reproducer line. It belongs in **patches/linux right after 0267/0269**, e.g. as `0270-...` (it touches the 0267 hunk).
- Signed drop-in `usbdp/phy-rockchip-usbdp.ko` (vermagic 7.3.0-opi5, no BTF section, sha256 22f717b0…). The module
  is in the initramfs, so it needs update-initramfs and a reboot.
- Board test: `board/usb3-altmode-test.sh`. It does O_DIRECT reads from the dock's USB3 SD reader (8-1.1, `/dev/sdb`) during
  3× altmode exit/enter (`port0-partner.0/active`) and D→C→D, then counts 8-1 disconnects and dd errors, with phy dyndbg on.
  The NIC has no cable (link DOWN), so its enumeration and disconnects are checked, but not its traffic.

### Board evidence (logs `board/usb3-{before,after,after2}.txt`; the module is installed as updates/opi5-usbdp-keep-usb3, in the initramfs)
- **Before**, stock PHY module: every DP AltMode exit/enter re-initialised the PHY ("reinit PHY with USB3=on and DP=…"), and hub 8-1
  disconnected each time (3 disconnects). After the pin D step (two full re-inits 60 ms apart during enumeration) the dock
  **never came back**: `usb 8-1: device descriptor read/8, error -71` repeated through an xhci port power cycle and later PHY
  re-inits, and the reader also failed on the USB2 side (7-1.1, -71), while the webcam on the same USB2 hub (7-1.4) kept working. So the dock's
  hub/reader was wedged by the back-to-back link resets. The host PHY was not stuck, and only a reboot (VBUS cycle) recovered it.
- **After (0270), two runs:** boot has no 8-1 disconnect (devices 2/3/4). 3× exit/enter logs "disable/enable DP (2 lanes), keeping
  USB3=on" with **0 disconnects**, and dd O_DIRECT reads from the dock's SD reader run without error through all six transitions. The only
  disconnect is around pin C (4 lane DP, so no USB3 lanes, as expected). The dock re-enumerates at SuperSpeed once at C→D (hub, reader, NIC)
  without errors. DP-1 is connected and enabled afterwards. The NIC has no cable, so there was no traffic test on it.
- The coordinator's non-recovery case is therefore covered by 0270: the resets that wedged the dock no longer happen on entry or exit.

## 4. Board procedure as run (one slot, ~40 min, both displays free of weston/players, 1 reboot)
Staged in `~/wr` on the board: the 4 debs, `kms6/libgstkms.so`, `phy-rockchip-usbdp.ko`, and both scripts.
1. `sudo ~/wr/usb3-altmode-test.sh before`. Baseline: DP blanks and re-enters a few times.
2. `sudo apt-get install ./wr/debs/*.deb`. The packages are gstreamer1.0-plugins-bad, gstreamer1.0-plugins-extra,
   libgstreamer-plugins-bad1.0-0 and libgstreamer-plugins-extra1.0-0, all 1.28.6-1ubuntu1 → +opi5.1. Way back:
   `sudo apt-get install --reinstall gstreamer1.0-plugins-bad=1.28.6-1ubuntu1 gstreamer1.0-plugins-extra=1.28.6-1ubuntu1
   libgstreamer-plugins-bad1.0-0=1.28.6-1ubuntu1 libgstreamer-plugins-extra1.0-0=1.28.6-1ubuntu1`.
   Then `sudo ~/wr/gst-kmssink-test.sh opi5.1 hdmi plain60 ms60 ms120 plain120` and `... opi5.1 dp plain60 ms60`.
3. 0006: `sudo cp ~/wr/kms6/libgstkms.so /usr/lib/aarch64-linux-gnu/gstreamer-1.0/`, `rm -rf ~/.cache/gstreamer-1.0 /root/.cache/gstreamer-1.0`,
   then rerun step 2's tests with the label `kms6`. dpkg restores the file on the next deb install.
4. `sudo install -D -m644 ~/wr/phy-rockchip-usbdp.ko /lib/modules/7.3.0-opi5/updates/opi5-usbdp-keep-usb3/phy-rockchip-usbdp.ko && sudo depmod -a 7.3.0-opi5 && sudo update-initramfs -u`.
   Then remove `video=HDMI-A-1:3840x2160@60` from `/etc/default/u-boot` U_BOOT_PARAMETERS. Keep `U_BOOT_ROOT=root=LABEL=rootssd`: the overlay
   default says `rootfs`, and opi5-install-ssd rewrites that on SSD installs. Then `sudo u-boot-update` and reboot.
5. After the reboot: `sudo ~/wr/usb3-altmode-test.sh after` and the boot log, then `gst-kmssink-test.sh final hdmi` with the default console mode.
6. If all pass: move 0006 into patches/gstreamer, delete overlay/usr/local/bin/opi5-play, and rebuild gst-plugins-bad (+opi5.2).

### Board state left behind (2026-10-30 04:34)
- **Kernel modules:** `/lib/modules/7.3.0-opi5/updates/opi5-usbdp-keep-usb3/phy-rockchip-usbdp.ko` (0270), in the initramfs.
- **Boot config:** `/etc/default/u-boot` without `video=` (backup `/var/tmp/u-boot.default.pre-workaround-removal`); u-boot-update has been run.
- **gst packages:** gstreamer1.0-plugins-bad, gstreamer1.0-plugins-extra, libgstreamer-plugins-bad1.0-0 and libgstreamer-plugins-extra1.0-0 at
  1.28.6-1ubuntu1+opi5.1.
- **Files over the deb:** `/usr/lib/aarch64-linux-gnu/gstreamer-1.0/libgstv4l2codecs.so` (md5 e28f1604…) and `libgstkms.so` (ffbd1f48…) are
  the fixed 0001-0007 builds. Without them, H.264 and HEVC on rkvdec don't link.
- **Way back:** `sudo apt-get install --reinstall gstreamer1.0-plugins-bad=1.28.6-1ubuntu1 gstreamer1.0-plugins-extra=1.28.6-1ubuntu1
  libgstreamer-plugins-bad1.0-0=1.28.6-1ubuntu1 libgstreamer-plugins-extra1.0-0=1.28.6-1ubuntu1`.

## 5. Host work after the slot (04:35-04:45)

### 0008 "kmssink: Pick a plane that can scan out the negotiated format" (built, 0 warnings; board test pending)
- **Why:** without plane-id, kmssink took the first plane usable with the CRTC (Cluster2) and advertised only that plane's caps.
  That plane does YUV only with AFBC, so playsink converted the stream to YUY2 in software (0.78 fps, POST_BUF_EMPTY).
- **What it does with an automatic plane:**
  - every other non-primary, non-cursor plane of the CRTC becomes a candidate, and the allowed caps are the union of all candidates' caps;
  - `set_caps()` switches to the first candidate that can scan out the negotiated caps; the current plane wins if it can;
  - plane setup (type, vblank rule, atomic props, plane properties) is factored out and redone for the new plane;
  - on renegotiation, the old plane is disabled after its last flip;
  - the choice is redone on every start, and freed in stop/finalize.
- **Left out of the candidates:** primary planes of other CRTCs (frames on a primary are page-flipped on the CRTC) and cursor planes.
- **Files:**
  - patch: `gstreamer/series/0008-*`; its commit message says "After: TO BE MEASURED", to be filled in after the board test;
  - it is **not yet in patches/gstreamer**, which has 0001-0007;
  - plugin: `gstreamer/libgstkms-0008-arm64.so`, staged on the board as `~/wr/kms8/libgstkms.so`;
  - tree: `work/gst-v4l2cd/A`, branch HEAD = 0001-0008 on 1.28.6.
- **Board check:** `gst-kmssink-test.sh k8 hdmi plain60 ms60 ms120` with no plane-id.
  - Expect: "plane 47 can't show … using plane 59", NV12, 60 fps, 0 dropped, no POST_BUF_EMPTY.
  - Also check that HDMI and DP sinks running together pick different planes.

### 4K120 lateness after kmssink's own modeset: diagnosis plan (`board/k120-diag.sh`)
- **Seen:** SetCrtc 60→120 Hz (FRL) takes 0.37 s in configure_mode_setting, yet frames are ~7 s late afterwards.
  A frame with pts 3.9 s was dropped at running time 11 s, and the decoder's QoS drops nearly everything.
- **Leading hypothesis:** after the FRL mode switch, page-flip events for the first non-blocking commits arrive late or not at all.
  `gst_kms_sink_wait_flip()` gives up after 3 s and logs "no page flip event: timeout"; two of those plus the modeset ≈ 7 s.
  The /tmp log with the WARNINGs was lost when the board rebooted.
- **Script, on a 60 s clip** (`ffmpeg -stream_loop 11 -c copy` of the yacht clip):
  - A: force-modesetting;
  - Bset/B: the mode stays at 120 Hz (restore-crtc=false), then plain kmssink with no modeset.
  - It logs flip timeouts, modeset timing, QoS drop counts and dmesg.
- **Reading the result:**
  - If A stalls and B doesn't, the problem is in the first flips after the modeset: look at the kernel FRL/vblank path, e.g. the vblank
    counter or flip_done after dw-hdmi-qp FRL link training, and whether kmssink should wait for the first flip after SetCrtc.
  - If both stall, it is clock/segment handling in kmssink or basesink at 120 fps.

### DP plan (`board/dp-test.sh`, Dell P2415Q)
Pin D gives 2 lanes HBR2, so 4K30 at most; pin C gives 4 lanes, so 4K60 but no USB3. Cases:
1. Plain DP with jellyfish 4K 30 fps: expect about 30 fps and 0 drops, with 0007 taking the DP CRTC over.
2. force-modesetting on DP: 0005 picks 4K30 or 29.97.
3. 4K60 content on the 30 Hz panel: ~30 fps rendered and ~50% QoS drops, which is inherent.
4. HDMI 4K60 and DP 4K30 at the same time: two sinks, two CRTCs, two overlay planes chosen by 0008, two black primaries.
   Check 0 drops on HDMI and no POST_BUF_EMPTY.
5. Pin C plus force-modesetting 4K60 on DP; afterwards back to pin D, and DP must come back.
6. Not scripted, needs the user: unplug the dongle during case 4. The sink must post an error or keep running, and must not hang
   or crash the kernel.

### GitHub-facing notes
`~/orangepi5-github/tools/export/topics.conf` has a new topic: `usbdp-keep-usb3`, branch `opi5/usbdp-keep-usb3-7.3`, parent dp-smooth,
notes from `workaround-removal`. The branch was rebased to one commit on `opi5/dp-smooth-7.3`; its diff is the same as patches/linux/0270.
The export/publish is not run (`tools/export-from-workspace.sh --commit --branches && ./publish.sh …`). Note: `tests.conf` still
exports `dp-smooth/overlay/usr/local/bin/opi5-play`, and `tests/maxout/maxout.sh` hides the fbcon cursor. Drop both once opi5-play goes.

### Next board slot (~25 min, both displays, no compositor)
1. `sudo install -m644 ~/wr/kms8/libgstkms.so /usr/lib/aarch64-linux-gnu/gstreamer-1.0/`, then clear the registry caches.
2. `sudo ~/wr/gst-kmssink-test.sh k8 hdmi plain60 ms60` (no plane-id).
3. `sudo ~/wr/k120-diag.sh`.
4. `sudo ~/wr/dp-test.sh`.
5. If all pass: fill in 0008's "After", put 0008 into patches/gstreamer, delete overlay/usr/local/bin/opi5-play and the two references above,
   then rebuild gst-plugins-bad (+opi5.2).

## 6. Second board slot (04:52-05:02, no reboot; logs `board/gst-k8-hdmi.txt`, `board/h120.txt`, `board/dp-test.txt`, `board/tcpm-nopartner.txt`)
- **0008, plain `kmssink connector-id=<HDMI>` with no plane-id, cursor blinking:**
  - "plane 47 can't show … using plane 59": NV12 on Esmart0, 2185 frames, **0 dropped, 59.94 fps**.
  - With force-modesetting, plane 35 (primary) → 59, mode set, 0 dropped.
  - No POST_BUF_EMPTY.
  - 0008 is now in `patches/gstreamer` (0001-0008, for +opi5.3).
- **4K120 is solved; it was not a kmssink problem.** HEVC yacht 4K120 (60 s loop), kmssink setting 3840x2160@120 itself, video on Esmart0:
  - **3041 frames, 0 dropped, 120.02 fps**;
  - the same with restore-crtc=false.
  - The earlier "7 s late" came from the H.264 clip: single-core rkvdec decodes 4K H.264 at only 64 fps (600 frames in 9.4 s with fakevideosink), so every frame is late and sync drops them.
  - 4K120 H.264 needs the CCU dual-core decoder (121 fps, per the CCU work). The modeset itself is fine. Without a modeset the mode stays at fbcon's 60 Hz → 60 fps, which is expected.
  - The `rkvdec … Frame processing timed out` lines (826-899 s) were from the CCU slot before mine.
- **DP not tested: the dock's DP AltMode never came up on this boot.** USB3 was fine.
  - tcpm: Discover Identity OK (057e:2003); then Discover SVIDs collided with a partner message, we sent 0xbb0, the retry got Not_Supported (0x690), and discovery ended.
  - No partner alt modes were registered, so DP-1 stayed disconnected.
  - **New bug (tcpm VDM discovery not retried after an AMS collision), not fixed here.**
  - kmssink on the disconnected DP connector fails cleanly at start ("Could not get allowed GstCaps").
  - The HDMI half of the dual-display test passed (0 dropped).
- **Workarounds removed:**
  - `overlay/usr/local/bin/opi5-play` (copy in `opi5-play.removed`);
  - the board's `video=` cmdline;
  - the opi5-play entry in `~/orangepi5-github/tools/export/tests.conf`.
  - Still to remove: the cursor-hiding line in `tests/maxout/maxout.sh`, owned by the maxout agent.
- **Board state:** `libgstkms.so` = 0001-0008 build (`~/wr/kms8`), `libgstv4l2codecs.so` = 0001/0002 build, both over the +opi5.1 debs. +opi5.3 replaces them.

## 7. DP-1 stuck "disconnected" with AUX -110 (2026-10-30 05:20-05:30)
- **Board, this boot:** DP AltMode active, pin D, hpd=1. A forced detect gets `drm_dp_dpcd_probe … 0x00102 AUX -> (ret=-110)` four times, i.e.
  AUX timeouts. The USBDP PHY took the quick path ("USB3 port on" only), so it believes the DP half is up.
- **0275** (dw-dp: re-detect on short pulse when the last detect failed, or on DOWNSTREAM_PORT_STATUS_CHANGED;
  `dw-dp-redetect/`, branch `opi5/dw-dp-redetect-7.3`) is **parked, not for patches/linux.**
  - On USB-C every Attention already re-probes: `drm_connector_oob_hotplug_event()` → `drm_bridge_connector_handle_hpd()` sets the
    status and sends a hotplug event, so the fbdev client and compositors run `detect()` again.
  - The only case 0275 fixes is native DP, where IRQ_HPD comes from the HPD pin and nothing else re-probes, and this board has no native DP.
  - Its "nothing ever detects again" claim is wrong for this stack, so the commit message must not be used as is.
- **0270 and AUX:**
  - Boot −2 ran 0270 with DP-1 connected at 37 s and 440 s, so 0270's DP-half start (raising `CMN_DP_INIT_RSTN` on an initialized PHY)
    does bring AUX up at least in that sequence. The current -110 may be the dock's converter wedged; the user is replugging it.
  - If AUX stays at -110 after a replug with 0270, the prepared alternative is `usbdp/0270-alt-init-dp-half-at-phy-init.diff`, not
    committed. It releases `CMN_DP_INIT_RSTN` inside `rk_udphy_init()` for Type-C ports in USB-only mode too, at the datasheet
    position (before the cmn/lane resets). DP entry/exit then only gates the DP lanes and ROPLL, and INIT_RSTN never changes at runtime.
  - **Test:** boot with 0270, enable `phy_rockchip_usbdp` dyndbg from early boot via modprobe.d `options … dyndbg=+p`, and check AUX.
    Then boot with the alternative. Both DP AUX and the USB3 test must pass.

## 8. 0270 regression (DP AUX -110 from boot) fixed: 0270 v2 (slot 05:26-05:37, 3 boots, logs `board/boot-{no0270,alt,v2}.txt`, `board/usb3-v2.txt`)
- **Root cause:** the DP AUX channel only works if the PHY is initialized after the SBU lines are biased and the AUX polarity is set
  for the cable orientation, which happens on the Type-C orientation event.
  - At boot, the USB3 PHY init (3.1 s) comes before that event. The orientation handler only re-inits when the orientation
    differs from the default (normal), so the first init stays the only one.
  - Before 0270, DP entry did a full re-init and hid this. With 0270's partial DP start, AUX timed out (-110) and DP-1 stayed disconnected.
  - The C→D sequence worked because its init came after the orientation was set. Boot −2 probably had orientation before the first init.
- **Bisect:**
  - no 0270: DP OK;
  - "INIT_RSTN in init" alternative: DP still broken at boot, so INIT_RSTN timing was not the cause;
  - after pin C→D: AUX OK.
- **Fix (0270 v2):** also re-init the PHY when a partner attaches (orientation NONE → normal/reverse; new `attached` flag), not only when the
  orientation changes. This runs before the partner's USB devices enumerate.
- **Result on the board:**
  - DP-1 connected from boot;
  - 0 AUX errors across forced detects after 3× exit/enter, D→C→D and another exit/enter;
  - USB3: 0 disconnects except at pin C, with dd traffic uninterrupted.
- **Files:**
  - `patches/linux/0270` replaced (v2; same subject, extra paragraph); `patches/linux-hold/0270` removed;
  - branch `opi5/usbdp-keep-usb3-7.3` amended;
  - board module `updates/opi5-usbdp-keep-usb3/` = v2 (md5 f4ea67c6…), in the initramfs, with the boot debug option removed;
  - the old drop-in is parked at `/var/tmp/opi5-hold/` on the board.
- **0275 (dw-dp re-detect)** stays parked (§7): this was a PHY problem, and Attention already re-probes.
