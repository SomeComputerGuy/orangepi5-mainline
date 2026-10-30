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

Nothing in here has been sent upstream yet.

## What works

Tested on an Orange Pi 5 (RK3588S, 8 GB) booting from an M.2 SATA SSD with the image kernel
(`patches/linux`) or with drop-in modules built from the topic branches. Details for each
topic are in its `notes/`.

| Area | State |
|---|---|
| Boot | Mainline U-Boot from SPI flash or SD. TF-A BL31 from source. Big cores clocked up before Linux (boot time from 100 s down to normal). M.2 slot auto-detects NVMe or SATA and picks the matching DTB |
| Storage | M.2 SATA (new `rk3588s-orangepi-5-sata` DTB). The SATA-root reboot hang is fixed (arm-smmu-v3 power domain and clock) |
| Video decode | rkvdec (VDPU381) H.264/HEVC on both cores (about 2x throughput for parallel 4K streams). VP9 on VDPU381 (carried series plus our conformance and performance fixes). Hantro G1, AV1. All decoders bit-exact in the codec sweep (`topics/codec-quality`). One stream on both cores through the CCU is **in progress** (`topics/rkvdec-ccu`, not in the image) |
| Video encode | VEPU580 H.264 stateless encoder driver (new, working on the board). VPU121 H.264 encode (hantro). VEPU121 JPEG on 4 cores. HEVC encode is written but not yet run on hardware |
| JPEG decode | New VDPU720 (rkjpegd) driver, works on the board |
| Deinterlace | New IEP2 driver, works on the board |
| GPU / NPU | panthor (Mali-G610) and rocket (NPU) work. DVFS/clock fixes are written and wait for re-testing |
| Display | HDMI0 up to 4K60 TMDS and HDMI 2.1 FRL 4K120. USB-C DP alt-mode (with a pin-assignment re-train fix). Dual display with 0 VOP2 underflows (AXI port balancing). MIPI DSI panels are prepared but untested (no panel) |
| Audio | HDMI audio, including across FRL/TMDS mode changes. DP audio is checked at signal level only. The headphone jack has UCM defaults but hasn't been checked by ear |
| Browsers / players | VA-API driver ([libva-v4l2_request fork](https://github.com/SomeComputerGuy/libva-v4l2_request)), FFmpeg/mpv V4L2 Request hwaccels, GStreamer v4l2codecs. The desktop image that bundles them is not built yet |
| Camera | rkisp2 series plus Orange Pi 5 sensor overlays. Probing works, but no camera module has been attached yet |
| Suspend | Not working yet. The TF-A fix (`patches/tf-a`) and kernel resume fixes are in. An s2idle resume hang (with a fast console) is still open: `topics/suspend`, `topics/suspend-k3` |

The authoritative list is [`STATUS.md`](STATUS.md), generated from the workspace together with the topics.

## Layout

```
README.md, STATUS.md      this file; per-topic status table (generated)
LICENSE, LICENSES/        licensing per directory
PUBLISH.md, publish.sh    how this repository and the kernel branches get to GitHub
install-deps.sh           host packages (Ubuntu 26.10 x86_64 build host)
local.env.example         site settings (board address, network ports, identity)
scripts/                  build, flash, board-update and lab-network scripts
  opi5.config             kernel config fragment on top of Ubuntu's arm64 config
patches/linux/            image kernel: applied in order on v7.3 by build-kernel.sh
patches/linux-extra/      optional, untested-on-hardware extras (OPI5_EXTRA=1 build-kernel.sh)
patches/u-boot/           U-Boot -u-boot.dtsi fragments copied in by build-uboot.sh
patches/tf-a/             TF-A patches applied on v2.15.0 by build-uboot.sh
patches/upstream/u-boot/  two U-Boot patches prepared for the U-Boot list
patches/{ffmpeg,mpv,gstreamer}/  media package patches (build-media-debs.sh)
overlay/, cidata/         root-filesystem overlay and cloud-init seed for the image
overlay-desktop/          extra overlay for the desktop image
topics/<topic>/           one kernel topic (see "Kernel topics" below)
docs/                     SOURCES.md (third-party material and URLs), workspace notes
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
| 3. `build-kernel.sh` | `debs/linux-image-7.3.0-opi5_7.3.0-<n>_arm64.deb`, `linux-headers-…`, `linux-libc-dev_…` |
| 4. `build-uboot.sh` | `u-boot-rockchip.bin` (SD/eMMC, sector 64) and `u-boot-rockchip-spi.bin` (SPI NOR) |
| 5. `build-media-debs.sh` | `debs-media/`: `ffmpeg`/`libav*` `7:8.1.2-2ubuntu2+opi5.2`, `mpv` `0.41.0-2ubuntu5+opi5.1`, `gstreamer1.0-plugins-bad` and friends `1.28.6-1ubuntu1+opi5.1`, plus a `Packages` index. Logs: `build/media/<source>.*/build.log` |
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
  branch `opi5/image-7.3` in the [kernel fork](https://github.com/SomeComputerGuy/linux).
- **`build-uboot.sh`** builds TF-A BL31 from source (`BL31_SRC=rkbin` uses Rockchip's binary
  instead), resetting `src/tf-a` to v2.15.0 and applying `patches/tf-a/*.patch`. It patches
  a copy of the rkbin DDR blob to print at 115200 baud, adds the board fragments from
  `patches/u-boot/` (M.2 SATA/NVMe auto-detect, `M2_MODE=auto|sata|nvme`, and big-core clocks)
  and builds `orangepi-5-rk3588s_defconfig` with the console at 115200.
- **`build-media-debs.sh`** rebuilds three Ubuntu 26.10 source packages in a rootless arm64
  chroot (`mmdebstrap --mode=unshare` + qemu-user). It runs `apt-get source` at the exact
  versions in the script and adds `patches/ffmpeg`, `patches/mpv` or `patches/gstreamer`.
  FFmpeg gets the V4L2 Request API hwaccels (H.264, HEVC, VP8, VP9, AV1, MPEG-2). mpv gets
  the v4l2request hwdec. gst-plugins-bad gets v4l2codecs per-device caps and kmssink fixes.
  Run with `ffmpeg mpv gst-plugins-bad1.0` arguments to build a subset. mpv needs the FFmpeg
  build first. `MEDIA_JOBS` sets the parallelism (default 6).
  The versions are pinned in the script. If Ubuntu has published a newer version of one of
  these packages and the archive no longer carries the pinned one, `apt-get source` fails. In
  that case, bump `VERSION` in the script to the archive's version. The patches usually still
  apply.
- **`build-va-driver.sh`** builds the VA-API driver for the V4L2 stateless decoders, so
  Firefox and Chrome can decode with the hardware. It uses
  [SomeComputerGuy/libva-v4l2_request](https://github.com/SomeComputerGuy/libva-v4l2_request),
  branch `opi5/main`, pinned at commit `069af0906f88`. That is megi's
  [libva-v4l2_request](https://xff.cz/git/libva-v4l2_request) `cac6ece` plus three of
  sofus13's HEVC fixes and our RK3588 work, under GPL-3.0-or-later. The build uses the
  source's own `debian/` packaging, in the same kind of rootless chroot as the media packages.
- **`build-image.sh`** runs mmdebstrap for Ubuntu 26.10 arm64. It adds `out/debs-media` as a
  local apt repository (pinned above the archive), applies `overlay/` (and, for the desktop,
  `overlay-desktop/` and `scripts/customize-desktop.sh`), installs the kernel packages and
  writes a GPT image. The image has U-Boot at sector 64, a `CIDATA` FAT partition holding the
  cloud-init seed, and the root file system, which grows on first boot. Both variants need
  the FFmpeg and GStreamer rebuilds. The desktop variant also needs mpv and the VA driver.
  It installs `ubuntu-desktop-minimal`, Firefox from Mozilla's apt repository, Google
  Chrome from Google's, and Jellyfin MPV Shim from the wheels pinned in
  `scripts/jellyfin-mpv-shim.wheels`. `--rootfs-tar FILE` builds only the root filesystem,
  rootless, to check that the package set resolves. `--reuse-rootfs` reuses the previous
  run's tree.

**Verified so far:** the kernel, U-Boot and server-image steps have been built from these
scripts and booted on the test board. The VA driver and the FFmpeg V4L2 Request patches have
been tested on the board. The GStreamer patches are build-tested only. The **desktop image
has not been built or booted yet**, so treat `--variant desktop` as untested.

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
  1500000). `scripts/serial-log.py /dev/ttyUSB0 115200 serial.log` logs it with timestamps.
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

## Testing

Each topic's `notes/TESTING.md` or `notes/RESULTS.md` has the exact commands, test vectors
and pass/fail criteria used on the board. The tools used are GStreamer `v4l2codecs`, FFmpeg,
fluster, v4l2-compliance, modetest, glmark2 and vkmark, plus the small test clients under
`topics/*/notes/tools/`. Test media is not included. `docs/SOURCES.md` says where the
conformance vectors come from.

## Kernel topics

Each `topics/<topic>/` contains:

- `README.md`: what the topic is, what it sits on, the hardware-test state, the next upstream
  step, and a table of every patch with its author and upstream `Link:`.
- `ours/`: our patches, intended for upstream. They have no `Signed-off-by:` yet; the author
  adds it when sending.
- `carried/`: other people's posted or published series that the topic needs, with their
  authorship and tags kept.
- `local/`: DO-NOT-UPSTREAM and local-only patches (backports, symbol-version shims, debug).
- `series`: the order in which to apply all of them with `git am`, on top of the parent topic.
- `topic.env`: branch, parent and base commit, plus the tip tree ID used to verify a rebuild.
- `cover-letter.txt` (written by hand) or `cover-letter.draft.txt` (generated skeleton), and
  `notes/` (design notes, results, test procedures and test tools).

Most topics are based on **v7.3**, on top of `multicore` and `board-sata` (see each
`topic.env`). They will be rebased onto 7.4-rc1 before sending. The `v7.4-*` topics are
early versions on the 7.4 merge window (`c339f4010`).

For `git` history instead of patch files, use the kernel fork named in
[`PUBLISH.md`](PUBLISH.md): branch `opi5/<topic>` for each topic, and `opi5/image-7.3`
for the exact image kernel. `tools/recreate-kernel-branches.sh` builds the same branches
locally from these patch files and verifies every tree.

## Licensing

See [`LICENSE`](LICENSE). In short: the patches are under the licences of the projects they
apply to (Linux GPL-2.0, U-Boot GPL-2.0+, TF-A BSD-3-Clause). The scripts, tools and
documentation have their own licence, stated in `LICENSE`. Third-party material is not
included; [`docs/SOURCES.md`](docs/SOURCES.md) says where to get it.

## Contributing

See [`CONTRIBUTING.md`](CONTRIBUTING.md). Test reports from other RK3588/RK3588S boards are
especially welcome.
