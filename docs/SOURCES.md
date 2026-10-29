# Sources and provenance

This repository ships no third-party or vendor material: no kernel, U-Boot or TF-A trees, no
Rockchip binaries (rkbin), no Rockchip MPP or BSP sources, no board schematics or manuals, no
mailing-list mboxes, no API dumps and no test media. The build scripts fetch the build inputs at
build time. Everything else listed here was read during development as reference and is **not
redistributed**. This file records where each piece is published, so the work can be reproduced.

Conventions:

- Hashes are full 40-character git commit ids unless marked "short". A short id is all the work
  notes recorded. Resolve it against the named public repository.
- `msgid:` values are lore message-ids. Open them as `https://lore.kernel.org/r/<msgid>`, or
  fetch a series with `b4 am <msgid>`.
- "Origin not recorded" means the work notes do not say where the file came from. It is listed
  so nobody assumes it is part of this repository.

## Build-time inputs (fetched by scripts)

| Name | URL | Pinned version / commit | Files used | Licence | Used for |
|---|---|---|---|---|---|
| Linux | https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git | tag `v7.3` (tag object `091b06388b117fefdcb63336ac09956a4914b961`, commit `c03c1a14507dfaf8b856c2608f9ac216021fc222`) | whole tree; `patches/linux/*.patch` applied on top by `scripts/build-kernel.sh` | GPL-2.0 | Board kernel `7.3.0-opi5` and the base of every `opi5/*-7.3` topic branch |
| Linux 7.4 merge window (reference base) | https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git | `master` at `c339f4010dea8b0d754f84ace70cd1b089878ef8` (2026-10-28) | rga/ and rkvdec/ sources (synced into `patches/linux/0101`); comparison only otherwise | GPL-2.0 | Base of the non-`-7.3` branches (`opi5/multicore`, `opi5/dp-altmode`, `opi5/rkisp2`, `opi5/rkvdec-vp9`, `opi5/hdmi-frl`, `opi5/vepu580`); upstream-status checks |
| linux-next (reference) | https://git.kernel.org/pub/scm/linux/kernel/git/next/linux-next.git | `next-20261028` (`6d0933ae9d46674a6ea63a87e9e9ab4e662670c9`) | none (read-only comparison) | GPL-2.0 | Upstream-status checks |
| Rockchip SoC tree (reference) | https://git.kernel.org/pub/scm/linux/kernel/git/mmind/linux-rockchip.git | `for-next` at `d2abcbb905b0e4b2e06b257fa1e5bcf4faa6dbda` | none (read-only comparison) | GPL-2.0 | Upstream-status checks of DT changes |
| U-Boot | https://source.denx.de/u-boot/u-boot.git | tag `v2026.10` (`5508406582f6f7120dce0c4b3059819a41788db2`) | whole tree; `patches/u-boot/*.dtsi` copied in by `scripts/build-uboot.sh` | GPL-2.0+ | Board boot loader (`u-boot-rockchip.bin`, `u-boot-rockchip-spi.bin`) |
| U-Boot upstream development base | https://source.denx.de/u-boot/u-boot.git | `v2027.01-rc1` (`dfcfc4c9f78d1743f490a497082a4ec8e058aae8`) | base for 2 local commits (`fbf3b6bf924aef60c4260cab04a2bac509f2c00e` "ata: dwc_ahci: Look up the PHY on sata-port subnodes too", `f8fb03e50de95accfa191f47c6db3016da4a28ae` "rockchip: rk3588: Raise the Cortex-A76 cluster clocks to 1.2 GHz") | GPL-2.0+ | Patches prepared for upstream submission (`scripts/make-uboot-patches.sh`) |
| Trusted Firmware-A | https://github.com/ARM-software/arm-trusted-firmware.git | tag `v2.15.0` (`da738d5eae93af342fdc4995dd3c05acb4c9d757`) | `PLAT=rk3588 bl31`; `patches/tf-a/*.patch` applied on top | BSD-3-Clause | Open-source BL31 (default `BL31_SRC=tfa`) |
| rkbin | https://github.com/rockchip-linux/rkbin.git | `3e288fe814e059dd06833495f845cab04ac20a5c` (2026-06-26, "rk3572: ddr: Update to v1.07 260626") | `bin/rk35/rk3588_ddr_lp4_2112MHz_lp5_2400MHz_v1.24.bin` (sha256 `2853a0da7ab895af43d50615af73eccf0694115dd0202483ee1c93c9071a42c3`); `tools/ddrbin_tool.py` (sha256 `1edfd0cbfed0f7650523d03881822015ba1301bb412629d54b2fca892eea86a7`); `tools/ddrbin_param.txt` (sha256 `3415639471f64a747d74c5c574d53b6341a531ddc3d61bb4daf9e7e88094114c`); optional `bin/rk35/rk3588_bl31_v1.56.elf` (sha256 `2864c2fc36333e03e7e3fe6459225d320d310850b4ac7620d1f3601efb7d4a9b`, only with `BL31_SRC=rkbin`) | Rockchip proprietary licence (rkbin `LICENSE`: redistribution allowed, no reverse engineering) | DDR init blob (TPL), re-parameterised to 115200 baud with `ddrbin_tool.py`; fallback closed BL31 |
| Ubuntu kernel config base | http://ports.ubuntu.com/ubuntu-ports/pool/main/l/linux/linux-modules-7.3.0-10-generic_7.3.0-10.10_arm64.deb | `7.3.0-10.10` (sha256 `fd856e9c7a5798f8e999b1eb7690ddd38dcffcf60544ecc1dd8b8d39b9a2bfb3`) | `./boot/config-7.3.0-10-generic` only | GPL-2.0 (Ubuntu kernel) | Base `.config`, merged with `scripts/opi5.config` |
| Ubuntu arm64 sysroot debs | http://ports.ubuntu.com/ubuntu-ports/ (pool path from `apt-cache show`, Ubuntu 26.10 "stonking") | `libssl-dev`/`libssl4` 4.0.3-1ubuntu1; `libdw-dev`/`libdw1t64` 0.196-1; `libelf-dev`/`libelf1t64` 0.196-1; `zlib1g-dev`/`zlib1g` 1.3.dfsg+really1.3.2-3ubuntu1.1; `libzstd1` 1.5.7+dfsg-4; `liblzma5` 5.8.3-1ubuntu1; `libbz2-1.0` 1.0.8-6build2 | headers and libraries, unpacked into a private sysroot | per package (OpenSSL Apache-2.0, elfutils LGPL/GPL, zlib, zstd BSD/GPL, xz, bzip2) | Cross-building the arm64 `scripts/` (sign-file, gendwarfksyms) shipped in `linux-headers` |
| Ubuntu 26.10 root filesystem | http://ports.ubuntu.com/ubuntu-ports, suite `stonking` (+ `-updates`, `-security`), components main restricted universe multiverse | package versions current at image build time (not pinned) | package list in `scripts/build-image.sh` | per package | SD-card image (`scripts/build-image.sh`, mmdebstrap) |
| Mali CSF firmware | Ubuntu package `linux-firmware-misc` (from https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git) | version current at image build time; firmware reported by panthor: git sha `95a25d71` (short), interface v1.5.0 | `arm/mali/arch10.8/mali_csffw.bin.zst` | Arm redistributable licence (`LICENCE.mali_csffw` in linux-firmware) | GPU (panthor) bring-up and validation |

## Upstream patch series carried in the kernel branches

All of these are public, GPL-2.0 kernel patches. They are applied with authorship and tags kept.
Most `-7.3` branches stack on `opi5/multicore-7.3`, so the RGA and rkvdec multi-core series
appear in nearly every `-7.3` branch.

| Series | Author | Version | Link / origin | Topic / branch |
|---|---|---|---|---|
| media: rockchip: rga: Add multi-core support (17) | Sven Püschel | v2, 2026-09-16 | msgid `20260916-spu-rga3multicore-v2-0-23aa2cb74e61@pengutronix.de` (v1 for reference: `20260606-spu-rga3multicore-v1-0-3ec2b15675f7@pengutronix.de`) | `opi5/multicore`, `opi5/multicore-7.3` and the branches on top; `patches/linux/0102-0118` |
| media: rkvdec: Enable multi-core support (patches 1, 2, 4, 5 of 5; 3/5 is already in the RGA series) | Detlev Casanova | v2, 2026-08-10 | msgid `20260810-rkvdec-multicore-v2-0-986f89d22cdc@collabora.com` | `opi5/multicore`, `opi5/multicore-7.3`; `patches/linux/0119-0122` |
| phy: rockchip: usbdp: Clean up the mess (part 1) (16, includes patches by Frank Wang, William Wu, Zhang Yubing) | Sebastian Reichel | v15, 2026-09-15 | msgid `20260915-rockchip-usbdp-cleanup-v15-0-80e2c11d1ce8@collabora.com` (merged for 7.4) | `opi5/dp-altmode-7.3` |
| phy: rockchip: usbdp: Clean up the mess (part 2) (11) | Sebastian Reichel | v15, 2026-09-15 | msgid `20260915-rockchip-usbdp-cleanup-part2-v15-0-8d507cb1174f@collabora.com` | `opi5/dp-altmode-7.3` |
| phy: rockchip: usbdp: Clean up the mess (38; patches 34-38 are the basis of "part 3") | Sebastian Reichel | v14, 2026-08-13 | msgid `20260813-rockchip-usbdp-cleanup-v14-0-b5ad9c68fa11@collabora.com` | reference for `opi5/dp-altmode-7.3` |
| usb: dwc3: introduce Rockchip glue driver (7) | Sebastian Reichel | v18, 2026-10-21 | msgid `20261021-b4-rockchip-dwc3-rockchip-glue-v18-0-60000d03fca2@collabora.com` | `opi5/dp-altmode`, `opi5/dp-altmode-7.3` |
| Synopsys DisplayPort Controller improvements for Rockchip platforms (21) | Sebastian Reichel | v11, 2026-08-06 | msgid `20260806-synopsys-dw-dp-improvements-v11-0-0d508505f383@collabora.com` (v9 for reference: `20260803-synopsys-dw-dp-improvements-v9-0-2e6e46135312@collabora.com`) | `opi5/dp-altmode`, `opi5/dp-altmode-7.3` |
| USBDP "part 3", drm/connector OOB hotplug cache, DP sound-dai-cells fix, typec mux fix | Sebastian Reichel | Collabora branch `sre/usbdp-rework`, commits `52eef750d7c5ce13ea1d66b1be2d039c6250cb4c`, `c03e9dd764007ac7a510e1c05a00ac08e07d8b03`, `9b2366277462f629452654e1b1d05e17c6a378e8`, `713114cb94f79a06377636747095ca823b093e62`, `2391da40eb39e26b31972ef4a6d7a3d997a1c209`, `b6c756709db3ae6f85ef8133de754a8e7b7ec894`, `9b8b3adadabe758cf1848df72dce497d2a37d99f`, `d2872441c3d55c2cbb9c0449a6c90e22babadb8d`, `9e1bfcaf758d271d7aa57a056351e065dc5d9a8c` | https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/&lt;sha&gt; (each commit carries a `Link:` trailer) | `opi5/dp-altmode-7.3` |
| ROCK 5B DP AltMode DT and its VDO fix (models for the Orange Pi 5 DT, which is our own) | Sebastian Reichel | Collabora commits `7983809d4d2c5a6c39d936ed3140e378a3257ebd`, `c2d2e2b10a55c4d740a2faf1526a70c4f19da047` | https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/&lt;sha&gt; | `opi5/dp-altmode-7.3` (DT) |
| usb: typec: mux: initialize orientation switch array | Haobo Cheng | 2026-08-04 | msgid `20260804083434.20885-1-i@4t.pw` | `opi5/dp-altmode-7.3` |
| HDMI 2.0 (scrambling, SCDC, HPD rework), HDMI 2.1 FRL, hdptx TxFFE, VOP2 fixes/resets (114 commits) | Cristian Ciocaltea (Collabora) | Collabora branch `cristicc/hdmi-frl`, tip `30c98900c6187f014edc6068e78d95ee32dcca6e` (2026-09-04, based on v7.3-rc1). The HDMI 2.0 part is "Add HDMI 2.0 support to DW HDMI QP TX", msgid `20261005-dw-hdmi-qp-scramb-v12-0-195157ba0b40@collabora.com` (v12; v11 `20260901-dw-hdmi-qp-scramb-v11-0-bc12954a0688@collabora.com`) | https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux/-/commit/&lt;sha&gt; (per-commit `Link:` trailers); rebuilt from the GitLab API as mbox and `git am`'d | `opi5/hdmi-frl-7.3` |
| drm/scdc-helper: SCDC status / link-health debugfs (5) | Nicolas Frattaroli | v9, 2026-07-24 | msgids `20260724-scdc-link-health-v9-1-bdda406d016d@collabora.com` to `...-v9-5-bdda406d016d@collabora.com` (via `cristicc/hdmi-frl`) | `opi5/hdmi-frl-7.3` |
| drm/bridge: dw-hdmi-qp: use drm_hdmi_acr_get_n_cts() helper | Simon Wright | 2026 | msgid `86fcf349-0a7a-4618-9001-612371b0f71b@symple.nz` (via `cristicc/hdmi-frl`) | `opi5/hdmi-frl-7.3` |
| drm/bridge: dw-hdmi-qp: Guard clear_audio_infoframe when PHY is down | Frank Zhang | 2026-05-12 | msgid `20260512103153.8861-1-rmxpzlb@gmail.com` (via `cristicc/hdmi-frl`, Collabora commit `66689431479746ecda2eb2247e7ab22a75c50d52`) | `opi5/hdmi-frl-7.3` |
| drm/drm_scdc_helper: Add SCDC helper funcs for FRL (patch 04 of "Enable HDMI FRL for MTL+") | Ankit Nautiyal (Intel) | v2, 2026-10-12 | msgid `20261012035806.3361439-5-ankit.k.nautiyal@intel.com` (cover `20261012035806.3361439-1-ankit.k.nautiyal@intel.com`) | `opi5/hdmi-frl` (exploratory branch on the 7.4 base) |
| media: rockchip: rkisp2: Add driver for ISP on RK3588 (5) | Paul Elder, Xu Hongfei | v3, 2026-08-27 | msgid `20260827-rkisp2-v3-0-e91ff0a604d6@ideasonboard.com` | `opi5/rkisp2`, `opi5/camera-7.3` |
| media: Add V4L2 H.264 stateless encode and VC8000E (14; 9 carried, including Marco Felsch's hantro patch 11) | Paul Kocialkowski (and Marco Felsch) | v1, 2026-05-22 | msgid `20260522101653.2565125-1-paulk@sys-base.io` | `opi5/hevc-enc-uapi`, `opi5/vepu121-h264enc`, `opi5/rkvenc-7.3`, `opi5/rkvenc-hevc-7.3` |
| media: rkvdec: Add VP9 support for VDPU381 variant (3) | Venkata Atchuta Bheemeswara Sarma Darbha (co-developed by Igor Paunovic, Francesco Saverio Pavone) | v1, 2026-07-26 | msgid `20260726-b4-add-rkvdec2-vp9-vdpu381-v1-0-180fb2d1f10c@gmail.com`; applied from the Armbian packaging (https://github.com/armbian/build/pull/10874; patch file path in that PR not recorded) | `opi5/rkvdec-vp9`, `opi5/rkvdec-vp9-7.3`, `opi5/vp9-conf-7.3`, `opi5/vp9-perf-7.3` |
| media: rkvdec: align bytesperline to 64 bytes in rkvdec_fill_decoded_pixfmt() | Igor Paunovic | 2026 | no lore link recorded; from the same Armbian packaging (https://github.com/armbian/build/pull/10874) | same branches as the VDPU381 VP9 series |
| accel/rocket: DVFS for the RK3588 NPU (9 of 11; 1/11 and 3/11 are already in v7.3) | Igor Paunovic | v2, 2026-09-22 | msgid `20260922080114.44662-1-royalnet026@gmail.com` | `opi5/gpu-npu-7.3`, `opi5/board-dt` |
| RFC: GPU core clock from SCMI, panthor bus clock (3 of 4) | Jonas Karlman | RFC, 2025-04-27 (not posted to lore) | https://github.com/armbian/linux-rockchip/pull/380 (commits start at `a6a3efd3fda76957eaec0a007515e53ee606de9f`) | `opi5/gpu-npu-7.3`, `opi5/board-dt` |
| VEPU580 MPP-service encoder driver and IOMMU reserved regions (**vendor-derived, not for upstream**) | Ross Cawston | https://github.com/rcawston/rockchip-rk3588-mainline-patches, `main` at `e13a311d8ee5e8ed92ec3d4a57c21f766c61d660`, file `0001-rockchip-rk3588-vepu580-encoder-support-v3.patch` (introduced in `09595583f3ffadd3d790a20ead392434e0e46728`) | port of the Rockchip BSP `drivers/video/rockchip/mpp/` (mpp_rkvenc2, mpp_service, mpp_iommu); (GPL-2.0+ OR MIT) | `opi5/vepu580` only (experimental, not in `patches/linux`) |
| rkvenc / dma-buf heap fixes on top of the VEPU580 port (11) (**vendor-derived base**) | Andres Cera (CeraLive) | https://github.com/CERALIVE/rk3588-kernel-patches, `main` at `d3d6705a85e4f7fdf606a50bf2f333107b83a0d0`; the series before the "media island" rework (`patches/`, before commit `cb491dc`, short) | patches 0008, 0009, 0013-0016, 0018-0022 of that repository | `opi5/vepu580` only |

## Reference material (not redistributed)

These were read for register facts, pin mappings and behaviour. None of it is copied into this
repository. Where a kernel patch in this repository took facts or code from one of them, the
patch's commit message says so (see "Vendor-derived content" at the end).

### Board (Orange Pi 5) wiring

| What | URL | Version / commit / path | Used for |
|---|---|---|---|
| Orange Pi BSP kernel DTs | https://github.com/orangepi-xunlong/linux-orangepi | branch `orange-pi-6.1-rk35xx` (commit not recorded): `arch/arm64/boot/dts/rockchip/rk3588s-orangepi-5.dts`, `rk3588s-orangepi-5.dtsi`, `rk3588s-orangepi.dtsi`, `rk3588s-orangepi-5-lcd.dtsi`, `rk3588s-orangepi-5b.dts`, `overlay/rk3588-lcd1.dts`, `overlay/rk3588-lcd2.dts`; also branch `orange-pi-5.10-rk35xx` (same wiring) | DSI LCD pin mapping and VOP routing (dsi), DP AltMode mux evidence (dp-altmode), Ethernet/fan/PMIC/audio review (board-hygiene) |
| Orange Pi BSP camera DTs | https://github.com/orangepi-xunlong/linux-orangepi | `rk3588s-orangepi-5-camera1.dtsi`, `-camera2.dtsi`, `-camera3.dtsi` (branch and commit not recorded; `orange-pi-6.1-rk35xx` and `orange-pi-5.10-rk35xx` board DTs also read) | CAM1/2/3 connector I2C, MCLK, reset and power-down GPIOs (camera overlays) |
| Orange Pi BSP panel driver | https://github.com/orangepi-xunlong/linux-orangepi | branch `orange-pi-6.1-rk35xx`: `drivers/gpu/drm/panel/panel-innolux-afj101-ba2131.c`, `drivers/gpu/drm/panel/panel-simple.c` | Init table, timings and DSI flags of the Orange Pi 10.1" MIPI LCD (new ILI9881C entry, GPL-2.0+) |
| Orange Pi BSP misc | https://github.com/orangepi-xunlong/linux-orangepi | `rk3588-linux.dtsi`, `rk3588-rk806-single.dtsi`, `rk3588s.dtsi`, `sound/soc/rockchip/rockchip_i2s_tdm.c` (presumably `orange-pi-6.1-rk35xx`, not recorded) | board-hygiene: PMIC reset mode, I2S/TDM defaults |
| Orange Pi 5 user manual | Orange Pi official download page for Orange Pi 5 (orangepi.org); exact URL not recorded | v0.7 (sha256 `650b475c05a36b5e180e2a0c3adfc086b37d2c9ce07c4e91f824364c05a4f490`), sections 1.3 and 3.31 | LCD connector identification |
| Orange Pi 5 schematic | not obtained. Both Google Drive downloads returned a "quota exceeded" HTML page | none | none (wiring came from the BSP DTs) |

### Rockchip BSP kernel and MPP

| What | URL | Version / commit / path | Used for |
|---|---|---|---|
| Rockchip BSP kernel, MPP service drivers | https://github.com/rockchip-linux/kernel | branch `develop-6.1` (commit not recorded): `drivers/video/rockchip/mpp/mpp_iep2.c`, `rockchip_iep2_regs.h`; `develop-5.10` `mpp_iep2.c` | IEP2 register map, programming sequence and defaults (IEP2 deinterlacer driver) |
| Rockchip BSP kernel, JPEG/VDPU drivers | https://github.com/rockchip-linux/kernel | `develop-6.1`: `drivers/video/rockchip/mpp/mpp_jpgdec.c`, `mpp_vdpu1.c`, `mpp_vdpu2.c`, `mpp_common.h`, `Kconfig`, `Makefile` | Interrupt and reset handling of the VDPU720 JPEG decoder (rkjpegd) |
| Rockchip BSP kernel, rkvdec2 | https://github.com/rockchip-linux/kernel | `mpp_rkvdec2.c`, `mpp_rkvdec2.h`, `mpp_rkvdec2_link.c`, `mpp_rkvdec2_link.h` (branch not recorded, presumably `develop-6.1`) | vp9-perf: cache and link-mode behaviour (no patch resulted) |
| Rockchip BSP kernel, rkvenc2 | https://github.com/rockchip-linux/kernel/blob/develop-6.1/drivers/video/rockchip/mpp/mpp_rkvenc2.c | `develop-6.1` | VEPU580 IRQ bits, power/watchdog/reset/IOMMU recovery sequences (rkvenc) |
| Rockchip BSP SoC DT | https://github.com/rockchip-linux/kernel | `develop-6.1` and `develop-5.10`: `arch/arm64/boot/dts/rockchip/rk3588s.dtsi`, `rk3568.dtsi` | Addresses, clocks, resets, IRQs of IEP2, rkjpegd, VEPU121, VEPU580 |
| Rockchip BSP display drivers | Rockchip BSP kernel (repository and branch not recorded) | `dw-hdmi-qp.c`, `dw-hdmi-qp.h`, `dw_hdmi.h`, `dw_hdmi_qp-rockchip.c`, `dw_hdmi-rockchip.c`, `phy-rockchip-samsung-hdptx.c`, `rockchip_drm_vop2.c`, `rockchip_vop2_reg.c` | hdmi-frl: reference only, nothing ported |
| Rockchip MPP userspace library | https://github.com/rockchip-linux/mpp | branch `develop` (commit not recorded) | All of the following were used as data only, no code copied (Apache-2.0) |
| | | `mpp/hal/rkenc/h264e/hal_h264e_vepu580.c`, `hal_h264e_vepu580_reg.h`, `hal_h264e_vepu580_tune.c`, `vepu580_common.h`, `vepu5xx_common.c`; `mpp/hal/rkenc/h265e/hal_h265e_vepu580.c`, `hal_h265e_vepu580_reg.h`, `h265e_ps.c`; `osal/inc/mpp_service.h` | VEPU580 register layout and default tuning (rkvenc, rkvenc-hevc) |
| | | `mpp/hal/vpu/h264e/hal_h264e_vepu1_v2.c`, `hal_h264e_vepu2_v2.c`, `hal_h264e_vepu2_reg_tbl.h`, `hal_h264e_vepu_v2.c/.h`, `hal_h264e_stream_amend.c`; `mpp/codec/enc/h264/h264e_api_v2.c`, `h264e_sps.c`, `h264e_pps.c`, `h264e_slice.c` | VEPU121 slice header and stream-offset register meaning |
| | | `mpp/hal/vpu/jpegd/*` (`hal_jpegd_rkv.c`, `hal_jpegd_rkv_reg.h`, `hal_jpegd_vpu7xx_com.c`, `hal_jpegd_vdpu2.c`, ...), `mpp/codec/dec/jpeg/jpegd_parser.c`, `osal/mpp_soc.c` | rkjpegd register map and table layout |
| | | `mpp/hal/rkdec/vp9d/hal_vp9d_vdpu34x.c`, `hal_vp9d_rkv.c`, `hal_vp9d_com.c/.h`, `vdpu34x_com.h` | VDPU381 VP9 segment-map and probability handling (vp9-conf, vp9-perf) |
| | | `mpp/vproc/iep2/*.c`, `mpp/vproc/mpp_dec_vproc.c` | IEP2 tuning defaults and field order |

### Other vendor / downstream trees

| What | URL | Version / commit / path | Used for |
|---|---|---|---|
| ChromeOS kernel, rockchip-vpu | https://chromium.googlesource.com/chromiumos/third_party/kernel | branch `chromeos-4.4`, `drivers/media/platform/rockchip-vpu/` (tree `c69a8579a8550b357741434ef79a89e9130933a6`): `rk3399_vpu_hw_h264e.c`, `rk3399_vpu_hw.c`, `rk3399_vpu_hw_vp8e.c`, `rk3399_vpu_regs.h`, `rockchip_vpu_enc.c/.h`, `rockchip_vpu_common.h`, `rockchip_vpu_hw.h` | VEPU121 H.264 register programming and mode-decision tables (GPL-2.0, ported) |
| Armbian IEP v1 driver | https://github.com/armbian/build, `patch/kernel/archive/rockchip64-5.14/add-rockchip-iep-driver.patch` (commit not recorded) | Paolo Sabatino / Alex Bee | IEP2: V4L2 structure reference only |
| VEPU580 out-of-tree port | https://github.com/rcawston/rockchip-rk3588-mainline-patches | `e13a311d8ee5e8ed92ec3d4a57c21f766c61d660` | VEPU580 programming model (`docs/vepu580-programming-model.md`), basis of `opi5/vepu580` |
| CeraLive fork | https://github.com/CERALIVE/rk3588-kernel-patches | `d3d6705a85e4f7fdf606a50bf2f333107b83a0d0` | Same as above, plus QA notes |
| Rock 5B+ downstream notes | https://github.com/dongioia/rock5bplus-rkvdec2 | tree `2c67fd3a3fde501d3f90082ad7f1c849d4f2d6cc` (README.md) | rkvdec-vp9: status of the VDPU381 VP9 work elsewhere |
| GStreamer v4l2codecs / VP9 parser | https://gitlab.freedesktop.org/gstreamer/gstreamer | gst-plugins-bad 1.28.6 (Ubuntu source package): `sys/v4l2codecs/gstv4l2codecvp9dec.c`, `gst-libs/gst/codecparsers/gstvp9statefulparser.c`, `gst-libs/gst/codecs/gstvp9decoder.c` | Root cause of the inter-frame resize drops (LGPL-2.0+) |
| v4l-utils | https://linuxtv.org/downloads/v4l-utils/v4l-utils-1.32.0.tar.xz | 1.32.0 (sha256 `6828828a17775526eb93fb258a9294d1d1073d633c344dd71ecd4e7a1ffb7dfc`) | v4l2-compliance checks behind the hantro-validate fixes |

### Collabora GitLab (read through the GitLab API)

Repository: https://gitlab.collabora.com/hardware-enablement/rockchip-3588/linux

| What | Branch / commits | Used for |
|---|---|---|
| HDMI 2.0/2.1 FRL | `cristicc/hdmi-frl`, tip `30c98900c6187f014edc6068e78d95ee32dcca6e` (2026-09-04) | Source of the hdmi-frl branch (see above) |
| USB-C DP AltMode | `sre/usbdp-rework` (commits listed above); also read for reference: `1fd8f8b60540b7d779c171ecb5587a1b10ebbf05`, `4e7380b84d6fcdf6f6ebb8f4eb609c967bafb7a5`, `bc7b1dbdfa43ea53d900da688ecfcdce1d65337e`, `cc247e90cf280c4b7a87de868a2aa54c4b435fa8`, `d8f44d12710f2c98b7885f2f30ef45e8934ef7ec`, `dae79e46faa760d01afa802a66659db562f4d9f8`, `e02b5102837698edf66bc1db54be85a6427bcc6c` | dp-altmode |
| VICAP / CSI | `mriesch/mainline/rk3588-vicap` (head `607783c08e8aeca96b04cadf0b8736dc3d563e5c`), `mriesch/radxa/rk3588-vicap` (head `9bc38166b447da06aa999d07ec62d066137331c0`), May 2025 | camera: status of csi0/csi1 and DC-PHY RX |
| arm-smmu-v3 runtime PM (Pranjal Shrivastava's series, upstream msgids `20260728210928.1050849-*`) | `rockchip-devel`: `92b09f5dcde0e2f3e056e71ec42f53856c2fc194`, `a40cf7f21b833ead90def204db428f9cc21ffaee`, `d47871efb1aaa25100e45fdd0103f296e686e6de`, `da7630ff0392bdf07927432638d1c5f7dd55db3e` | shutdown-hang: upstream status |
| PM domain cleanup | `sre/pm-domain-cleanup` (2026-09-25): `e2e1a975`, `1b2408a2`, `47b36fc5` (short) | board-hygiene: upstream status |

### Mailing-list threads (lore.kernel.org)

| What | Link | Used for |
|---|---|---|
| Intel "Enable HDMI FRL for MTL+" | msgid `20261012035806.3361439-1-ankit.k.nautiyal@intel.com` | hdmi-frl: generic FRL/SCDC helpers |
| hdptx FRL, SCDC, link training and HDMI 2.1 searches | lore search result mboxes (queries not recorded); main threads: "Add HDMI 2.0 support to DW HDMI QP TX" v8-v12, "phy: rockchip: samsung-hdptx" fix/FRL series v4-v6, "Add HDMI 2.1 FRL support" v6, drm/amd and drm/i915 FRL link-training patches | hdmi-frl background |
| media: rkvdec: fix clk reference leak on unbind | msgid `20260717154505.83935-1-pavone.lawyer@gmail.com` (v4) | rkvdec-vp9: reviewed, not carried |
| Stateless encode uAPI history | see `docs/stateless-encode-uapi-survey.md` for the full list of lore, patchwork, patchew and Linux Media Summit links | hevc-enc-uapi design |

## Test vectors and media

| What | URL / origin | Version / hash | Used for |
|---|---|---|---|
| VP9 conformance vectors (fluster suite `VP9-TEST-VECTORS`) | downloaded by fluster 0.7.1 (Ubuntu package) from the libvpx test data listed in its suite file (WebM project) | full suite (305 vectors); local copies of `vp90-2-09-aq2.webm` (`c109832aeabf087b0cc3ef071cf9cf95801a72d9a86b2722b5a04506f1a8dd58`), `vp90-2-09-lf_deltas.webm` (`651fc818fea9687fb1acccac35433c555cf005d2a78d39d5168d40760fd23fa1`), `vp90-2-15-segkey_adpq.webm` (`c402502113c173ce4ba827fa50e7f1c4cc657ad0c0893ee550c4ca82f497355b`), `vp90-2-19-skip.webm` (`7aa1de5c86fdb89fbd7443b79ef412771e29ca996f7ba2ea8f13375e37683bdd`), `vp90-2-19-skip-01.webm` (`c7b08efe2da0e5206ef34ea8f214331c0d0d3a010f0f5f24bf5986f939f51b3d`), `vp90-2-19-skip-02.webm` (`93b163cec04230291cb4bb8691e8ad0fabb051d2151708dd3185bb36719d9325`), `vp90-2-22-svc_1280x720_3.ivf` (`41f2ac2086be31e4cf39bad75612ebfd5a3d5445b4328f064ec4f2996d286666`) | rkvdec-vp9 / vp9-conf conformance (224/305 to 230/305); the 7 named vectors for root-causing |
| Synthetic clips (H.264, HEVC, VP8, VP9, AV1, JPEG, raw NV12/I420/YUY2) | generated locally with ffmpeg `testsrc2`/`mandelbrot` and GStreamer `videotestsrc` by the scripts in this repository | not stored | decode/encode throughput, parity and PSNR tests |
| MobileNet v1 quantised (uint8) | origin not recorded (TensorFlow hosted-models archive name `mobilenet_v1_1.0_224_quant.tgz`) | `.tgz` sha256 `d32432d28673a936b2d6281ab0600c71cf7226dfe4cdcef3012555f691744166`; `.tflite` sha256 `2d0ebfa2e75ae93c709e9ecc27570c9c0e49b7780733a840f82589fc1272fc3d` | NPU (rocket + Teflon) vs CPU classification |
| MobileNet v2 quantised (uint8), labels, test images | origin not recorded ("Coral" models per the work notes) | `mobilenet_v2_1.0_224_quant.tflite` `7aad0c74c5e3c06e5eb3c827e13304fdd68a83da6087d92ee169c24ff9fd4776`; `imagenet_labels.txt` `b8aaeb5630c62626a7d124a05c0e14230a7ffdd2136a31d0190a4fb71c1d82f1`; `grace_hopper.bmp` `c43444bf3b1b1e3080551ca194bd231da4b67f20fc91454502915a6b806b614f`; `cat.bmp` `34f235786382686111728287fd26d4c24dd8c25de8233469d6eeb301888ce0a9`; `parrot.jpg` `a8fba9e7e29439fa414c13129aad661f2289ff891231920a7c33641b076f1833` | same |
| Python wheels for the NPU test venv | https://pypi.org/ | `ai_edge_litert` 2.3.0 (cp314, aarch64), `numpy` 2.5.4, `pillow` 13.0.0, `ml_dtypes` 0.6.0, `protobuf` 7.36.2, `flatbuffers` 25.12.19, `tqdm` 4.70.1, `typing_extensions` 4.16.0, `backports_strenum` 1.2.8 | Offline install of the LiteRT runtime on the board |
| Ubuntu 26.10 media packages | http://ports.ubuntu.com/ubuntu-ports (suite `stonking`) | `gstreamer1.0-plugins-bad` 1.28.6-1ubuntu1, `gstreamer1.0-plugins-extra` 1.28.6-1ubuntu1, `libavcodec62` 8.1.2-2ubuntu2 (arm64), and the suite's `Packages` indexes | Inspected on the host (purpose not recorded in the work notes) |

## Vendor-derived content in this repository's kernel patches

Some kernel patches here are our own drivers, but take hardware facts or ported code from the GPL
vendor sources above. Their commit messages record the provenance:

- IEP2 deinterlacer (`opi5/iep2-7.3`): register map, programming sequence and defaults ported from
  BSP `mpp_iep2.c` / `rockchip_iep2_regs.h` (GPL-2.0+ OR MIT); MPP tuning values used as data.
- VEPU121 H.264 encoder (`opi5/vepu121-h264enc`): register programming and mode-decision tables
  ported from ChromeOS `rk3399_vpu_hw_h264e.c` (GPL-2.0).
- VEPU580 stateless encoder (`opi5/rkvenc-7.3`, `opi5/rkvenc-hevc-7.3`): register meanings and
  tuning from MPP (Apache-2.0, data only); reset and recovery sequences follow BSP `mpp_rkvenc2`.
- VDPU720 JPEG decoder (`opi5/rkjpegd-7.3`): independent implementation from MPP and BSP hardware
  facts, no code copied.
- Orange Pi 10.1" LCD (`opi5/dsi-7.3`): panel init table and timings from the Orange Pi BSP panel
  driver (GPL-2.0+).
- `opi5/vepu580` is different: it is the vendor MPP-service driver itself (a port of the Rockchip
  BSP code, vendor uAPI). It is experimental, not in `patches/linux`, and not for upstream.
