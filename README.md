# Orange Pi 5 (RK3588S) on mainline Linux

Scripts, patches and notes for running the Orange Pi 5 on **mainline** software
only: Linux 7.3, U-Boot v2026.10 and open-source TF-A v2.15.0, with an Ubuntu 26.10
server image. The goal is to make the board feature-complete on mainline, video
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
| Video decode | rkvdec (VDPU381) H.264/HEVC on both cores (about 2x throughput for parallel 4K streams). VP9 on VDPU381 (carried series plus our conformance and performance fixes). Hantro G1, AV1 |
| Video encode | VEPU580 H.264 stateless encoder driver (new, working on the board). VPU121 H.264 encode (hantro). VEPU121 JPEG on 4 cores. HEVC encode is written but not yet run on hardware |
| JPEG decode | New VDPU720 (rkjpegd) driver, works on the board |
| Deinterlace | New IEP2 driver, works on the board |
| GPU / NPU | panthor (Mali-G610) and rocket (NPU) work. DVFS/clock fixes are written and wait for re-testing |
| Display | HDMI0 up to 4K60 TMDS. HDMI 2.1 FRL, USB-C DP alt-mode and MIPI DSI panels are prepared but not yet tested (no FRL monitor, DP cable or panel) |
| Camera | rkisp2 series plus Orange Pi 5 sensor overlays. Probing works, but no camera module has been attached yet |
| Suspend | Not working yet. Analysis and a TF-A fix are in `topics/suspend` and `patches/tf-a` |

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
overlay/, cidata/         root-filesystem overlay and cloud-init seed for the image
topics/<topic>/           one kernel topic (see "Kernel topics" below)
docs/                     SOURCES.md (third-party material and URLs), workspace notes
tools/                    export, secret scan, kernel-branch recreation
```

## Building

Host: Ubuntu 26.10 x86_64 (other recent Debian/Ubuntu releases should work). It needs
about 40 GB of disk, and a full kernel package build takes 45 to 60 minutes on 20 cores.

```sh
./install-deps.sh                 # host packages (sudo)
cp local.env.example local.env    # optional: board address, network ports, identity
scripts/fetch-sources.sh          # pinned Linux v7.3, U-Boot v2026.10, TF-A v2.15.0, rkbin
scripts/build-uboot.sh            # -> out/u-boot-rockchip.bin, out/u-boot-rockchip-spi.bin
scripts/build-kernel.sh           # -> out/debs/linux-{image,headers}-7.3.0-opi5_*.deb
scripts/build-image.sh            # (sudo) -> out/ubuntu-26.10-server-orangepi5.img.xz
```

What each step does:

- **`fetch-sources.sh`** makes shallow clones at pinned tags or commits into `src/` and checks
  the commit IDs. `build-*.sh` also run it for any tree that is missing. Every URL and version
  is listed in [`docs/SOURCES.md`](docs/SOURCES.md). No third-party code or binary is stored
  in this repository. The DDR init blob comes from rkbin at build time, and Rockchip's rkbin
  licence applies to it.
- **`build-uboot.sh`** builds TF-A BL31 from source (`BL31_SRC=rkbin` uses Rockchip's binary
  instead), resetting `src/tf-a` to v2.15.0 and applying `patches/tf-a/*.patch`. It patches
  a copy of the rkbin DDR blob to print at 115200 baud, adds the board fragments from
  `patches/u-boot/` (M.2 SATA/NVMe auto-detect, `M2_MODE=auto|sata|nvme`, and big-core clocks)
  and builds `orangepi-5-rk3588s_defconfig` with the console at 115200.
- **`build-kernel.sh`** resets `src/linux` to v7.3 and applies `patches/linux/*.patch` in
  order (with `OPI5_EXTRA=1`, also `patches/linux-extra/` and `scripts/opi5-extra.config`: hardware
  support not yet tested on a board). It does this only when the patch set changes, so rebuilds stay incremental. The
  config is Ubuntu's generic arm64 config (downloaded from ports.ubuntu.com) plus
  `scripts/opi5.config`. It builds signed modules (the kernel enforces lockdown) and
  cross-builds `linux-headers` for on-board DKMS through a private arm64 sysroot. The
  module-signing key is generated in `build/linux/certs/` and must stay private. It is never
  part of this repository or of any package.
- **`build-image.sh`** runs mmdebstrap for Ubuntu 26.10 arm64, applies `overlay/`, installs the
  kernel packages and writes a GPT image: U-Boot at sector 64, a `CIDATA` FAT partition
  holding the cloud-init seed, and the root file system, which grows on first boot.

### First-boot credentials

The image is configured by cloud-init from the `CIDATA` partition, which can be edited from
any OS. `cidata/user-data` is your local copy and is ignored by git. Without one, the
build uses [`cidata/user-data.example`](cidata/user-data.example): user `ubuntu`, password
`ubuntu`, and the password must be changed at the first login (as on Ubuntu's own
preinstalled images). Put your SSH key in `cidata/user-data`, or edit `user-data` on the
card's CIDATA partition before the first boot.

## Flashing and booting

```sh
scripts/flash-sd.sh /dev/sdX          # write the image to an SD card (asks to confirm)
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
