# Orange Pi 5 (RK3588S) on mainline Linux

Build scripts and patches for an Ubuntu 26.10 image for the Orange Pi 5: stock Ubuntu plus
a mainline kernel and boot firmware with patches that are meant to go upstream.

| Part | Base | Patches |
|---|---|---|
| Kernel (7.3.0+opi5.17) | Linux v7.3 | `patches/linux` |
| Boot loader | U-Boot v2026.10 | `patches/u-boot` |
| Firmware | TF-A v2.15.0 | `patches/tf-a` |
| Media packages | Ubuntu's FFmpeg, mpv, GStreamer, alsa-ucm-conf | `patches/<package>` |

Sources are fetched from pinned upstream commits; no binaries are stored here.

## Build

Host: Ubuntu 26.10 x86_64, about 60 GB free. `install-deps.sh`, `build-image.sh` and the
flash scripts use sudo; the rest runs as a normal user.

```sh
./install-deps.sh                         # host packages
scripts/fetch-sources.sh                  # pinned sources into src/
scripts/build-kernel.sh                   # kernel debs (OPI5_EXTRA=1 adds patches/linux-extra)
scripts/build-uboot.sh                    # TF-A + U-Boot
scripts/build-media-debs.sh               # FFmpeg, mpv, GStreamer, alsa-ucm-conf rebuilds
scripts/build-va-driver.sh                # VA-API driver (desktop image only)
scripts/build-image.sh                    # server image
scripts/build-image.sh --variant desktop  # or the GNOME desktop image
scripts/flash-sd.sh /dev/sdX [desktop]    # write it to an SD card
```

Output goes to `out/`. Optional settings (source dir, build identity) go in `local.env`,
see `local.env.example`.

First login: `ubuntu` / `ubuntu` (a password change is forced). To use your own SSH key,
copy `cidata/user-data.example` to `cidata/user-data` and edit it before building, or edit
`user-data` on the card's CIDATA partition.

To move to the M.2 SSD and put U-Boot in SPI flash, copy `scripts/opi5-install-ssd` and
`out/u-boot-rockchip-spi.bin` to the board (booted from SD) and run the script with sudo.
`scripts/flash-uboot-sd.sh` rewrites only the boot loader on an SD card. Serial console:
UART2 at 115200 baud.

To update the kernel on a running board, install the whole `linux-image` deb with
`dpkg -i`; a new kernel rejects modules from an older build.

## What works here that mainline does not have yet

Everything in this list runs on the board with this image. "Not in mainline" was checked on
2026-11-12 against v7.3, Linus' tree and linux-next, and compared with Armbian edge (its
rockchip64 7.3 and 7.4 patches) and Collabora's RK3588 status table. A good part of it is
other people's work that is posted but not merged; the patches keep their authors.

Display
- **HDMI 2.1 FRL, up to 4K120.** Mainline stops at TMDS (4K60). The FRL series is
  Collabora's and not posted yet; Armbian edge does not carry it. Limited to 10 Gbit/s per
  lane, so 4K120 runs at 8 bpc.
- **USB-C DisplayPort alt mode, up to 4K60, with hotplug.** Mainline has the DP controller
  but not the alt-mode parts (under review) or the Orange Pi 5 devicetree for it. Armbian
  edge has its own devicetree patch for this board.
- **HDR10 over DisplayPort** (static metadata, BT.2020) and BT.2020 colorimetry on HDMI,
  also with one output in HDR and the other in SDR. The DP HDR series is posted, not merged.

Video decode
- **One stream on both decoder cores** (H.264, HEVC, VP9): 4K HEVC goes from 130 to
  227 fps, 4K H.264 from 67 to 121 fps. Mainline and Armbian edge use one core.
- **VP9 on the main decoder, up to 8K**, bit-exact. Posted, not merged; Armbian edge
  carries the same series.
- **JPEG decode** on the hardware JPEG decoder. Mainline has no driver; another driver for
  the same block is under review.
- **MPEG-1, AVS and AVS+ decode.** The vendor kernel does these; mainline has no interface
  for them.
- **FFmpeg and mpv hardware decode** through the V4L2 Request API. The FFmpeg pull request
  is still open, so distribution FFmpeg cannot use these decoders.

Video encode
- **H.264 and HEVC encode** on the two main encoder cores (up to 8192x4320), **H.264
  encode** on the 1080p encoder, usable from GStreamer (`v4l2slh264enc`, `v4l2slh265enc`).
  Mainline has no driver and no stateless encoder interface; Armbian edge has none either.
- **JPEG encode on all four JPEG cores**: four streams run 3.4 times as fast as one.
  Mainline uses one core.

Other
- **10-bit video (NV15, P010) through the RGA3 scaler/converter.**
- **NPU frequency scaling**, 200 MHz to 1 GHz, with thermal throttling. Mainline keeps the
  NPU at 200 MHz; the series is posted.
- **M.2 SATA SSD as the boot disk**: a devicetree variant plus U-Boot fixes. Not in
  mainline; Armbian has an equivalent.

## Work in progress

Not finished. Listed so you know what is coming; no dates.

- HDMI VRR and ALLM (game mode): in the image; underruns while page-flipping at some
  high refresh rates. In testing.
- Two full-screen layers at 4K120: more than the display controller's memory port can
  fetch, so the picture underruns. A check that refuses such setups instead is in testing.
- HDMI FRL: fix for the rare "No Signal" after a mode change in testing. 12 Gbit/s per
  lane (4K120 at 10 bpc, 4K144) is being investigated.
- DisplayPort: fix for the rare black picture after a mode change in testing.
- HDR: correct colours for BT.601 and BT.2020 video planes, SDR-to-HDR conversion and
  colour matrix in the display controller. In testing, not passing yet.
- Display writeback and HDMI interlaced modes: written, board tests pending.
- IEP2 deinterlacer: the driver is in the image and passes v4l2-compliance, but neither
  GStreamer nor FFmpeg can use it yet. Being prepared for posting upstream.
- MPEG-4 Part 2 / H.263 decode: the kernel driver is in the image; the FFmpeg fixes and
  GStreamer elements it needs have passed on the board and come with the next media
  package update.
- AVS2 decode: in the image and working for the common cases; field coding, background
  pictures and some bit-depth cases are untested.
- H.264 MVC (3D) decode: the kernel decodes both views; FFmpeg and GStreamer only show
  the base view.
- VC-1 decode: in development, not decoding correctly yet.
- VP9: one group of conformance streams (very small frame sizes) still fails.
- Encoders: an FFmpeg encoder is planned; today only GStreamer can use them.
- Parity with the vendor's MPP stack: still missing are compressed (AFBC) decoder output,
  VP8 encode and multiview HEVC. Planned.
- Second IOMMU (MMU600_PHP) for SATA, USB 3 and Ethernet: now in the kernel patches. SATA,
  USB 3, Ethernet and deep suspend pass on the board; data transfer over the USB-C port is
  not tested yet. Upstream posting waits for the SMMUv3 power-management series it builds on.
- Crypto engine: driver ported, self-tests pass, one cross-check fails. In testing.
- OP-TEE with a firmware TPM and secure storage: on the board, OP-TEE's test suite, the
  TPM, sealing and a TPM-unlocked LUKS volume pass. The TPM was missing after one reboot
  because Ubuntu's tee-supplicant service can start before the OP-TEE driver loads; a fix
  (upstream's device-ordered service) is in testing. Test firmware only, booted from SD; no
  fuses or keys are burned.
- Verified and measured boot without burning fuses, and an encrypted root unlocked by
  TPM + PIN: works in emulation, board test pending.
- Upstreaming: about 30 series are posted and in review; the rest follow as they pass
  on the board.

## Testing

Tested on an Orange Pi 5 (8 GB) booting from an M.2 SATA SSD:
boot, SATA, Ethernet, USB 2 and 3, s2idle and deep suspend, HDMI (TMDS up to 4K60, FRL up
to 4K120, HDR, CEC, stereo audio), USB-C DisplayPort (up to 4K60, HDR), video decode
(H.264, HEVC, VP9, AV1, VP8, MPEG-2 and the formats listed above), H.264/HEVC/JPEG encode,
JPEG decode, RGA, GPU (panthor: OpenGL ES 3.1, Vulkan 1.4) and NPU (rocket).

Known problems: rare "No Signal" after HDMI FRL mode changes; rare black DP output after a
mode change; underruns at 1366x768 on both outputs; some VP9 conformance streams fail; an
SD card inserted while the board is running is not seen until reboot.

Not tested yet: the SD images built from the current kernel (the last boot test was on an
older one), NVMe and PCIe suspend, 8K output (no 8K display), DisplayPort audio and the
headphone jack by ear, USB-C device mode, cameras and MIPI DSI panels
(`patches/linux-extra`, no hardware attached).

## Licensing

See `LICENSE`. Patches are under the licences of the projects they apply to (Linux
GPL-2.0, U-Boot GPL-2.0+, TF-A BSD-3-Clause).
