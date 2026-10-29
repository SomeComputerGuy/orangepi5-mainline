# RK3588 IEP2 V4L2 mem2mem deinterlacer: design

Item C2. Branch `opi5/iep2`, worktree `~/orangepi5/work/iep2`.
Written before coding. Section 9 lists the changes made during implementation.

## 1. Prior art

| Source | What it is | Use |
|---|---|---|
| Mainline (`opi5/base`, c339f4010) | No IEP driver, binding or DT node for any Rockchip SoC | – |
| lore.kernel.org | Not reachable from this host: the lore search pages return HTTP 403 to the fetch tools. Web searches (linux-media/linux-rockchip mirrors, ratatoskr.run, patchew, lkml.iu.edu) found **no** posted IEP2 V4L2 series for RK3568 or RK3588. The user should re-check by hand with `https://lore.kernel.org/all/?q=s%3Aiep+rockchip` and `?q=iep2`. | Open question U1 |
| `armbian/build` `patch/kernel/archive/rockchip64-5.14/add-rockchip-iep-driver.patch` (Alex Bee / LibreELEC, carried by Paolo Sabatino) | V4L2 m2m driver for **IEP v1** (`rockchip,rk3228-iep`: RK3228/RK3288/RK3328/RK3399). Its register map is unrelated to IEP2. | Structure reference only |
| `rockchip-linux/kernel` `develop-6.1` `drivers/video/rockchip/mpp/mpp_iep2.c` + `rockchip_iep2_regs.h` (GPL-2.0+ OR MIT, Ding Wei / Alpha Lin) | BSP MPP-service backend. Userspace sends a struct of register values and the backend writes them. | **Register map and programming sequence ported from here** |
| `rockchip-linux/mpp` `mpp/vproc/iep2/iep2.c`, `mpp/vproc/mpp_dec_vproc.c` (Apache-2.0) | Userspace side: default tuning values, which mode to use when, frame/field order and output order | Only numeric defaults and behaviour are reused. No code is copied, because Apache-2.0 is not GPL-2.0 compatible. |
| `drivers/media/platform/sunxi/sun8i-di` (mainline) | Allwinner m2m deinterlacer. Keeps the previous buffer, emits 2 capture buffers per output buffer, uses INTERLACED_{TB,BT} on OUTPUT. | Model for the V4L2 semantics |
| `yisding/rock-5b-ysp` (GitHub) | Forward port of the MPP IEP2 service, not V4L2 | Not used |

Downloads are in `~/orangepi5/work/_downloads/iep2/`.

## 2. Hardware facts (RK3588)

From BSP `rk3588s.dtsi` (develop-6.1, node `iep: iep@fdbb0000`), cross-checked against mainline:

| Item | BSP | Mainline equivalent |
|---|---|---|
| Base / size | `0xfdbb0000`, `0x500` | Free in `rk3588-base.dtsi` (between `vepu121_3_mmu@fdbac800` and `vdec0@fdc38000`) |
| IOMMU | `iommu@fdbb0800`, size `0x100`, `rockchip,iommu-v2` | `"rockchip,rk3588-iommu", "rockchip,rk3568-iommu"` |
| IRQ | GIC SPI 117, level high, **shared by IEP and its IOMMU** | `<GIC_SPI 117 IRQ_TYPE_LEVEL_HIGH 0>` (4 cells, as in mainline). rockchip-iommu already requests with `IRQF_SHARED`; RGA3 nodes use the same pattern |
| Clocks | `ACLK_IEP2P0`, `HCLK_IEP2P0`, `CLK_IEP2P0_CORE` ("aclk", "hclk", "sclk") | IDs 411, 410, 412 in `rockchip,rk3588-cru.h`. In `clk-rk3588.c`, `aclk_iep2p0` gates `aclk_vdpu_low_pre`, `hclk_iep2p0` gates `hclk_vdpu_root`, and `clk_iep2p0_core` is a gpll/cpll composite |
| Assigned rate | BSP: `ACLK_IEP2P0` = 594 MHz | Not assigned in mainline. The parent `aclk_vdpu_low_root` is shared by the whole VDPU group, so the driver must not set it. Open question U5 |
| Resets | `SRST_A_IEP2P0` (366), `SRST_H_IEP2P0` (365), `SRST_IEP2P0_CORE` (367) | Present in `rst-rk3588.c` (CRU softrst con 45, bits 4–6) |
| Power domain | `RK3588_PD_VDPU` | Mainline `pd_vdpu` already lists `ACLK_IEP2P0`/`HCLK_IEP2P0` and `qos_iep` |
| RK3568 (BSP 5.10) | `0xfdef0000`, SPI 56, `PD_RGA`, same register block | Binding covers it; no RK3568 DT node in this series |

### Register block (BSP `rockchip_iep2_regs.h`)
- `0x000` FRM_START, `0x004` CONFIG0 (src/dst format and swap, soft resets), `0x008` WORK_MODE (bit 0 = IEP2 mode),
  `0x014` STATUS (bit 0 = ARST_FINISH_DONE), `0x020`/`0x024`/`0x028` INT_EN/CLR/STS
  (bit 0 frame done, bit 1 OSD max, bit 4 bus error, bit 5 timeout).
- `0x030` source strides (Y and UV, in **32-bit words**), `0x034` destination stride (words), `0x038` size
  (width−1, height−1, 11 bits each).
- `0x040` DIL_CONFIG0: mode[3:0], out_mode[4] (line/tile), field_order[5] (0 = TFF), feature enables [17:8].
- `0x060..0x08c` source addresses (cur/nxt/prv × Y/UV/V), MD, MV, ROI; `0x0b0..0x0c4` destination top/bottom Y/C, MD, MV.
- `0x0e0..0x17c` algorithm parameters (MD, detection, OSD, ME, EEDI, BLE, comb, motion table).
- `0x400..0x4ff` read-only statistics: pull-down and field-order counters, OSD areas, MV histogram.

### Formats
`src_fmt`/`dst_fmt` take 2 = YUV 4:2:2 and 3 = YUV 4:2:0. Swap takes 0 = SP UV, 1 = SP VU, 2/3 = planar.
The destination has only Y and C address registers, so **it is semi-planar only**.
**No 10-bit format exists** in the BSP or in MPP (values 0/1 are undocumented), so NV12 10-bit
(NV15/P010) is not supported.

### Size limits
Processing works on 16×4 tiles. MPP limits the source to `tile_cols ≤ 120` (1920 px) and
`tile_rows ≤ 480`, and allocates the motion-detection (MD) buffer as 1920×1088 bytes.
Driver limits: width 32..1920 in steps of 16, height 16..1088 in steps of 4.

### Modes (`DIL_MODE`)
| Value | BSP name | Meaning | Used by MPP | This driver |
|---|---|---|---|---|
| 1 | I5O2 | Motion-adaptive with MEMC, 5 fields in, 2 frames out (top-based in dst top, bottom-based in dst bot) | yes (MPP "I4O2") | MA, field rate |
| 2 / 3 | I5O1T / I5O1B | Motion-adaptive, 1 frame out from the top or bottom field | no | MA, frame rate |
| 4 | I2O2 | Intra-field (bob), 2 frames out | no | Bob, field rate |
| 5 / 6 | I1O1T / I1O1B | Intra-field (bob) from the top or bottom field | yes (MPP "I2O1": first frame) | Bob, frame rate; also MA for the first frame |
| 7 | PD | Pull-down (inverse telecine) recombination | yes | not used (future work) |
| 8 | BYPASS | copy | no | progressive (`V4L2_FIELD_NONE`) buffers |
| 9 | DECT | detection only | yes | not used |

Source inputs: `cur` is the frame being deinterlaced, `nxt` the following frame and `prv` the preceding one
(`mpp_dec_vproc.c`: SRC = prev_frm0, SRC1 = new frame, SRC2 = prev_frm1).

## 3. V4L2 interface

- `/dev/videoN`, `V4L2_CAP_VIDEO_M2M_MPLANE | V4L2_CAP_STREAMING`, driver name `rockchip-iep`.
- **OUTPUT** (interlaced frames in): NV12, NV21, NV16, NV61, each as one memory plane (both fields
  interleaved line by line). `field` is `V4L2_FIELD_INTERLACED_TB`, `_BT` or `_INTERLACED`
  (`INTERLACED` is treated as top-field-first, and anything else is coerced to `INTERLACED`).
  A per-buffer `field` set at QBUF overrides the format's field (`buf_out_validate`). `V4L2_FIELD_NONE`
  marks a progressive frame (soft-telecined MPEG-2), which is copied through in bypass mode.
- **CAPTURE** (progressive frames out): same pixel format as OUTPUT (the format is propagated, and
  4:2:2→4:2:0 conversion is not offered while it is untested). `field` is always `V4L2_FIELD_NONE`.
  Size equals OUTPUT size.
- `bytesperline` may be raised by userspace, for example to import decoder buffers with padded
  strides. It is rounded up to 16 and is ≤ 0x3fffc.
- `V4L2_BUF_FLAG_TIMESTAMP_COPY`. Sequence numbers are maintained on both queues.
- Colorimetry is propagated from OUTPUT to CAPTURE.

### Controls (driver-private, base `V4L2_CID_USER_ROCKCHIP_IEP_BASE = V4L2_CID_USER_BASE + 0x1260`)
| Control | Type | Default | Meaning |
|---|---|---|---|
| `V4L2_CID_ROCKCHIP_IEP_DEINT_MODE` | menu {Bob, Motion adaptive} | Motion adaptive | Algorithm |
| `V4L2_CID_ROCKCHIP_IEP_FIELD_RATE` | bool | 0 | 0: one progressive frame per input frame. 1: one per field (doubled rate, 50i→50p), so each job consumes 2 CAPTURE buffers |

The UAPI is an open question for review (U7). The alternative is a generic "deinterlacing mode"
control in the image-processing class, which sun8i-di and imx VDIC could also use.

## 4. Job model

The design follows sun8i-di:

- `job_ready`: 1 OUTPUT buffer and (FIELD_RATE ? 2 : 1) CAPTURE buffers.
- `device_run`: takes `src = next_src`. The previous source frame is held in `ctx->prev`, which is not
  returned to userspace until the following job completes, so the hardware can read it as `prv`.
  `cur = src`, `nxt = src` (**zero-latency** variant, see the rationale below), `prv = ctx->prev ?: src`.
  - Bob, frame rate: I1O1T (TFF) or I1O1B (BFF). dst top = dst bot = capture buffer.
  - Bob, field rate: I2O2. dst top/bot go to capture buffers [0]/[1] in temporal order (TFF: top first).
  - MA, frame rate: I5O1T/I5O1B for the first field. With no `prev` yet (first frame after STREAMON), I1O1x.
  - MA, field rate: I5O2. With no `prev`, I2O2.
  - Progressive buffer (`FIELD_NONE`): BYPASS into one capture buffer. In field-rate mode only one
    capture buffer is consumed.
- IRQ: read and clear status, return the capture buffers (DONE, or ERROR on bus error or timeout).
  Release `ctx->prev`, keep `src` as the new `prev`, then `v4l2_m2m_job_finish`.
- Timestamps: capture[0] copies the source metadata. In field-rate mode capture[1] gets
  `ts + (ts − prev_ts) / 2` (half a frame period), or `ts` when that is unknown.
- STREAMOFF on OUTPUT returns `prev`. Context-private MD/MV DMA buffers are allocated at OUTPUT
  STREAMON and freed at STREAMOFF.

**Why zero latency:** GStreamer `v4l2convert` (v4l2transform) is a 1:1 synchronous
`GstBaseTransform`: it queues one input and blocks until one output is ready. Waiting for the next frame
(true `nxt`, as in MPP) would deadlock it on the first frame and would need a drain (`V4L2_DEC_CMD_STOP`)
protocol for the last frame. In I5O1T for TFF, the first-field output mostly needs `prv` and `cur`. The
I5O2 second-field output loses its look-ahead field, which may cost quality on motion. A latency-1
"true next" mode with drain support is future work (U3) and should be measured against `bwdif`.

## 5. Driver structure

`drivers/media/platform/rockchip/iep/`
- `iep.h`: device, context and format structs.
- `iep-regs.h`: register definitions (ported from BSP `rockchip_iep2_regs.h`, renamed `IEP2_*`).
- `iep.c`: platform driver, V4L2 m2m, vb2 (dma-contig, through the IOMMU), controls, register
  programming, IRQ, watchdog, runtime PM, reset.

Resources: `devm_platform_ioremap_resource`, `devm_clk_bulk_get_all`, `devm_reset_control_array_get_optional_exclusive`,
`platform_get_irq`, and `devm_request_irq(IRQF_SHARED)`. The handler returns `IRQ_NONE` when no job is
running, so registers are never touched while the device is suspended and the shared IOMMU IRQ is safe.
Runtime PM uses autosuspend (100 ms), clocks are enabled in `runtime_resume` and resume is done in
`device_run`. The watchdog is a 500 ms delayed work. Reset is soft first
(`CONFIG0.ACLK_SRESET_P`, poll `STATUS.ARST_FINISH_DONE`), with the CRU reset as fallback, followed by
an IOMMU re-attach using rkvdec's `empty_domain` trick.

Per-device buffer: ROI (120×272 bytes, zeroed, ROI disabled). Per-context buffers: MD (1920×1088 bytes)
and MV (120×480 bytes), `dma_alloc_attrs(DMA_ATTR_NO_KERNEL_MAPPING)`.

### Register sequence per job
Ported from BSP `iep2_config()`, `iep2_osd_cfg()`, `iep2_mtn_tab_cfg()`, `iep2_tru_list_cfg()`,
`iep2_comb_cfg()` and `iep2_run()`, with the parameter values that MPP `iep2_init()`/`iep2_set_param()` use:

```
CONFIG0      = SRC_FMT|SRC_SWAP|DST_FMT|DST_SWAP|DEBUG_DATA_EN
WORK_MODE    = IEP2_MODE
SRC_IMG_SIZE = (tiles_x*16-1) | (tiles_y*4-1)<<16
VIR_SRC      = ystride/4 | uvstride/4 << 16 ; VIR_DST = dstride/4
DIL_CONFIG0  = MV_HIST|COMB|BLE|EEDI|MEMC|OSD|PD|FF|MD_PRE (lambda<8) | order<<5 | LINE<<4 | mode
SRC cur/nxt/prv Y/UV (V=0), TIMEOUT_CFG = EN|0x3ffffff, MD/MV src=dst, ROI
DST top Y/C, bot Y/C
MD   theta=1 r=6 lambda=4 ; DECT resi=30 osd_area=0 gradh=gradv=60 ; OSD_LIMIT=0
OSD  pec_thr=(width*26)>>7 line_num=2 ; OSD_AREA_CONF[0..7]=0
ME   pena=5 bonus=10 similar_thr=4 similar_num_thr0=4 thr_offset=20 ; left=-28 right=27
EEDI thr0=12 ; BLE backtoma=1 ; COMB osd_vld=0xff t_thr=4 feature=16 cnt=0
MTN_TAB[16] = BSP default table ; MV_TRU_LIST[0..1] = 0 (no global MV)
INT_EN = FRM_DONE|OSD_MAX|BUS_ERROR|TIMEOUT ; FRM_START = 1
```

## 6. DT binding

`Documentation/devicetree/bindings/media/rockchip,rk3568-iep.yaml`:
- `compatible`: `rockchip,rk3568-iep`, or `rockchip,rk3588-iep` with `rockchip,rk3568-iep` as fallback.
  (`iep` follows the TRM block name. The IEP v1 compatibles that are not in mainline use SoC names
  rk3228/rk3328/rk3399, so they cannot clash.)
- `reg`, `interrupts`, `clocks` with `clock-names: [aclk, hclk, sclk]`, `resets` with
  `reset-names: [axi, ahb, core]` (RGA naming), `power-domains`, `iommus`.

## 7. Kconfig / MAINTAINERS

`VIDEO_ROCKCHIP_IEP` (tristate). Depends on `V4L_MEM2MEM_DRIVERS && VIDEO_DEV && (ARCH_ROCKCHIP || COMPILE_TEST)`
and selects `V4L2_MEM2MEM_DEV` and `VIDEOBUF2_DMA_CONTIG`. The MAINTAINERS entry is a placeholder
(`M:` left for the user to fill).

## 8. Out of scope for the RFC (follow-ups)
1. Pull-down detection (PD mode) and automatic field-order detection (BSP output counters `0x400..`, MPP `iep2_pd.c`/`iep2_ff.c`).
2. Global-MV feedback (`MV_TRU_LIST` from `mv_hist`, MPP `iep2_gmv.c`), OSD and ROI handling.
3. Latency-1 "true next frame" mode with drain.
4. Planar YUV420 input (swap = P), and 4:2:2↔4:2:0 conversion.
5. RK3568 DT node.

## 9. Changes made during implementation
- Interrupt-cell and node placement follow the mainline style (4-cell GIC specifier, `qos` already present).
- Rebased onto v7.3 (`opi5/iep2-7.3`, on top of `opi5/multicore-7.3`). The control base stays at
  `V4L2_CID_USER_BASE + 0x1260`: free in 7.3 (last is Mali-C55 at 0x1230), and 0x1250 is taken by IT6625 in 7.4.
- DT node name is `deinterlace@fdbb0000` (generic name, as on sun8i-h3), label `iep`; enabled by default like the
  other SoC-internal m2m blocks. No assigned clock rate (U5).
- IRQ ownership: a `busy` flag under `irq_lock` replaces the `v4l2_m2m_get_curr_priv()` check. It is set
  after runtime resume just before FRM_START and cleared by whoever completes the job (hard IRQ on a valid
  status, or the watchdog). The hard handler returns `IRQ_NONE` without any register access while not busy
  (curr_ctx is set before `device_run` resumes the device, and it doesn't cover the gap after remove).
  The watchdog masks and clears INT_EN/INT_CLR while it still owns the job, so a late completion cannot leave the
  shared level IRQ asserted and unhandled.
- The previous frame's timestamp is kept separately from `ctx->prev`, so field-rate output in bob mode also gets
  a correct second timestamp (`ctx->prev` is NULL in bob mode).
- Whether the source is kept as reference is decided per job (`job_keep_src`) instead of re-reading the control at
  completion; progressive (`FIELD_NONE`) buffers are not held.
- FIELD_RATE is grabbed while either queue streams (`v4l2_ctrl_grab`) so `job_ready()` and `device_run()`
  agree on the number of CAPTURE buffers; `device_run()` also falls back to frame rate defensively. The bogus
  `V4L2_CTRL_FLAG_UPDATE` flag was dropped.
- `V4L2_FIELD_NONE` is accepted in the OUTPUT format (progressive pass-through), so a progressive stream can be
  negotiated by GStreamer instead of being coerced to INTERLACED.
- Added `V4L2_CID_MIN_BUFFERS_FOR_OUTPUT` = 2 (one OUTPUT buffer is held as reference in MA mode).
- A default colorspace is filled in (REC709 above 576 lines, SMPTE170M otherwise) when userspace leaves it at DEFAULT.
- `remove()` cancels the watchdog before releasing the m2m device.
- MD/MV buffers use `dma_alloc_coherent()` (zeroed) rather than `DMA_ATTR_NO_KERNEL_MAPPING`.
- **Board findings (RK3588):**
  - The IEP reads past the end of the source buffer (I1O1T at least; the BSP has the same workaround). It retries a
    faulting read forever, so an IOMMU fault turns into an IRQ storm. OUTPUT `sizeimage` is now padded (debug param
    `src_tail`, 4096 for now), and the hard IRQ aborts a job after 4 shared interrupts without IEP status
    (mask, soft reset, fail the job).
  - `iommu_set_fault_handler()` cannot be used on the DMA-API default domain (cookie union), so the BSP's
    map-a-spare-page workaround is not possible.
  - v4l2-compliance forbids `V4L2_CID_MIN_BUFFERS_FOR_OUTPUT` on non-encoders, so `min_reqbufs_allocation = 2` on
    OUTPUT is used instead.
  - Zero-latency MA is not reliably better than bob (+1.4 dB at 576i, -1.7 dB at 1080i). At field rate its second
    field lacks look-ahead (-2..-4 dB), so the default is **bob**. U3 (latency-1 true-next mode) is needed for real
    MA quality.
  - GStreamer 1.28 v4l2transform keeps `interlace-mode` on the CAPTURE side, so `v4l2convert` cannot be used as a
    deinterlacer without a GStreamer change.
  - remove() suspends the device explicitly (devm runtime-PM disable would drop a pending autosuspend with the clocks on).
- See the commit messages and RESULTS.md for details.
