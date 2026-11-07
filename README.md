# Orange Pi 5 (RK3588S) on mainline Linux

Scripts, patches and notes for running the Orange Pi 5 on **mainline** software
only: Linux 7.3, U-Boot v2026.10 and open-source TF-A v2.15.0, with Ubuntu 26.10
server and desktop images. The goal is to make the board feature-complete on mainline, video
first, and to upstream the fixes and drivers this needs.

This repository has two purposes:

1. **Use and reproduce**: build the image, kernel and boot firmware yourself
   from pinned upstream sources and the patches here, and deploy them to a board.
2. **Review upstream work**: every kernel topic has its own patch series under
   [`topics/`](topics/), split into our own patches, other people's series we
   carry, and local-only patches, with test results and draft cover letters.
   [`STATUS.md`](STATUS.md) lists every topic and where it stands.

**Nothing in here has been sent upstream yet.** The series are prepared (see
"Upstream status" below), not posted.

## Current versions

| Component | Version | Where |
|---|---|---|
| Kernel | **7.3.0+opi5.15** = Linux v7.3 + the 479 patches in `patches/linux`, regression-tested on the board. Versions are `<mainline>+opi5.<rev>`. The next kernel, 7.3.0+opi5.16, is a release candidate under test, not released | `scripts/build-kernel.sh`; fork branch `opi5/image` (tag `image-7.3.0+opi5.15`) |
| U-Boot | v2026.10 + `patches/u-boot` (three carried fixes and the board `-u-boot.dtsi` fragments) | `scripts/build-uboot.sh` |
| TF-A | v2.15.0 + `patches/tf-a` (PHP CRU clock-gate save/restore), BL31 built from source | `scripts/build-uboot.sh` |
| Image | Ubuntu 26.10 arm64, server and desktop variants | `scripts/build-image.sh` |

## What works

Tested on an Orange Pi 5 (RK3588S, 8 GB) booting from an M.2 SATA SSD, with the current image
kernel unless a row says otherwise. The numbers come from the notes under `topics/*/notes/`.
The full display and video support chart (every resolution, refresh rate and colour format on
HDMI and DP: verified / not tested / driver limit / hardware limit) is
[`docs/video-support-chart.pdf`](docs/video-support-chart.pdf).

### Works

| Area | State |
|---|---|
| Boot | Mainline U-Boot from SPI flash or SD, TF-A BL31 from source. Big cores clocked up before Linux (boot time from 100 s down to normal). The M.2 slot auto-detects NVMe or SATA and picks the matching DTB. The boot check finds every expected device |
| Storage | M.2 SATA root (`rk3588s-orangepi-5-sata` DTB). Reboots take under 1 s (the SATA-root reboot hang is fixed) |
| Video decode | rkvdec (VDPU381) H.264/HEVC/VP9 on both cores, including **one stream on both cores through the CCU** (HEVC 4K 130 -> 227 fps, H.264 4K 67 -> 121 fps, bit-exact). Hantro G1 (H.264, VP8, MPEG-2) and AV1. Fluster: HEVC 146/147, AVC 129/135, FR-EXT 65/69, VP9 230/305. All decoders bit-exact in the codec sweep. Timeout recovery (core reset, IOMMU) proven on a KASAN kernel |
| Video encode | VEPU580 H.264 and HEVC stateless encoder driver (38-42 dB at QP 26, 4K at 39-54 fps), Hantro H1 H.264, VEPU121 JPEG on 4 cores. GStreamer `v4l2slh264enc` and `v4l2slh265enc` (`patches/gstreamer`): hardware and software decode of the output are bit-identical, 4K60 HEVC to H.264/H.265 transcode with zero copies, about 250 fps per stream at 1080p and 68 fps at 4K |
| JPEG decode | VDPU720 (rkjpegd) driver |
| Deinterlace | IEP2 driver (v4l2-compliance 57/57) |
| 2D (RGA) | RGA2 and RGA3: copies bit-exact, v4l2-compliance 48/48 on both |
| GPU / NPU | panthor (Mali-G610) at 995-1024 MHz under load, 200 runtime suspend/resume jobs without failure; rocket (NPU) at 1 GHz with DVFS and thermal cooling, Teflon inference matches the CPU |
| Display | HDMI0 up to 4K60 TMDS, HDMI 2.1 FRL 4K120 and 4K60 10 bpc, exact pixel clocks. In the colour-format matrix every HDMI mode the driver accepts shows correctly (346 of 346) and every native DP case is good (370 of 370). HDR (SDR/PQ switching with the right infoframes) on the HDMI TV and the DP monitor, also mixed HDR/SDR on two heads. USB-C DisplayPort alt mode with a native DP cable or through a dock, including DP-to-HDMI protocol-converter docks (4K30) and pin-assignment re-train. Dual display with 0 VOP2 underflows |
| Audio | HDMI audio, also across FRL/TMDS mode changes |
| USB | Type-A USB3 port: a device present at boot is moved from 480M to SuperSpeed. USB-C role switching: the USB side of a USB-C dock (USB 2.0 and USB 3) enumerates after boot and after every s2idle and deep-suspend resume. See "Hardware limitation" below |
| Network | Gigabit Ethernet at line rate (940 Mbit/s, 0 errors) |
| Suspend | s2idle and deep suspend (mem) with an RTC wake-up: 15/15 and 10/10 cycles in the last regression run (deep resume 3.1 s, 0 warnings). After every resume USB, DP, HDMI, SATA and Ethernet are checked |
| Media packages | FFmpeg/mpv V4L2 Request hwaccels, GStreamer v4l2codecs and kmssink fixes (rebuilt Ubuntu packages, in both images); VA-API driver ([libva-v4l2_request fork](https://github.com/SomeComputerGuy/libva-v4l2_request)) in the desktop image |

### Known problems

| Area | State |
|---|---|
| HDMI 2.1 FRL | After a few percent of FRL mode changes the TV shows "No Signal" (about 3-5%). A fix is under test |
| DP | Rarely (about 0.6% of modesets) the DP monitor stays black with no kernel error. A fix is under test |
| HDMI modes | The driver refuses some mode/format combinations (64 of 410 in the colour matrix). FRL is capped at 10 Gbit/s per lane, so 4K100-165 at 10 bpc is not available yet |
| H.264 encode | Constant bitrate undershoots by 5-10% (fixed in 7.3.0+opi5.16, see below) |
| VP9 decode | Some conformance streams still fail (fluster 230/305), and FFmpeg loses its references when a VP9 stream changes resolution between inter frames; fixes are being worked on |
| CPU frequency | The top "2400 MHz" operating point actually runs at about 2.14 GHz (under discussion) |

### Partly done or not tested

| Area | State |
|---|---|
| Desktop image | Builds with the current kernel and media packages; this build has not been booted yet. An earlier desktop image booted to the GNOME greeter on HDMI 4K60 10 bpc and on DP. Browser hardware decode through the VA driver: Chrome passes the board decode checks; Firefox needs the changes in `patches/firefox`, which Mozilla's builds do not have, and still drops some frames at 4K60 AV1 |
| DP audio | The dp0 card exists and streams; checked at signal level only (no speakers on the DP monitor) |
| Headphone / microphone jack (ES8388) | UCM defaults applied, path opens, not checked by ear |
| Camera | rkisp2 series plus Orange Pi 5 sensor overlays (`patches/linux-extra`): probing works, no camera module attached yet |
| MIPI DSI | ili9881c panel driver and LCD overlays (`patches/linux-extra`): no panel attached |
| DP HBR3 4-lane, CEC over DP | Need a USB-C to HDMI 2.1 adapter or a CEC-capable adapter |
| NVMe in the M.2 slot, USB boot | The test board runs from SATA; the PCIe system-PM patches are carried but exercised only by the build |
| Long deep-suspend soak | Short cycle runs pass; an hours-long soak is not done |

### Hardware limitations

| Area | State |
|---|---|
| USB 2.0 Type-A port next to the USB3 port, and the USB-C port | On the Orange Pi 5 v1.2 the USB 2.0 Type-A port beside the USB3 port is wired in parallel to the USB 2.0 data lines of the USB-C port, with no switch. Only one of the two can use USB 2.0 at a time. The kernel makes the controller a host by default when nothing is attached to the USB-C port, so the Type-A port works then; a USB-C partner still gets the role it negotiates |
| DP | The RK3588 DP controller has no DSC and no MST, and one video port drives at most 4096x2304 at 60 Hz, so 4K120 and DSC over DP are not possible |

## Not in the image kernel yet

These are kernel feature branches on top of the current image kernel. None is in `patches/linux`
or in the stock image yet. Each is a topic under [`topics/`](topics/) and a branch `opi5/<topic>`
in the [kernel fork](https://github.com/SomeComputerGuy/linux). Most of them are in the
**7.3.0+opi5.16 release candidate**, which is under test and becomes the image kernel once it
passes.

| Topic | What it is | State |
|---|---|---|
| `dp-ycbcr` | DP YCbCr 4:4:4 / 4:2:2 / 4:2:0 output as requested by the connector colour format | Works (370 camera-judged DP cases). In 7.3.0+opi5.16 |
| `vop2-splice` | Modes wider than 4096 pixels by splicing video ports 0 and 1, plus four small VOP2 fixes it needs | 4K60, 4096-wide and 1080p spliced modes good on HDMI and DP, SDR/HDR10 switching good. Wider than 4096 not tested (no such display). Open: an intermittent underrun on video port 2 after modesets. In 7.3.0+opi5.16 |
| `mpeg1` | MPEG-1 decoding on the VPU121 (hantro), with the `V4L2_PIX_FMT_MPEG1_SLICE` format | Works (all hardware-decodable conformance vectors and a 1080p30 stream). D-pictures are not supported. In 7.3.0+opi5.16 |
| `avs2` | AVS2 decoding on rkvdec | Bit-exact on 17 of 17 test streams; no userspace hwaccel yet. In 7.3.0+opi5.16 |
| `avs-plus` | AVS and AVS+ decoding on the AVS+ decoder (hantro) | Bit-exact on the test streams, corrupt streams recover. In 7.3.0+opi5.16 |
| `h264-mvc` | H.264 MVC (two-view stereo) decoding on rkvdec | 15 of 15 two-view streams bit-exact; only our own test client drives it. In 7.3.0+opi5.16 |
| `iep2-std-deint`, `iep2-first-ts` | IEP2 uses the standard deinterlacing control, correct first-field timestamps; carries a drm/gem AFBC framebuffer size check | Works (72 of 72 cases identical, v4l2-compliance 57/57). In 7.3.0+opi5.16 |
| `rga3-10bit` | RGA3 NV15/P010 input, rotation and flip; RGA descriptor and buffer-size fixes | Works (10-bit HEVC to RGB at 57-58 dB). In 7.3.0+opi5.16 |
| `rga-fixes` | RGA2 flip direction, RGA3 crop, larger strides, NV20 | Works. The RGA2 flip fix is in 7.3.0+opi5.16, the rest goes into the next kernel |
| `rkvenc-h264-rc`, `h1-h264-rc` | H.264 constant-bitrate control for VEPU580 and Hantro H1, SPS/PPS `nal_ref_idc` fix | Bitrate error within about 2.5% (was up to -9.4%), better PSNR. In 7.3.0+opi5.16 |
| `mpeg4` | MPEG-4 Part 2, H.263 and Sorenson Spark decoding on the VPU121 | Partly: 93 of 95 board checks pass on the next revision; two failures being fixed |
| `venc-8k` | VEPU580 encoding wider than 4096 pixels | H.264 works up to 16384x2048. H.265 is broken in the published version; the fix passed the board test and is not published yet |
| `hevc-enc-rc` | HEVC constant-bitrate control on VEPU580 | Not good enough yet: still fails 2 board checks |
| `dp-irq-retrain` | DP link retrain on IRQ_HPD link loss | Tested: does not fix the rare DP black, so it is not taken |

Passed on the board but not published as topics yet: AVS1 decoding on the VPU121 decoder,
macroblock-level rate control for the H1 encoder, and two fixes for browser hardware decode
(m2m stream-off, RGA3 strides). They go into the kernel after 7.3.0+opi5.16.

Userspace: the GStreamer encoders and the shared FFmpeg V4L2 Request series (AVS2, MPEG-1 and
others) are in `patches/gstreamer` and `patches/ffmpeg` and run on the board. FFmpeg and GStreamer
support for the new MPEG-4, AVS, AVS+ and MVC decoders, IEP2 in GStreamer/FFmpeg and an FFmpeg
stateless encoder are not written yet.

## Upstream status

Nothing has been posted, pushed or mailed. Series are prepared on linux-next (or
`torvalds/master` for pure fixes) with cover letters and per-series notes. Only patches that are
proven on hardware will be sent. Some go out as replies to other people's unmerged series (rkvdec
multi-core and VP9, the H.264 stateless encode uAPI, dw-dp, the USBDP rework, HDMI 2.1 FRL);
patches that duplicate work already upstream or under review are dropped.

The per-patch hardware test map is exported as
[`docs/workspace/UPSTREAM-TESTMAP.md`](docs/workspace/UPSTREAM-TESTMAP.md); the series themselves
(cover letters, send lists) stay in the workspace until they are sent. Each topic's README and
`STATUS.md` give the next step per topic.

## Layout

```
README.md, STATUS.md      this file; per-topic status table (generated)
LICENSE, LICENSES/        licensing per directory
PUBLISH.md, publish.sh    how this repository and the kernel branches get to GitHub
install-deps.sh           host packages (Ubuntu 26.10 x86_64 build host)
local.env.example         site settings (board address, network ports, identity)
scripts/                  build, flash, board-update and lab-network scripts
  opi5.config             kernel config fragment on top of Ubuntu's arm64 config
patches/linux/            image kernel: applied in order on v7.3 by build-kernel.sh (479 patches)
patches/linux-extra/      optional, untested-on-hardware extras (OPI5_EXTRA=1 build-kernel.sh)
patches/linux-hold/       patches taken out of the image kernel (currently none; see its README)
patches/u-boot/           U-Boot patches 0001-0003 and -u-boot.dtsi fragments used by build-uboot.sh
patches/tf-a/             TF-A patches applied on v2.15.0 by build-uboot.sh
patches/upstream/u-boot/  two U-Boot patches prepared for the U-Boot list
patches/{ffmpeg,mpv,gstreamer,gst-plugins-good,alsa-ucm-conf}/  package patches (build-media-debs.sh)
patches/{chromium,firefox,weston,jellyfin-desktop}/  patches for packages the image does not rebuild
overlay/, cidata/         root-filesystem overlay and cloud-init seed for the image
overlay-desktop/          extra overlay for the desktop image
topics/<topic>/           one kernel topic (see "Kernel topics" below)
tests/<test>/             board/host test scripts with a README each (see docs/TESTING.md)
docs/                     SOURCES.md (third-party material and URLs), results, workspace notes
tools/                    export, secret scan, kernel-branch recreation
```

## Build it yourself

Everything the images need is in this repository or fetched from pinned upstream sources
by the scripts. No binaries are downloaded from us.

**Host:** Ubuntu 26.10 x86_64 (other recent Debian/Ubuntu releases may work, but the media
packages are rebuilt from Ubuntu 26.10's sources, so the host's `ubuntu-keyring` must know
that release). You need about **60 GB** of free disk: `build/linux` is about 35 GB, `src/` 7 GB
and `out/` a few GB. On 20 cores, budget about **1 hour** for the kernel, **a few minutes** for
U-Boot, and **several hours** for the media packages. These are native arm64 builds under
qemu-user, and FFmpeg takes most of the time. Only `build-image.sh` and `flash-sd.sh` need
root. Everything else runs as your normal user.

```sh
git clone https://github.com/SomeComputerGuy/orangepi5-mainline.git && cd orangepi5-mainline
./install-deps.sh                 # 1. host packages (sudo apt-get)
cp local.env.example local.env    #    optional: board address, network ports, identity
scripts/fetch-sources.sh          # 2. pinned sources into src/
scripts/build-kernel.sh           # 3. kernel debs
scripts/build-uboot.sh            # 4. TF-A + U-Boot
scripts/build-media-debs.sh       # 5. FFmpeg, mpv, GStreamer rebuilds (rootless)
scripts/build-va-driver.sh        # 6. VA-API driver deb (rootless; desktop image only)
scripts/build-image.sh                    # 7a. server image (asks for sudo)
scripts/build-image.sh --variant desktop  # 7b. or the GNOME desktop image
scripts/flash-sd.sh /dev/sdX [desktop]    # 8. write it to an SD card (sudo, asks first)
```

| Step | Output (in `out/` unless noted) |
|---|---|
| 2. `fetch-sources.sh` | `src/linux` (v7.3 `c03c1a14`), `src/u-boot` (v2026.10), `src/tf-a` (v2.15.0), `src/rkbin` (pinned commit), `src/libva-v4l2-request` (pinned commit). Prints `<name>: <commit> OK` for each |
| 3. `build-kernel.sh` | `debs/linux-image-7.3.0-opi5_<version>_arm64.deb`, `linux-headers-…`, `linux-libc-dev_…` |
| 4. `build-uboot.sh` | `u-boot-rockchip.bin` (SD/eMMC, sector 64) and `u-boot-rockchip-spi.bin` (SPI NOR) |
| 5. `build-media-debs.sh` | `debs-media/`: `ffmpeg`/`libav*` `7:8.1.2-2ubuntu2+opi5.2`, `mpv` `0.41.0-2ubuntu5+opi5.2`, `gstreamer1.0-plugins-bad` and friends `1.28.6-1ubuntu1+opi5.4`, `gst-plugins-good` `1.28.7-1build1+opi5.1`, `alsa-ucm-conf` `1.2.16.1-1ubuntu1+opi5.1`, plus a signed `Packages` index. Logs: `build/media/<source>.*/build.log` |
| 6. `build-va-driver.sh` | `debs-media/v4l2-request-va-driver_1.2+opi5.2-1_arm64.deb` |
| 7. `build-image.sh` | `ubuntu-26.10-<variant>-orangepi5.img`, `.img.xz` and `.img.xz.sha256` |

What each step does:

- **`fetch-sources.sh`** makes shallow clones at pinned tags or commits into `src/` and checks
  the commit IDs. `build-*.sh` also run it for any tree that is missing. Every URL and version
  is listed in [`docs/SOURCES.md`](docs/SOURCES.md). No third-party code or binary is stored
  in this repository. The DDR init blob comes from rkbin at build time, and Rockchip's rkbin
  licence applies to it.
- **`build-kernel.sh`** resets `src/linux` to v7.3 and applies `patches/linux/*.patch` in
  order (with `OPI5_EXTRA=1`, also `patches/linux-extra/` and `scripts/opi5-extra.config`:
  hardware support not yet tested on a board). It re-applies them only when the patch set
  changes, so rebuilds stay incremental. The config is Ubuntu's generic arm64 config
  (downloaded from ports.ubuntu.com) plus `scripts/opi5.config`. It builds signed modules
  (the kernel enforces lockdown) and cross-builds `linux-headers` for on-board DKMS through a
  private arm64 sysroot. The module-signing key is generated in `build/linux/certs/` and must
  stay private. It is never part of this repository or of any package. The same tree is
  branch `opi5/image` in the [kernel fork](https://github.com/SomeComputerGuy/linux), and every
  image kernel has a tag `image-<package version>` (the current one is `image-7.3.0+opi5.15`).
- **`build-uboot.sh`** builds TF-A BL31 from source (`BL31_SRC=rkbin` uses Rockchip's binary
  instead), resetting `src/tf-a` to v2.15.0 and applying `patches/tf-a/*.patch`. It patches
  a copy of the rkbin DDR blob to print at 115200 baud, resets `src/u-boot` to v2026.10, applies
  `patches/u-boot/*.patch` (three carried fixes: the RK3588 combo-PHY SATA register offset, AHCI
  READ CAPACITY, PCIe link-up timeout on cold boot), adds the board fragments from
  `patches/u-boot/` (M.2 SATA/NVMe auto-detect, `M2_MODE=auto|sata|nvme`, and big-core clocks)
  and builds `orangepi-5-rk3588s_defconfig` with the console at 115200.
- **`build-media-debs.sh`** rebuilds Ubuntu 26.10 source packages in a rootless arm64
  chroot (`mmdebstrap --mode=unshare` + qemu-user). It runs `apt-get source` at the exact
  versions in the script and adds the patches from `patches/<package>`.
  FFmpeg gets the V4L2 Request API hwaccels (H.264, HEVC, VP8, VP9, AV1, MPEG-2). mpv gets
  the v4l2request hwdec. gst-plugins-bad gets v4l2codecs per-device caps and kmssink fixes,
  gst-plugins-good a v4l2transform colorimetry fix and a souphttpsrc fix, alsa-ucm-conf the
  ES8388 and HDMI/DP profiles. Run with package-name arguments to build a subset. mpv needs the
  FFmpeg build first. `MEDIA_JOBS` sets the parallelism (default 6).
  The versions are pinned in the script. If Ubuntu has published a newer version of one of
  these packages and the archive no longer carries the pinned one, `apt-get source` fails. In
  that case, bump `VERSION` in the script to the archive's version. The patches usually still
  apply.
- **`build-va-driver.sh`** builds the VA-API driver for the V4L2 stateless decoders, so
  Firefox and Chrome can decode with the hardware. It uses
  [SomeComputerGuy/libva-v4l2_request](https://github.com/SomeComputerGuy/libva-v4l2_request),
  branch `opi5/main`, pinned at commit `e912dc47684e`. That is megi's
  [libva-v4l2_request](https://xff.cz/git/libva-v4l2_request) `cac6ece` plus three of
  sofus13's HEVC fixes and our RK3588 work, under GPL-3.0-or-later. The build uses the
  source's own `debian/` packaging, in the same kind of rootless chroot as the media packages.
- **`build-image.sh`** runs mmdebstrap for Ubuntu 26.10 arm64. It adds `out/debs-media` as a
  local, signed apt repository (pinned above the archive), applies `overlay/` (and, for the
  desktop, `overlay-desktop/` and `scripts/customize-desktop.sh`), installs the kernel packages
  and writes a GPT image. The image has U-Boot at sector 64, a `CIDATA` FAT partition holding
  the cloud-init seed, and the root file system, which grows on first boot. Both variants need
  the FFmpeg and GStreamer rebuilds. The desktop variant also needs mpv and the VA driver.
  It installs `ubuntu-desktop-minimal`, Firefox from Mozilla's apt repository, Google
  Chrome from Google's, and Jellyfin MPV Shim from the wheels pinned in
  `scripts/jellyfin-mpv-shim.wheels`. `--rootfs-tar FILE` builds only the root filesystem,
  rootless, to check that the package set resolves. `--reuse-rootfs` reuses the previous
  run's tree.

**Verified so far:** the kernel, U-Boot and both image variants build from these scripts; the
server image, the current kernel packages and U-Boot (in SPI flash) run on the test board. The
current desktop build has not been booted yet; an earlier one booted to the GNOME greeter on both
outputs. The VA driver, the FFmpeg V4L2 Request patches and the GStreamer patches are used on the
board (the display tests rely on the kmssink fixes).

### First-boot credentials

The image is configured by cloud-init from the `CIDATA` partition, which can be edited from
any OS. `cidata/user-data` is your local copy and is ignored by git. Without one, the
build uses [`cidata/user-data.example`](cidata/user-data.example): user `ubuntu`, password
`ubuntu`, and the password must be changed at the first login (as on Ubuntu's own
preinstalled images). Put your SSH key in `cidata/user-data`, or edit `user-data` on the
card's CIDATA partition before the first boot.

## Flashing and booting

```sh
scripts/flash-sd.sh /dev/sdX [desktop]   # write the image to an SD card (asks to confirm)
# on the board, to move to the M.2 SSD and put U-Boot in SPI flash:
sudo opi5-install-ssd
```

- Serial console: UART2 at **115200** baud (the image and U-Boot use 115200, not Rockchip's
  1500000). `scripts/serial-log.py <serial device> 115200 serial.log` logs it with timestamps.
- `scripts/flash-uboot-sd.sh` rewrites only the boot loader on an SD card (recovery).

## Updating a running board

```sh
scripts/pi-add-key.sh                 # once: create/install the project SSH key
scripts/pi-update.sh                  # copy new kernel debs + U-Boot to the board
# then on the board: sudo /tmp/opi5-update/pi-apply-update.sh
```

Always install the whole `linux-image` package, never a `vmlinuz` on its own. The config has
`CONFIG_DEBUG_INFO_BTF_MODULES=y`, so a new image rejects every in-tree module from an older
build. Installing the package also overwrites the DTB directory, so re-install any custom DTB
afterwards.

### Drop-in modules and DTBs

To test a topic without a full kernel build, build its modules against the
configuration, symbol versions and signing key of your image kernel build
(`build/linux` from `build-kernel.sh`), in a separate output directory:

```sh
export ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu-
T=<topic-tree>  B=build/wt-<topic>       # T: a checkout of the topic branch
mkdir -p $B/certs
cp build/linux/.config build/linux/Module.symvers $B/
cp build/linux/certs/signing_key.pem build/linux/certs/signing_key.x509 $B/certs/
make -C $T O=$PWD/$B olddefconfig modules_prepare
make -C $T O=$PWD/$B M=drivers/media/platform/rockchip/rkvdec modules   # signed with your key
make -C $T O=$PWD/$B rockchip/rk3588s-orangepi-5-sata.dtb              # DT changes
# on the board:
sudo install -Dm644 -t /lib/modules/$(uname -r)/updates/opi5-<topic>/ *.ko && sudo depmod -a
sudo cp rk3588s-orangepi-5-sata.dtb /usr/lib/linux-image-$(uname -r)/rockchip/
```

If a topic changes a core module's exported symbols (for example v4l2-core for the
stateless-encode uAPI), the dependent core modules have to be replaced too. The
topic's `notes/` say which modules that is.
Modules only load on a kernel built with the same signing key: build them against your own
kernel build, not against someone else's packages. To undo: remove
`/lib/modules/*/updates/opi5-*`, run `depmod -a`, and restore the packaged DTB
(`dpkg -i` the linux-image deb again).

## Testing and results

Testing is separate from the build. See [`docs/TESTING.md`](docs/TESTING.md) for how to re-run
the board tests in [`tests/`](tests/), [`docs/RESULTS.md`](docs/RESULTS.md) for the numbers
measured so far and the command behind each one, and [`docs/TEST-MEDIA.md`](docs/TEST-MEDIA.md)
for the clips (not included: public URLs, licences and sha256). Each topic's
`notes/TESTING.md` or `notes/RESULTS.md` has the per-topic details, and
[`docs/image-kernel/MANIFEST.md`](docs/image-kernel/MANIFEST.md) says where each patch range of the
image kernel comes from and how it was tested.

## Kernel topics

Each `topics/<topic>/` contains:

- `README.md`: what the topic is, what it sits on, the hardware-test state, the next upstream
  step, and a table of every patch with its author and upstream `Link:`.
- `ours/`: our patches, intended for upstream, with an `Assisted-by:` tag for the AI assistance
  used. The topic branches carry no `Signed-off-by:` yet; the copies in `patches/linux` (the image
  kernel) and the prepared upstream series do.
- `carried/`: other people's posted or published series that the topic needs, with their
  authorship and tags kept.
- `local/`: DO-NOT-UPSTREAM and local-only patches (backports, symbol-version shims, debug).
- `series`: the order in which to apply all of them with `git am`, on top of the parent topic.
- `topic.env`: branch, parent and base commit, plus the tip tree ID used to verify a rebuild.
- `cover-letter.txt` (written by hand) or `cover-letter.draft.txt` (generated skeleton), and
  `notes/` (design notes, results, test procedures and test tools).

Most topics are based on **v7.3**, on top of `multicore` and `board-sata`; the newer feature
branches sit on the image kernel (`image`; see each `topic.env`). The prepared upstream series are rebased on linux-next instead (see "Upstream
status"). The `v7.4-*` topics are early versions on the 7.4 merge window (`c339f4010`).

For `git` history instead of patch files, use the kernel fork named in
[`PUBLISH.md`](PUBLISH.md): branch `opi5/<topic>` for each topic, `opi5/image` for the exact
current image kernel and tags `image-<version>` for the image kernels.
`tools/recreate-kernel-branches.sh` builds the same branches locally from these patch files and
verifies every tree.

## Licensing

See [`LICENSE`](LICENSE). In short: the patches are under the licences of the projects they
apply to (Linux GPL-2.0, U-Boot GPL-2.0+, TF-A BSD-3-Clause). The scripts, tools and
documentation have their own licence, stated in `LICENSE`. Third-party material is not
included; [`docs/SOURCES.md`](docs/SOURCES.md) says where to get it.

## Contributing

See [`CONTRIBUTING.md`](CONTRIBUTING.md). Test reports from other RK3588/RK3588S boards are
especially welcome.
