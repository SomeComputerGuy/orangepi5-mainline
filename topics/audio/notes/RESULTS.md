# Orange Pi 5 audio: HDMI0, USB-C DP alt-mode, 3.5 mm jack (ES8388)

Branch `opi5/audio-7.3` (worktree `~/orangepi5/work/audio-7.3`) on `opi5/integration-7.3`:

```
22ef6b1e3 arm64: dts: rockchip: Add DP0 audio to RK3588 and Orange Pi 5/5B
e4eadf14d drm/bridge: dw-hdmi-qp: Reprogram audio N/CTS after a link rate change
```

Board kernel: 7.3.0-opi5 #3. The running DTB is the integration DTB, structurally identical
apart from what the bootloader adds, so the new DTB is a clean drop-in.

## Status per output

| Output | Status | Root cause | Fix |
|---|---|---|---|
| HDMI0 (TCL TV, 4K60 TMDS scrambled, 594 MHz) | **Works**: the user heard it (alsasink plughw:0,0 as root, BBB 4K60). Non-root (aruni over SSH): `alsasink device=plughw:hdmi0` and `autoaudiosink` rc 0; audible non-root check pending | Non-root failure ("cannot find card 0") = user not in `audio` (no logind seat over SSH). No `alsasink` on the server (`gstreamer1.0-alsa` missing) | `audio` group (cloud-init); `alsa-utils alsa-ucm-conf gstreamer1.0-alsa` in PKGS; UCM profile for names/priorities |
| HDMI0 4K120 FRL | **Not tested yet** (needs a mode switch on the user's display). Code review: FRL N/CTS helper uses "Recommended N and Expected CTS Values in FRL Mode" (HDMI 2.1 9.2.2); `tmds_char_rate` is set in FRL mode so `audio_prepare` works | Bug found: N/CTS only programmed at `audio_prepare`; a stream open across a modeset (TMDS->FRL, 4K60->4K120) or an FRL rate fallback keeps the old link's ACR | Patch 0002 (dw-hdmi-qp), signed drop-in `modules/updates/opi5-audio/dw-hdmi-qp.ko` |
| USB-C DP alt-mode (DP-1, Dell P2415Q via DP->HDMI dongle) | **Needs reboot to test**. Sink EDID through the dongle advertises Basic Audio, LPCM 2ch 32/44.1/48 kHz | No sound card for dp0 at all | Patch 0001: `dp0_sound` (simple-audio-card SPDIF_TX2 -> `<&dp0 1>`) in rk3588-base.dtsi, enabled with `spdif_tx2` on OPi5/5B. SPDIF per the dw-dp driver's own recommendation (HW inserts IEC60958 channel status; I2S would need userspace PCUV) and the vendor BSP |
| 3.5 mm jack (ES8388) | Path works as non-root (speaker-test, gst alsasink/autoaudiosink, rc 0). **Audible check pending** (nothing plugged in: hp-det GPIO1_D5 reads low = unplugged) | Codec reset values: DAC (`PCM`) -96 dB, `Output 1` -30 dB, and there was no alsactl state / UCM to set them. No alsa-utils on the image, so nothing ever restored a mixer state | UCM `Rockchip/es8388` BootSequence (0 dB DAC/outputs, stereo, no bypass, onboard mic on Line 2), applied on first boot by alsa-utils' udev `alsactl restore` -> init -> UCM `_boot` (verified on the board) |

DT/driver review that needed no change:
- hp-det polarity: `GPIO_ACTIVE_HIGH` matches the Xunlong BSP (`hp-det-gpio = <&gpio1 RK_PD5 GPIO_ACTIVE_HIGH>`).
  The jack creates the `Headphones Jack` control and input device; DAPM disables the `Headphones`
  pin while it is unplugged (so it is silent until something is plugged in, as intended).
- ES8328 driver: no "Left Mixer Left Playback Switch" is by design (the mixer widget powers
  DACCONTROL17/20 bit 7 itself via DAPM).
- Routing LOUT1/ROUT1 -> Headphones, mics on LINPUT1/2 as mainline; LOUT2 unconnected.

## Permissions (task 2)
- Server: `overlay/etc/cloud/cloud.cfg.d/90-opi5.cfg` sets the default user's groups to Ubuntu's
  defaults + `audio video render` (the server user had neither; the desktop 91 file already had
  video/render). Desktop keeps `91-opi5-desktop.cfg` without `audio`: logind tags /dev/snd/* with
  `uaccess` (systemd 70-uaccess.rules) for the active seat, which PipeWire needs; `audio` would
  let background/other users grab the devices.
- On the board: `aruni` added to `audio` (permanent, `usermod -aG audio aruni`).

## Desktop (PipeWire 1.6.8 / WirePlumber 0.5.17, tested on the board with a private instance)
- ACP picks up the UCM profiles. The ES8388 card has profiles `HiFi (Headphones, Mic)` /
  `HiFi (Headphones, Headset)`, Headphones route with jack availability.
- With the jack unplugged ACP marks the HiFi profiles unavailable, WirePlumber sets the card to
  `off` and the sink disappears; WirePlumber also skips nodes with unavailable routes. On
  insertion the profile becomes available and the headphone sink appears. ACP gives every
  platform sink priority.session 1000 (UCM PlaybackPriority does not reach it), so the
  WirePlumber rule below ranks Headphones 1100 > HDMI 1000 > DP 900; the headphone sink then
  wins the default on insertion. **Insertion switch still to be confirmed with a plug-in.**
  Known limitation (stock ACP behaviour, same as the ROCK 5B ES8316 profile):
  the on-board mic is only offered while the profile is up, i.e. with headphones plugged in.
- `overlay-desktop/etc/wireplumber/wireplumber.conf.d/51-opi5-audio.conf` names the cards
  "Headphone Jack", "HDMI", "USB-C DisplayPort" (ACP calls all of them "Built-in Audio"), names
  the sinks "Headphones"/"HDMI"/"USB-C DisplayPort" and sets their priorities. Verified on the
  board: devices "Headphone Jack" + "HDMI", sink "HDMI" (prio 1000, default).
- HDMI/DP have no jack control (simple-card only makes jacks for GPIO/aux devices, not for the
  hdmi-codec DAI), so they always show as available. Possible follow-up: hdmi-codec jack support
  in simple-card (kernel feature, generic).

## Files

### Add to `patches/linux/` (after the 1xxx board patches)
- `_out/audio/patches/0001-arm64-dts-rockchip-Add-DP0-audio-to-RK3588-and-Orang.patch`
- `_out/audio/patches/0002-drm-bridge-dw-hdmi-qp-Reprogram-audio-N-CTS-after-a-.patch`
  (suggested names `1201-...`, `1202-...`)

### Add to `overlay/` (server + desktop)
- `usr/share/alsa/ucm2/Rockchip/es8388/es8388.conf`, `.../HiFi.conf`
- `usr/share/alsa/ucm2/Rockchip/hdmi-dp/hdmi-dp.conf`, `.../HiFi.conf`
- `usr/share/alsa/ucm2/conf.d/simple-card/{rockchip,es8388,hdmi0,hdmi1,dp0,dp1}.conf` (symlinks;
  customize-rootfs.sh's `rsync -rlt` keeps them)
- `etc/cloud/cloud.cfg.d/90-opi5.cfg` (replaces the current one: adds `system_info.default_user.groups`)

### Add to `overlay-desktop/`
- `etc/wireplumber/wireplumber.conf.d/51-opi5-audio.conf`

### scripts
- `_out/audio/image-build-image.sh.patch`: `alsa-utils alsa-ucm-conf gstreamer1.0-alsa` in PKGS
  (desktop gets them through Recommends anyway).

UCM files are BSD-3-Clause like alsa-ucm-conf (upstreamable there as-is); the WirePlumber
fragment is GPL-2.0-only.

### Board artefacts
- DTB: `_out/audio/dtb/rk3588s-orangepi-5-sata.dtb` (md5 c50a1a1a73a3a9e1f26785e35f39dcb9; also
  `-5.dtb`, `5b.dtb`), built `DTC_FLAGS=-@ CHECK_DTBS=y`: clean.
- Module: `_out/audio/modules/updates/opi5-audio/dw-hdmi-qp.ko` (W=1 clean, signed sha512 with
  build/linux's key, vermagic 7.3.0-opi5) -> `/lib/modules/7.3.0-opi5/updates/opi5-audio/`, `depmod -a`.
- `_out/audio/listen-test.sh`: the non-root audible test (voice L/R + sine via alsasink per
  output, then autoaudiosink).

## Board changes made (by this agent)
- Installed `alsa-utils alsa-ucm-conf` (and the coordinator `gstreamer1.0-alsa`), and
  `pipewire pipewire-bin wireplumber` for the desktop test (socket-activated user units, not
  started by anything; my test instance ran from /tmp/audio-pw with its own runtime dir).
  `pipewire-alsa` was installed and removed again (it redirects ALSA `default` to PipeWire).
- `aruni` in `audio`. ES8388 mixer set to the UCM boot values (not stored with alsactl yet).
- Test UCM tree in `/tmp/audio-ucm2` (system `/usr/share/alsa/ucm2` untouched).

## Checks
- checkpatch --strict: both patches clean except the expected missing Signed-off-by.
- dtbs_check (`CHECK_DTBS=y`) for rk3588s-orangepi-5{,-sata,b}: no warnings.
- `alsaucm -c hw:0|hw:1 dump text` with the new tree: profiles parse, devices as intended.

## Hardware results after the reboot (DTB c50a1a1a + dw-hdmi-qp.ko srcversion FC79F137...)
Cards (by name; numbering changed): hdmi0, dp0, rockchipes8388. Verified by signal, kprobes on
`dw_hdmi_qp_set_sample_rate`/`drm_hdmi_acr_get_{frl_,}n_cts`/`dw_dp_audio_prepare` plus dyndbg:
- **DP0**: speaker-test as aruni on `plughw:dp0`: dw-dp "audio prepare with 2 channels using
  DAI=1" (SPDIF), audio SDP sent (prepare rc 0), hw_ptr +48k frames/s, no xrun, rc 0.
- **HDMI**: after the reboot 4K60 runs **10-bit over FRL 4x10G** (742.5 MHz), 4K120 8-bit FRL
  4x10G (1188 MHz), 1080p60 TMDS (185.6 MHz). Stream opened at 4K60 FRL (FRL N/CTS, 10 Gbps),
  then modesets while it played: 4K60->4K120->4K60 and 4K60 FRL->1080p TMDS->4K60 FRL. Each
  atomic_enable reprogrammed ACR via patch 0002 (`acr_tmds tmds=185625000` at 1080p,
  `acr_frl lane_gbps=10` back at 4K). The PCM stayed RUNNING with hw_ptr advancing at 48 kHz,
  no xruns. Without 0002, the 1080p TMDS link would keep the FRL N/CTS.
- Not checkable here: N/CTS register readback (no regmap reads allowed) and sink-side audio lock.
  Audible checks pending: `/tmp/audio-t/seq.sh` (HDMI 440 Hz 3 s, pause, DP 880 Hz 3 s,
  prints times) and headphones via `listen-test.sh hp`.
- Fixed `listen-test.sh` (speaker-test has no `-q`).

## 2026-10-30: config moved to its upstream homes (image = mainline Ubuntu + patches)

- **UCM** (was overlay/usr/share/{alsa/,}ucm2, files no package owned): now
  `patches/alsa-ucm-conf/0001-ucm2-Rockchip-Add-ES8388-and-RK3588-HDMI-DP-configur.patch`
  (upstream layout: `ucm2/Rockchip/es8388/`, `ucm2/Rockchip/rk3588-hdmi-dp/` (renamed from
  `hdmi-dp`), `ucm2/conf.d/simple-card/{rockchip,es8388,hdmi0,hdmi1,dp0}.conf`; dp1 dropped:
  no DT defines a dp1 sound card). Content unchanged apart from the SPDX lines (upstream files
  carry none) and the directory rename. Shipped as Ubuntu's own package rebuilt with the patch:
  `scripts/build-media-debs.sh alsa-ucm-conf` -> `alsa-ucm-conf_1.2.16.1-1ubuntu1+opi5.1_all.deb`.
  The `/usr/share/ucm2` copy was a duplicate (alsa-lib reads `/usr/share/alsa/ucm2`).
- **WirePlumber fragment dropped** (stock Ubuntu would not ship a board rule in /etc):
  - Names: ACP's card description is "Built-in Audio" for every platform card (udev
    SOUND_FORM_FACTOR=internal, `acp/compat.c`), but each output's route/port carries the UCM
    device Comment, so GNOME lists "Headphones", "HDMI", "DisplayPort" - Built-in Audio.
  - Priority: WirePlumber 0.5.17 gives every UCM HiFi node priority.session 1000
    (`monitors/alsa.lua`), and `node-utils.compare_nodes` ranks route priority (where UCM
    PlaybackPriority ends up) only *within* one device; across cards the tie goes to the lower
    device serial (probe order). So no UCM value can rank the jack over HDMI across cards; that
    would be a WirePlumber policy change (compare route priority across devices for internal
    cards), not a small fix, and isn't written. Stock behaviour, as on the Rock 5B (ES8316 +
    HDMI): the first card is the default; once the user picks an output in Settings,
    WirePlumber remembers it (state-default-nodes).
