# Orange Pi 5 MIPI-CSI camera pipeline (VICAP + CSI-2 + D-PHY + rkisp2) on 7.3.0-opi5

Branch: `opi5/camera-7.3` (worktree `~/orangepi5/work/camera-7.3`), on top of `opi5/multicore-7.3`.

```
f384072b5 arm64: dts: rockchip: Add OV13850/OV13855 overlays for Orange Pi 5 CAM1
aa7e72e11 arm64: dts: rockchip: Add IMX219 camera overlay for Orange Pi 5 CAM1
625e97636 arm64: dts: rockchip: rk3588: Drop third ISP0 interrupt            (local fixup, squash into v3 5/5)
ca58b2af9 media: rkisp2: Fix missing HIST_BIG2 entry in stats block info table (local fixup, squash into v3 3/5)
bd7ecd476 arm64: dts: rockchip: add ISP nodes to rk3588                       (rkisp2 v3 5/5)
412bebf3d dt-bindings: media: Add rockchip rkisp2                             (rkisp2 v3 4/5)
fb57b7bcb media: rkisp2: Add statistics capture video node                    (rkisp2 v3 3/5)
e1231d87d media: rkisp2: Add parameters output video node                     (rkisp2 v3 2/5)
6e33ecb05 media: rockchip: rkisp2: Add rkisp2 driver                          (rkisp2 v3 1/5)
```

## 1. What's attached

**No camera module is attached to CAM1 or CAM3.** This was checked on hardware on 2026-10-29 at 13:10.
The coordinator booted `detect/board-sata-cam-detect.dtb` (the installed board DTB plus the detection overlay):

- `imx219 7-0010`, `7-0036` (CAM1) and `2-0010`, `2-0036` (CAM3) all returned
  `Error reading reg 0x0000: -6` / `failed to read chip id 219` (NACK).
- The overlay took effect as intended. i2c7 was up on the m0 pins and GPIO1_D6/D7 were muxed to
  mipim0_camera3/4_clk with CLK_MIPI_CAMARAOUT_M3/M4 at 24 MHz. The cam1/cam3 reset and power-down GPIO
  regulators were claimed and switched on during the probes. So the NACKs mean no sensor is present at
  0x10/0x36. They don't point to a DT mistake.
- `i2cdetect -y -r 7` and `-r 2` after boot, with the camera lines off again: nothing apart from the
  rk8602 at i2c2 0x42.
- CAM2 (i2c7, DC-PHY0) wasn't probed: it shares the bus and addresses with CAM1, and it can't stream
  in mainline anyway (no DC-PHY RX).
- Before that, a read-only `i2cdetect -y -r` on buses 0/2/6 saw only the DT-described devices.

**Hardware tests stop here. A camera must be attached to go further** (§5b/5c).

- The OPi5 camera connectors (from the Xunlong vendor DT `rk3588s-orangepi-5-camera{1,2,3}.dtsi`;
  the schematic downloads in `_downloads/dp-altmode/schematic/` are Google Drive "quota exceeded"
  HTML pages, not PDFs):

  | Connector | I2C | MCLK | reset / power-down | PHY → CSI host → VICAP | Mainline 7.3 |
  |---|---|---|---|---|---|
  | CAM1 | i2c7 (M0) | CLK_MIPI_CAMARAOUT_M3, GPIO1_D6 | GPIO3_C4 / GPIO3_C6 | csi_dphy0 → csi2 (fdd30000) → vicap mipi2 | **supported** |
  | CAM2 | i2c7 (M0), same addresses | M4, GPIO1_D7 | GPIO1_B2 / GPIO3_C1 | mipi_dcphy0 → csi0 (fdd10000) | DC-PHY has no RX mode, no csi0 node |
  | CAM3 | i2c2 (shared with vdd_npu) | M4, GPIO1_D7 | GPIO1_A6 / GPIO3_C5 | mipi_dcphy1 → csi1 (fdd20000) | DC-PHY has no RX mode, no csi1 node |

- i2c7 isn't enabled in the board DT, and the sensors need MCLK plus released reset and power-down
  before they answer on I2C, so a plain i2cdetect can't see a module. That's why the detection
  overlay was needed.

## 2. What mainline 7.3 already has (no kernel rebuild needed for CAM1)

- VICAP: `rockchip,rk3588-vicap` in rkcif (`CONFIG_VIDEO_ROCKCHIP_CIF=m`), with MIPI capture,
  RAW8/10/12 Bayer and YUV.
- CSI-2 receiver: Synopsys `dw-mipi-csi2rx` with `rockchip,rk3588-mipi-csi2` →
  `rockchip,rk3568-mipi-csi2` fallback (`CONFIG_VIDEO_DW_MIPI_CSI2RX=m`).
- D-PHY: `phy-rockchip-inno-csidphy` has `rockchip,rk3588-csi-dphy` (`CONFIG_PHY_ROCKCHIP_INNO_CSIDPHY=m`).
- DT nodes in rk3588-base.dtsi: `vicap`, `vicap_mmu`, `csi2`/`csi4` (hosts 2 and 4, fed by
  `csi_dphy0`/`csi_dphy1`). Hosts 0, 1, 3 and 5 aren't described.
- **Missing:** DC-PHY camera (RX) mode in `phy-rockchip-samsung-dcphy` (TX/DSI only), and csi0/csi1
  nodes, so CAM2/CAM3 can't work in mainline. The upstream work for that isn't on the list yet as far as I know.
  Collabora's `mriesch/*/rk3588-vicap` branches (May 2025) are the predecessors of what's in mainline now,
  and their csi0/csi1 nodes there are `//phys = <&mipi_dcphy0>; // TODO`.
- Sensors: `imx219.ko`, `dw9714.ko` and the v4l2-isp helper are built and installed on the board.
  **OV13850 and OV13855, the official Xunlong modules, have no mainline driver or binding.** That needs a
  port of the vendor drivers (Rockchip BSP, GPL-2.0), a separate item.
- All needed symbols are already `=m` in the board config. No `=y` change is needed.

## 3. rkisp2 v3 port to 7.3

- `b4 am` mbox (`_downloads/rkisp2/am/v3_20260827_paul_elder_...mbx`) applied cleanly with `git am -3`.
  Authorship and `Link:` tags are kept. **No rework was needed for 7.3**: the series is based on 7.2-rc1 and
  7.3 doesn't have the 7.4 `v4l2_subdev_client_info` set_fmt argument, so that fix from the 7.4 branch
  wasn't carried.
- Carried fix: HIST_BIG2 stats block info (duplicate initializer, also on the 7.4 branch).
- New fix: **v3 5/5 gives isp0 three interrupts (SPI 131/133/134) while the binding allows two** and
  the driver uses only "isp_irq" and "mi_irq". dtbs_check flags it on every RK3588 board. I dropped SPI 134
  (the vendor "mipi_irq"). The `opi5/rkisp2` 7.4 branch has the same bug. Report this upstream for v4.
- The v3 driver is memory-to-memory only: VICAP writes raw frames to memory, and the ISP reads them back
  through the rawrd (dmarx) video nodes. Formats are compatible (RAW8/10/12 unpacked).
- Module: `modules/rockchip-isp2.ko`, built as an external module with `CONFIG_VIDEO_ROCKCHIP_ISP2=m` and
  signed with the board key (vermagic `7.3.0-opi5 ... modversions`).

## 4. Build and checks

- `kernelrelease` = 7.3.0-opi5; board `.config` unchanged after olddefconfig, apart from the new
  `VIDEO_ROCKCHIP_ISP2` symbol.
- rkisp2 at `W=1`: no warnings. Sparse isn't installed.
- `CHECK_DTBS=y` for rk3588s-orangepi-5{,-sata}.dtb and all composites: clean, except the expected
  "failed to match any schema" for `ovti,ov13850`/`ovti,ov13855` (no binding). Before the ISP0 fix, both
  board DTBs had the isp@fdcb0000 interrupts error.
- checkpatch --strict: the local commits are clean, apart from the missing SoB (intentional) and the
  MAINTAINERS note on new files. The upstream v3 patches have a few: 2/5 and 3/5 each have one
  "trailing statements" ERROR and an over-100-column uapi line, plus about 60 CHECKs across the series.
  Upstream code, left as is.
- Board composites, all dt-validate clean:
  - `detect/board-sata-cam-detect.dtb` = board DTB (built from `board-dt` HEAD~1 with `-@`; it matched the
    DTB installed at the time node-for-node) + `rk3588s-orangepi-5-cam-detect.dtbo`.
  - `test/board-sata-cam1-imx219.dtb` = same base + rkisp2 ISP nodes (+ fix) + CAM1 IMX219 overlay.
  - `test/board-sata-cam1-imx219.dtb` needs the rkisp2 ISP nodes in the base, so it has to be rebuilt
    from the then-current board DT plus `dt/0002`/`0003` before use. The coordinator can merge `dt/000[1-4]*.patch` into
    `opi5/board-dt` (they apply cleanly on its HEAD).

## 5. Test plan (needs a board slot and an attached camera)

### 5a. Detection boot (low risk: GPIO, clock and I2C reads only, nothing streams). Done on 2026-10-29, see §1

```sh
sudo cp /usr/lib/linux-image-7.3.0-opi5/rockchip/rk3588s-orangepi-5-sata.dtb ~/sata.dtb.orig
sudo cp board-sata-cam-detect.dtb /usr/lib/linux-image-7.3.0-opi5/rockchip/rk3588s-orangepi-5-sata.dtb
sudo reboot
dmesg | grep -i imx219        # per node 7-0010, 7-0036 (CAM1), 2-0010, 2-0036 (CAM3)
sudo i2cdetect -y -r 7
# restore ~/sata.dtb.orig and reboot
```

What the imx219 probe messages mean:
- `failed to read chip id 219`: nothing at that address.
- `chip id mismatch: 219!=xxxx`: a different sensor is there. On 0x10 that's likely the OV13850, on 0x36 the OV13855.
- probe OK: an IMX219 is there.

CAM2 isn't covered, because it shares i2c7 and the addresses with CAM1, and it can't stream in mainline anyway.

### 5b. IMX219 on CAM1: raw capture through VICAP (medium risk: first CSI streaming on this board)

Install `modules/rockchip-isp2.ko` in `/lib/modules/7.3.0-opi5/updates/` and run `depmod`. Boot
`test/board-sata-cam1-imx219.dtb`. Then:

```sh
media-ctl -d /dev/mediaN -p            # imx219 7-0010 -> dw-mipi-csi2rx fdd30000 -> rkcif mipi2 -> video node
media-ctl -d /dev/mediaN -V '"imx219 7-0010":0[fmt:SRGGB10_1X10/1920x1080]'   # and propagate to csi2/rkcif
v4l2-ctl -d /dev/videoX --set-fmt-video=width=1920,height=1080,pixelformat=RG10 \
         --stream-mmap --stream-count=60 --stream-to=/tmp/raw.bin
v4l2-compliance -d /dev/videoX ; v4l2-compliance -u /dev/v4l-subdevY   # csi2rx, sensor
dmesg  # must be clean: no CSI ERR1/ERR2 storms, no IOMMU faults
```

Pass: 60 frames of 1920x1080x2 bytes, a frame rate near 30 fps, a plausible Bayer image (convert offline),
and v4l2-compliance with 0 failures.

### 5c. ISP processed capture (rkisp2, memory-to-memory)

- Ubuntu has libcamera 0.7.0 (`libcamera-tools`, `gstreamer1.0-libcamera`), which **has no rkisp2
  pipeline handler**. That handler is out of tree (v2/v3 on the libcamera list, Aug 2026,
  https://patchwork.libcamera.org/cover/28011/) and has to be built from source on the board: libcamera
  master + the rkisp2 series, `meson setup -Dpipelines=rkisp2 -Dipas=rkisp2`. Then `cam -l`, `cam -c1 -C10 -F`.
- Without libcamera: feed a 5b raw frame to the ISP rawrd node with v4l2-ctl (`--stream-out-mmap`) and
  capture from the mainpath node. That gives only a basic check: no 3A, and default params.
- Risk: medium-high. This is the first run of an out-of-tree ISP driver on this board, and the IOMMU and
  power domains are shared with VICAP. If it faults: reboot, don't rmmod.

## 6. Upstream status

- rkisp2 v3: "media: rockchip: rkisp2: Add driver for ISP on RK3588", Paul Elder / Xu Hongfei, 2026-08-27,
  https://patch.msgid.link/20260827-rkisp2-v3-0-e91ff0a604d6@ideasonboard.com. Not merged, not in linux-next.
- libcamera rkisp2 pipeline handler: v2/v3 on the libcamera list. Not in a release.
- VICAP/CSI-2/D-PHY for RK3588 CSI hosts 2 and 4: mainline (7.3).
- DC-PHY RX and CSI hosts 0/1/3/5: not posted. OV13850/OV13855 drivers: not posted.

## 7. Next steps

1. Attach a camera (IMX219 for the mainline-only path, or the Xunlong OV13850/OV13855) and re-run 5a.
2. With an IMX219 on CAM1: 5b, then 5c with a self-built libcamera.
3. With the official OV13850/OV13855 module: port the sensor driver, the bigger missing piece.
   The overlays are ready, and the link frequencies and GPIO polarity need checking against the port.
4. CAM2/CAM3: DC-PHY RX support plus csi0/csi1 nodes.
5. Report the ISP0 interrupt mismatch and the HIST_BIG2 bug on the rkisp2 v3 thread (user's decision).
