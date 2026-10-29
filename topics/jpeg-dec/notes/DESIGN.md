# C3: hardware JPEG/MJPEG decode on RK3588: design decision

Branch `opi5/jpeg-dec` (base `opi5/base` = c339f4010).

## 1. What the hardware has

| Block | Address (RK3588) | BSP compatible | Mainline | JPEG decode? |
|---|---|---|---|---|
| VPU121 / **VDPU2** decoder (+ VEPU2) | `0xfdb50000` (dec regs at +0x400), IRQ 119 | `rockchip,vpu-decoder-v2` (mpp_vdpu2.c) | `hantro`, `rockchip,rk3588-vpu121` → `rk3568_vpu_variant` | Yes in silicon (VDPU2 JPEG + PP), **not wired up** in hantro |
| **VDPU720 "rkjpegd"** dedicated JPEG decoder | `0xfdb90000` (0x400), IRQ 129; IOMMU at `0xfdb90480`, IRQ 130 | `rockchip,rkv-jpeg-decoder-v1` (mpp_jpgdec.c) | **nothing** (no binding, no node, no driver) | Yes, this is its only job |
| VEPU121 ×4 | `0xfdba0000`, +0x4000 ... | `rockchip,vpu-jpege-core` | `hantro` `rockchip,rk3588-vepu121` | encode only |

Sources: `_downloads/jpeg-dec/rk3588s.dtsi` (rockchip-linux/kernel develop-6.1),
`mpp_jpgdec.c`, `mpp_vdpu2.c`, and the userspace MPP library (`_downloads/jpeg-dec/mpp/`).

Two corrections to the task framing:

* The RK3588 `vpu121` decoder is **not a G1/VDPU1-style core**. Mainline drives it with
  `rk3568_vpu_variant`, which uses the `rockchip_vpu2_*` (VDPU2) register layout.
  The `G1_REG_*` JPEG bits in `hantro_g1_regs.h` don't apply to it. Option (a) would therefore mean
  VDPU2 JPEG decode (RK3399/RK3568/PX30/RK3588 class), plus separately G1 JPEG for RK3288/i.MX8M if
  anyone wanted it.
* Rockchip's own stack (MPP `osal/mpp_soc.c`, RK3588 entry) lists `&rkjpegd` before `&vdpu2` and
  sets `HAVE_JPEG_DEC`, so **on RK3588 the vendor routes all JPEG/MJPEG decode to the dedicated
  VDPU720 block**. VDPU2 JPEG is only the fallback on SoCs without rkjpegd.

### The BSP kernel driver is a register pass-through

`mpp_jpgdec.c` doesn't know the JPEG format. Userspace MPP (`hal_jpegd_rkv.c`,
`hal_jpegd_rkv_reg.h`, `hal_jpegd_vpu7xx_com.c`) parses the headers, builds the quantisation and
Huffman tables in a DMA buffer, and passes all 42 registers through an ioctl. The kernel only
adds IOMMU address translation, start, IRQ, soft or hard reset, and clocks. So the register
semantics for a mainline driver have to come from the **MPP userspace HAL**. That code is
**Apache-2.0**, which is not GPL-2.0-compatible, so none of it can be copied. The new driver
is an independent implementation that uses only the register map and table layout (facts about
the hardware) learned from it, with provenance recorded in the commit message. The BSP kernel file
(GPL-2.0+ OR MIT) gives the reset and IRQ handling (IRQ status bits, soft-reset sequence,
`FORCE_SOFTRESET_VALID`), which this driver also reimplements rather than copies.

VDPU720 capabilities, from the HAL:
* Baseline (SOF0) 8-bit Huffman. MPP also programs `pixel_depth`=12-bit for the newer VPU730, but
  not on RK3588. No progressive, no arithmetic coding.
* Input subsampling 4:0:0, 4:1:1, 4:2:0, 4:2:2, 4:4:0, 4:4:4. Restart intervals (DRI) in hardware.
* Output: native semi-planar layout (NV12/NV16/NV24/GREY-like) or conversion to NV12, YUYV,
  RGB888 or RGB565 (RK3588: RGB565 BE only). Also 1/2, 1/4, 1/8 scale-down, plus a tiled and an FBC
  output mode.
* 16-bit `width-1`/`height-1` fields, so up to 65536×65536. Collabora's tracking issue quotes about
  560 Mpixel/s, which is above 4K60 MJPEG on one core.
* Own IOMMU and IRQ, separate from VPU121. JPEG decode doesn't contend with H.264/VP8/MPEG-2 on
  VPU121 or with the 4 VEPU121 encoders.

## 2. Prior art (lore and elsewhere)

* lore.kernel.org's search UI returns 403 for scripted access from this host, so the lore search
  went through a web search for `hantro jpeg decode`, `vdpu720`, `rkjpegd` and `rk3588 jpeg decoder`.
  Results:
  * **No hantro JPEG *decoder* was ever posted or merged.** Hantro and its rockchip-vpu predecessor
    only ever had the H1/VEPU2 JPEG *encoder* (RK3288/RK3399; Chen-Yu Tsai's 2021-22 encoder fixes;
    Nicolas Frattaroli's RK3568 VEPU series, 2022). During the 2024 "Add hantro g1 video decoder
    support for RK3588" review (Jianfeng Liu, v1–v7), a reviewer pointed out that the commit text
    called VDPU121 "the JPEG decoder" and that mainline has no JPEG decoder driver.
  * **No VDPU720/rkjpegd patch has been posted.** Collabora's RK3588 mainline tracker has an open issue
    ("rkdjpeg Hardware JPEG Decoder Driver", gitlab.collabora.com/hardware-enablement/rockchip-3588/linux
    issue 20). It notes that the block is VDPU720 in the TRM, is also present on RK3566/RK3568, and raises
    the open question of "abusing the stateful JPEG V4L2 interface for yet another stateless JPEG
    decoder". That page is behind a bot wall, so this summary comes from search snippets. Pine64's
    "Mainline Hardware Decoding" page also lists it as unsupported.
* The relevant mainline precedent: every JPEG decoder in tree whose hardware is really "stateless" (the
  host parses the headers) exposes the **stateful** `V4L2_PIX_FMT_JPEG` m2m interface and parses the
  headers in the kernel: `mediatek/jpeg` (custom parser), `nxp/imx-jpeg` and `coda-jpeg`
  (`v4l2_jpeg_parse_header()`), `s5p-jpeg`. There's no stateless JPEG uAPI, and upstream has
  repeatedly said a JPEG header is simple enough to parse in the kernel.

## 3. Options

### (a) JPEG decode in hantro for VDPU2 (RK3588 vpu121)
* Hantro is built around *stateless* decoders (request API, per-codec controls) plus one stateful-ish
  JPEG *encoder*. A JPEG decoder needs a different format negotiation path (JPEG on OUTPUT,
  capture format and size coming from the bitstream, SOURCE_CHANGE events, DEC_CMD_STOP draining).
  That touches `hantro_v4l2.c`/`hantro_drv.c` for every SoC, and the maintainers would have to accept
  a third kind of context inside hantro. The regression risk for i.MX8M, SAMA5, sunxi and STM32 is real.
* VDPU2 JPEG register programming is documented in the public RK3399 TRM and in MPP
  `hal_jpegd_vdpu2.c` (Apache-2.0 again). Its PP pipeline would be needed for NV12 output of 4:2:2
  sources.
* On RK3588 it shares the single VPU121 core with H.264/VP8/MPEG-2 decode, and it isn't what the
  vendor stack uses there.
* Benefit: the same code could serve RK3399/RK3568/PX30 boards.
* Effort: medium-high (framework changes plus a new codec). Upstream likelihood: uncertain.

### (b) New driver for the dedicated VDPU720 block ✔ chosen
* A self-contained ~1k-line m2m driver with a new binding and DT node. It changes no existing
  behaviour on any SoC.
* The hardware is simpler than VDPU2 JPEG: one register file, one table buffer, no PP coupling,
  and restart markers handled in hardware.
* It's the block Rockchip uses on RK3588, it's faster, and it doesn't steal VPU121 time. The same IP
  is in RK3566/RK3568/RK3528/RK3562 (VPU720 variants), so a later `rockchip,rk3568-jpeg-decoder`
  compatible is cheap. RK3576's VPU730 has a different start/IRQ register layout and would need a
  variant struct.
* Follows the established mainline pattern: stateful JPEG decoder plus `v4l2_jpeg_parse_header()`,
  as in mtk-jpeg and imx-jpeg.
* Risks: no public register documentation beyond the RK3588 TRM Part 2 (if it covers VDPU720),
  and everything has to be validated on hardware because the board isn't here yet.
* Effort: medium. Upstream likelihood: good once it's tested. The SoC block has no driver at all
  today, and the reviewers' main question (stateful API for stateless HW) has an established answer.

**Decision: (b).** Option (a) stays as a possible follow-up for RK3399/RK3568-class boards without
rkjpegd (RK3568 does have rkjpegd, so the real beneficiaries would be RK3399/RK3288/PX30).

## 4. Driver design (`drivers/media/platform/rockchip/rkjpegd/`)

* **Name / compatible**: `rockchip,rk3588-jpeg-decoder` (binding
  `Documentation/devicetree/bindings/media/rockchip,rk3588-jpeg-decoder.yaml`). Module
  `rockchip-jpegd`, Kconfig `VIDEO_ROCKCHIP_JPEGD`. It's a single node with `aclk`/`hclk`, the
  `axi`/`ahb` resets, `iommus` and `power-domains = <&power RK3588_PD_VDPU>`. The IOMMU node at
  `0xfdb90480` uses the existing `rockchip,rk3588-iommu` driver.
* **uAPI**: single-device m2m, MPLANE API, stateful decoder per `dev-decoder.rst`:
  * OUTPUT: `V4L2_PIX_FMT_JPEG`, 1 plane.
  * CAPTURE (1 plane, contiguous; hardware places chroma at `y_virstride` after luma):
    * 4:2:0 → `NV12`
    * 4:2:2 → `NV16` (native) or `NV12` (hardware down-conversion)
    * 4:4:4 → `NV24` (native) or `NV12`
    * grey → `GREY`
    * 4:1:1, 4:4:0 → rejected. 4:4:0 isn't accepted by `v4l2_jpeg_parse_header()`, and 4:1:1 has no
      matching V4L2 semi-planar fourcc. NV12 conversion of 4:1:1 is plausible but unverified.
  * Headers are parsed in `buf_prepare` of the OUTPUT queue with `v4l2_jpeg_parse_header()`.
    Progressive, lossless, arithmetic and 12-bit streams are rejected there, so the buffer comes back
    with `VB2_BUF_STATE_ERROR` and no hardware access. So are 4-component, >3 quant-table and
    malformed streams.
  * The first parsed header (or a change in size or subsampling) sends `V4L2_EVENT_SOURCE_CHANGE`
    (RESOLUTION) and stalls `job_ready` until CAPTURE is reconfigured (STREAMOFF/ON). This is the
    mtk-jpeg scheme, which GStreamer `v4l2jpegdec` and FFmpeg `mjpeg_v4l2m2m` already handle.
    If the capture format is already compatible (same fourcc family, big enough buffers), it decodes
    straight away, which matters for MJPEG streams where every frame repeats the same header.
  * `V4L2_DEC_CMD_STOP`/`START` via the m2m draining helpers. The last buffer gets
    `V4L2_BUF_FLAG_LAST`.
  * Missing DHT (typical of UVC MJPEG) → the standard Annex K tables (`v4l2_jpeg_ref_table_*`).
* **Per-frame programming** (all derived from the header):
  * Register 1 (INT/control) gets `dec_e | timeout_e | buf_empty_e`, written last with `START`.
  * `sys` (reg 2): output conversion, `fill_down`/`fill_right`, all endian/swap off.
  * `pic_size`, `pic_fmt` (jpeg_mode, qtables_sel, htables_sel, DRI), strides, table lengths,
    stream length and start byte, table base addresses (one 1280-byte coherent buffer per device),
    stream base (16-byte aligned, offset of the entropy-coded segment), output base, and error
    handling: `error_prc_mode=1`, skip stray `0xFFFF` and other markers, as MPP does.
  * Quant tables: per component, de-zigzagged, 64 × u16. Huffman tables: per table, 16 × u16
    "mincode" plus 8 × u16 packed cumulative counts (DC then AC), with a 192-byte value array (DC
    values at 0, AC values at 16). The construction is reimplemented from the JPEG BITS arrays.
* **IRQ / errors**: threaded-free hard IRQ. `IRQ_RAW` must be set, otherwise `IRQ_NONE`. Success is
  `dec_irq && rdy_sta` with none of `bus|error|timeout|buf_empty` set. On error the buffer is marked
  `ERROR` and the core gets soft-reset (`FORCE_SOFTRESET_VALID` + `SOFT_RST_EN`, then poll
  `SOFT_RST_RDY`), falling back to the CRU resets. The core is also soft-reset after a frame when
  `SOFT_RST_RDY` is clear, as the BSP does for pre-VPU720 IDs. A 1 s delayed-work watchdog does the
  same if no IRQ arrives.
* **PM**: runtime PM with autosuspend (100 ms), using clk_bulk. The IOMMU follows the device via
  device links.

## 5. Not done / follow-ups
* RGB888/RGB565 and YUYV output conversion, scale-down (could be exposed via `S_SELECTION` compose
  later), 4:1:1/4:4:0.
* RK3568/RK3566 compatible and node (same IP, needs a board to test).
* hantro VDPU2 JPEG (option a) for SoCs without rkjpegd.
