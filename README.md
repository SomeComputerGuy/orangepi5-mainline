# Orange Pi 5 (RK3588S) on mainline Linux

Build scripts and patches for an Ubuntu 26.10 image for the Orange Pi 5 on mainline
software: Linux v7.3 + `patches/linux`, U-Boot v2026.10 + `patches/u-boot`, TF-A v2.15.0 +
`patches/tf-a`, and rebuilt FFmpeg, mpv, GStreamer and alsa-ucm-conf packages with the
patches in `patches/<package>`. Sources are fetched from pinned upstream commits; no
binaries are stored here.

## Build

Host: Ubuntu 26.10 x86_64, about 60 GB free. Only `build-image.sh` and `flash-sd.sh` need root.

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

First login: `ubuntu` / `ubuntu` (a password change is forced). Put your own SSH key in
`cidata/user-data` before building, or edit `user-data` on the card's CIDATA partition.

To move to the M.2 SSD and put U-Boot in SPI flash, copy `scripts/opi5-install-ssd` to the
board (booted from SD) and run it with sudo. `scripts/flash-uboot-sd.sh` rewrites only the
boot loader on an SD card. Serial console: UART2 at 115200 baud.

To update the kernel on a running board, install the whole `linux-image` deb with
`dpkg -i`; a new kernel rejects modules from an older build.

## Testing

Tested on an Orange Pi 5 (8 GB) booting from an M.2 SATA SSD with the server image:
boot, SATA, Ethernet, s2idle and deep suspend, HDMI (TMDS up to 4K60, FRL 4K120, HDR),
USB-C DisplayPort, HDMI/DP audio, video decode (rkvdec, Hantro, AV1), H.264/HEVC encode,
JPEG, RGA, IEP, GPU (panthor) and NPU (rocket).

Known problems: rare "No Signal" after HDMI FRL mode changes and rare black DP output after
a modeset (fixes under test); some VP9 conformance streams fail.

Not tested yet: the current desktop image build, NVMe, the headphone jack by ear, cameras
and MIPI DSI panels (`patches/linux-extra`, no hardware attached).

## Licensing

See `LICENSE`. Patches are under the licences of the projects they apply to (Linux
GPL-2.0, U-Boot GPL-2.0+, TF-A BSD-3-Clause).
