# RK3588 VEPU580 (rkvenc v2) — register-level programming model

Groundwork for an upstream V4L2 **stateless** H.264/HEVC encoder driver.

Status: analysis only. No board access, no kernel changes. Date: 2026-10-29.

## Sources and confidence

| Tag | Source | How it was read |
|---|---|---|
| **K** | Out-of-tree MPP-service port, worktree `~/orangepi5/work/vepu580`, branch `opi5/vepu580` (HEAD `118aeb259`): `drivers/media/platform/rockchip/rkvenc/{rkvenc_hw.h,rkvenc_hw.c,rkvenc_task.c,rkvenc_service.c,rkvenc_drv.c,rkvenc_iommu.c}`, `include/uapi/linux/rkvenc.h`, uncommitted DT in `arch/arm64/boot/dts/rockchip/rk3588-base.dtsi`, untracked `Documentation/devicetree/bindings/media/rockchip,rkv-encoder-v2.yaml` | Read directly. File:line references are exact. |
| **M** | Rockchip MPP userspace, `github.com/rockchip-linux/mpp` branch `develop` (Apache-2.0): `mpp/hal/rkenc/common/vepu580_common.h`, `vepu5xx_common.c`, `vepu541_common.c`, `mpp/hal/rkenc/h264e/hal_h264e_vepu580.c`, `hal_h264e_vepu580_reg.h`, `mpp/hal/rkenc/h265e/hal_h265e_vepu580.c`, `mpp/hal/common/h264/hal_h264e_stream_amend.c`, `mpp/codec/enc/h264/h264e_api_v2.c`, `mpp/codec/rc/rc_model_v2.c` | Fetched as raw data via WebFetch. That tool returns a model-generated summary, not the file, so there are **no line numbers**. References name the function or struct. Struct and bitfield layouts that were quoted verbatim are marked **M(verbatim)**. |
| **R** | Pengutronix/Bootlin VC8000E stateless H.264 encoder RFC, 2025-05-02: cover letter `lists.openwall.net/linux-kernel/2025/05/02/1002`, uAPI patches `/1003` (01/11), `/1004` (02/11), `/1005` (03/11), `/1006` (04/11), driver `/1014` (11/11) | Fetched. uAPI structs were quoted verbatim. Only the first 100 KB of the driver patch was summarised. |
| **D** | `~/orangepi5/work/_downloads/vepu580/{rcawston,ceralive,ceralive-pre-island}` | Grepped. These are earlier copies of the same port plus board/QA notes. They add no programming-model information beyond K. |

**[UNVERIFIED]** marks inferences and anything not confirmed in source. Both the kernel port and MPP are vendor-derived. No Rockchip TRM chapter for VEPU580 was available.

Gaps: `vepu5xx_common.h` (numeric `VEPU5xx_FMT_*` codes), `h264e_sps.c`/`h264e_slice.c`/`mpp_bitwrite` (emulation-prevention details), the HEVC stream-amend file, and the second half of `hal_h265e_vepu580.c` (only partly read) were not fully seen. No TRM was available.

---

## 0. Summary of the facts that constrain a V4L2 design

1. **Hardware writes the slice header and NAL start code itself**, from `synt_*` registers. **Software writes SPS/PPS/VPS/SEI** into the output buffer first. The hardware then starts writing at byte offset `packet_length` (MPP: offset patch on reg 175 = `adr_bsbs`). For H.264 with long-term refs, more than one short-term ref config, or a POC-type / log2_max_frame_num mismatch, MPP **rewrites the slice header in software** after the encode (`hal_h264e_stream_amend.c`). For HEVC, MPP patches `nuh_temporal_id_plus1` in software.
2. **One reference picture per frame.** There is a single read port (`rfpr_h/b`, `dspr`, `cmvr`). No B-frames are used by MPP on 580. Recon and ref are a **proprietary FBC layout** (header + body), each with a ¼-resolution thumbnail buffer and, for HEVC, a collocated-MV buffer. They are internal-only and should be driver-allocated.
3. **Rate control is split.** The hardware does CTU/MB-row-level QP adaptation against a per-CTU bit target (`ctu_ebit`) using a 9-entry deviation→ΔQP LUT. Software does frame-level RC and sets frame QP, min/max QP, row ΔQP range and target bits. Feedback is a rich status block at `0x4000`: length, QP sum, SSE, MADI/MADP, block-type counts and a per-QP histogram.
4. **Two identical cores, each with its own IOMMU.** In MPP/BSP they share **one IOMMU domain** so any task can run on either core. The coupling is the "DCHS" dual-core handshake (`0x304`). MPP uses it for (a) **frame-parallel** encoding, where frame N+1 on core B reads frame N's recon while core A is still writing it, and (b) **HEVC tile-parallel** encoding of one frame split into tile columns. Without DCHS, the cores are just two independent encoders.
5. The kernel side of the vendor design is thin. It patches fd→IOVA with offsets, applies a few register fixups (split flush, DCHS IDs, SRAM RCB), uses a watchdog, does soft reset with CRU fallback, and schedules work on idle cores. Everything codec-related is in userspace.
6. **The port's IRQ-status and DCHS bit definitions disagree with MPP's register struct.** See §6.4. Check them against the BSP/TRM before reusing them.

---

## 1. Hardware blocks and per-core resources

### 1.1 Instances (K: `rk3588-base.dtsi` diff)

| | core 0 | core 1 |
|---|---|---|
| MMIO | `0xfdbd0000`, size `0x6000` | `0xfdbe0000`, size `0x6000` |
| IRQ | GIC SPI 101 | GIC SPI 104 |
| IOMMU | `0xfdbdf000` (+`0xfdbdf040`, two banks of 0x40), IRQs SPI 99/100, `rockchip,disable-mmu-reset` | `0xfdbef000` (+`0xfdbef040`), SPI 102/103 |
| Clocks | `ACLK_RKVENC0`, `HCLK_RKVENC0`, `CLK_RKVENC0_CORE` | `…RKVENC1…` |
| Rates (DT) | aclk 500 MHz, core 800 MHz (`assigned-clock-rates`, `rockchip,normal-rates`). Driver defaults: aclk 300 MHz, core 600 MHz (`rkvenc_hw.c:856-857`) | same |
| Resets | `SRST_A_RKVENC0`, `SRST_H_RKVENC0`, `SRST_RKVENC0_CORE` ("video_a/h/core") | `…RKVENC1…` |
| Power domain | `RK3588_PD_VENC0` | `RK3588_PD_VENC1` (parent of VENC1 is VENC0 in the RK3588 pmdomain tree **[UNVERIFIED]**) |
| SRAM RCB | optional `rockchip,rcb-iova` / `rockchip,sram`. **Not wired** in this DT (`rkvenc_drv.c:384-403`), so it runs without SRAM | same |

The service and CCU nodes (`rockchip,mpp-service`, `rockchip,rkv-encoder-v2-ccu`) have no registers. They are a software construct (binding yaml, "NOT FOR UPSTREAM"). The **CCU is not a hardware block**. In the port it is a container that (a) groups the cores, (b) holds the shared IOMMU domain (`rkvenc_drv.c:232-285`: the secondary core's IOMMU group is attached to the main core's domain), and (c) holds the DCHS ID allocation table (`struct rkvenc_ccu`, `rkvenc_hw.h:781-788`).

### 1.2 Register map (per core; K `rkvenc_hw.c:90-138`, M `vepu580_common.h` `VEPU580_*_OFFSET`)

| Class (K enum) | Range | MPP struct | Contents |
|---|---|---|---|
| BASE / CTL | `0x0000–0x0058` | `Vepu580CtlCommon` | version (`0x00`: sub_ver, hevc_cap, res_cap, osd_cap, **bfrm_cap**, fbc_cap, ip_id), `enc_strt` 0x10 (lkt_num[7:0], vepu_cmd[9:8]), `enc_clr` 0x14 (safe_clr, force_clr), `int_en/msk/clr/sta` 0x20/24/28/2c, `dtrns_map` 0x30 (per-port endian/order), `dtrns_cfg` 0x34, `enc_wdg` 0x38 (vs_load_thd[23:0], rfp_load_thd[31:24]), QoS 0x3c–0x4c, `enc_idle_en` 0x50, `func_en` 0x54 (cke, resetn_hw_en, enc_done_tmvp_en, sram_ckg_en), 0x58 rdo clock gating |
| PIC (frame) | `0x0280–0x03f4` | `Vepu580BaseCommon` + codec-specific tail | addresses 0x280–0x2dc, enc_pic, dual_core, resolution, source format/CSC/rotation/crop, RC base (0x350–0x358), slice split, ME, syntax registers (0x3b0–0x3dc), tile_pos 0x3f4 |
| RC (`RCKLUT`) | `0x1000–0x10e0` | `Vepu580RcKlut` | qp_adj LUT, deviation thresholds, ROI QP areas, AQ thresholds/steps, MADI/SAD thresholds, chroma KLUT weights |
| PAR | `0x1700–0x1cd4` | `Vepu580Section3` + `Vepu580WgtCommon` | intra cost thresholds/weights, quant bias (`RDO_QUANT` 0x1730), ATR (H.264 only), CIME/RIME/FME weights |
| SQI (RDO) | `0x2000–0x21e4` | `Vepu580RdoCfg` | RDO thresholds/weights per block size, smear thresholds, pre-intra |
| SCL | `0x2200–0x2c98` | `Vepu580SclCfg` | **scaling lists** (intra/inter 8x8 Y/U/V, 16/32 Q/IQ, DC). Not a scaler. |
| OSD | `0x3000–0x347c` | `Vepu580OsdReg` | 8 OSD regions (enable, positions, 8 buffer addresses at 0x3050–0x306c), 256-entry palette |
| ST (status) | `0x4000–0x42cc` | `Vepu580Status` | read-back results (§4.3) |
| DBG | `0x5000–0x5354` | `Vepu580Dbg` | per-stage timeouts, pipeline positions, cycle counters (0x5200+), AXI perf counters (0x5300+) |

The hardware register count is reported as 254 dwords in the "hw" header (`reg_num`), but the real span is about 0x5400. A V4L2 driver would write only the classes it needs.

#### 1.2.1 Frame-class address registers (M `Vepu580BaseCommon`; reg index = offset/4)

| Off | idx | Name | Meaning |
|---|---|---|---|
| 0x280 | 160 | `adr_src0` | source Y (or packed / FBC) |
| 0x284 | 161 | `adr_src1` | source Cb/CbCr (MPP: same fd + offset) |
| 0x288 | 162 | `adr_src2` | source Cr |
| 0x28c | 163 | `rfpw_h_addr` | recon write, FBC header |
| 0x290 | 164 | `rfpw_b_addr` | recon write, FBC body (= same buffer + `fbc_hdr_size`) |
| 0x294 | 165 | `rfpr_h_addr` | reference read, FBC header |
| 0x298 | 166 | `rfpr_b_addr` | reference read, FBC body |
| 0x29c | 167 | `cmvw_addr` | collocated MV write (HEVC TMVP) |
| 0x2a0 | 168 | `cmvr_addr` | collocated MV read |
| 0x2a4 | 169 | `dspw_addr` | ¼×¼ down-sampled recon ("thumb") write |
| 0x2a8 | 170 | `dspr_addr` | ¼×¼ down-sampled ref read (coarse ME) |
| 0x2ac | 171 | `meiw_addr` | motion-estimation info write (optional `md_info`, `enc_pic.mei_stor`) |
| 0x2b0 | 172 | `bsbt_addr` | bitstream buffer **top** (end). MPP: fd + (size-1) |
| 0x2b4 | 173 | `bsbb_addr` | bitstream buffer bottom (base) |
| 0x2b8 | 174 | `bsbr_addr` | bitstream ring read pointer |
| 0x2bc | 175 | `adr_bsbs` | bitstream **start** write address. MPP: fd + current packet length (headers already written) |
| 0x2c0 | 176 | `lpfw_addr` | loop-filter line buffer write (HEVC tiles: per-tile `hw_tile_buf[k]`) |
| 0x2c4 | 177 | `lpfr_addr` | loop-filter line buffer read (tile k-1) |
| 0x2c8 | 178 | `roi_addr` | ROI base config map |
| 0x2cc | 179 | `roi_qp_addr` | ROI QP map |
| 0x2d0 | 180 | `roi_amv_addr` | ROI AMV cfg |
| 0x2d4 | 181 | `roi_mv_addr` | ROI MV cfg |
| 0x2d8 | 182 | `ebuft_addr` | external line buffer top (width > 4096) |
| 0x2dc | 183 | `ebufb_addr` | external line buffer bottom. Target of SRAM RCB |

The port's fd-translation table for H.264/HEVC is exactly PIC-class indices 0–23, i.e. 0x280–0x2dc (`rkvenc_hw.c:31-41`). For OSD it is OSD-class indices 20–27, i.e. 0x3050–0x306c (`rkvenc_hw.c:48-54`).

#### 1.2.2 Frame-class control registers (M(verbatim) `vepu580_common.h`)

| Off | Name | Fields |
|---|---|---|
| 0x300 | `enc_pic` | enc_stnd[0] (0=H.264, 1=HEVC), roi_en[1], cur_frm_ref[2] (keep recon as reference), mei_stor[3], bs_scp[4] (**[UNVERIFIED]** start-code/emulation-prevention enable), pic_qp[13:8], num_pic_tot_cur[18:14] (HEVC NumPicTotalCurr), log2_ctu_num[23:19], slen_fifo[30], rec_fbc_dis[31] |
| 0x304 | `dual_core` | dchs_txid[1:0], dchs_rxid[3:2], dchs_txe[4], dchs_rxe[5], dchs_ofst[26:16] |
| 0x310 | `enc_rsl` | pic_wd8_m1[10:0], pic_hd8_m1[26:16] (units of 8 px, so the field maximum is 16384) |
| 0x314 | `src_fill` | pic_wfill[5:0], pic_hfill[21:16] (padding to 16 / CTU) |
| 0x318 | `src_fmt` | alpha_swap[0], rbuv_swap[1], src_cfmt[5:2], src_range[6], out_fmt[7] |
| 0x31c–0x328 | `src_udfy/u/v/o` | RGB→YUV CSC weights and offsets |
| 0x32c | `src_proc` | src_mirr[26], src_rot[28:27], txa_en[29], afbcd_en[30] (AFBC/FBC input) |
| 0x330 | `pic_ofst` | pic_ofst_x[13:0], pic_ofst_y[29:16] (crop origin) |
| 0x334/0x338 | `src_strd0/1` | luma stride [16:0], chroma stride [15:0] |
| 0x350 | `rc_cfg` | rc_en[0], aq_en[1], aq_mode[2], rc_ctu_num[31:12] (CTUs per RC row) |
| 0x354 | `rc_qp` | rc_qp_range[19:16], rc_max_qp[25:20], rc_min_qp[31:26] |
| 0x358 | `rc_tgt` | ctu_ebit[19:0] (target bits per CTU/MB, ×16) |
| 0x360 | `sli_splt` | sli_splt[0], sli_splt_mode[1] (byte vs CTU count), sli_splt_cpst[2], sli_flsh[15], sli_max_num_m1[30:16] |
| 0x364 / 0x368 | `sli_byte` / `sli_cnum` | split by bytes [19:0] / by CTU count-1 [19:0] |
| 0x370 | `me_rnge` | CME/RME search ranges, dlt_frm_num[31:16] |
| 0x374–0x380 | `me_cfg`, `me_cach`, `gmv` | PMV, mv_limit, colmv_stor/load, RME/FME disables, CME RAM sizing, global MV |
| 0x390 | `roi_en` | roi_qp_en, roi_amv_en, roi_mv_en |
| 0x3a0 | `rdo_cfg` | … vlc_lmt, atr_e, scl_lst_sel[…] |
| 0x3b0–0x3dc | `synt_*` | codec syntax (§2.4) |
| 0x3f0 | `sli_cfg` | mv_v_lmt, sli_crs_en (deblock across slices) |
| 0x3f4 | `tile_pos` | tile_x[7:0], tile_y[23:16] (HEVC). HEVC also has `reg0252_tile_cfg` with tile_w_m1/tile_h_m1/tile_en (offset not captured **[UNVERIFIED]**, likely 0x3f0) |

### 1.3 IRQ status (M(verbatim) `int_sta` 0x2c; `int_en/msk/clr` share the layout)

| Bit | MPP name | Meaning | Port's define (`rkvenc_hw.h:199-206`) |
|---|---|---|---|
| 0 | enc_done | frame done | `INT_STA_ENC_DONE_STA` BIT(0) — matches |
| 1 | lkt_node_done | link-table node done | port calls this **`SLC_DONE`** — mismatch |
| 2 | sclr_done | safe-clear done | port calls this **`BSF_OFLW`** — mismatch |
| 3 | slc_done | slice done (low-latency) | not defined in the port |
| 4 | bsf_oflw | bitstream buffer overflow | port uses it as **`RKVENC_SCLR_DONE_STA`** — mismatch |
| 5 | brsp_otsd | bus response outstanding error | port calls this **`WDG`** — mismatch |
| 6 | wbus_err | AXI write error | inside `INT_STA_ERROR` 0x3f0 |
| 7 | rbus_err | AXI read error | inside 0x3f0 |
| 8 | wdg | watchdog timeout | inside 0x3f0 |
| 9 | lkt_err | link-table error | inside 0x3f0 |

`hal_h264e_vepu580_status_check()` (M) decodes the same order. The port's error mask 0x3f0 (bits 4–9) agrees with MPP's error set (it contains bsf_oflw, so overflow counts as an error). Bits 0–5 are discussed in §6.4.

Link-table mode (`enc_strt.lkt_num`, `st_lkt`, `lkt_node_done`) is a hardware multi-frame command-list feature. Neither the port nor the MPP 580 HAL uses it **[UNVERIFIED for MPP]**.

### 1.4 Can the two cores encode independent frames, or split one frame?

| Mode | Mechanism | Who uses it |
|---|---|---|
| **Independent frames / sessions** | Both cores sit in one task queue. The worker picks `find_first_bit(core_idle)` (`rkvenc_service.c:1020-1050`). Because the IOMMU domain is shared, a task's IOVAs are valid on either core. | Port (default). Any number of sessions. |
| **Frame-parallel, one stream** | DCHS: core encoding frame N sets `dchs_txe` with a txid. Core encoding N+1 (whose reference is N's recon) sets `dchs_rxe` with `rxid = txid of the frame that produces its ref`. `dchs_ofst = 9` is the row lag (units **[UNVERIFIED]**: probably CTU/MB rows). TX is disabled for non-reference frames, RX for I frames. IDs wrap at 4 (2-bit fields). | MPP `setup_vepu580_dual_core()` (H.264 and HEVC) when `task_cnt > 1` (`MAX_TASK_CNT` / `MAX_FRAME_TASK_NUM` = 2). Port: `rkvenc2_patch_dchs()` (`rkvenc_hw.c:193-285`) re-maps the user txid/rxid to IDs free across both cores, and pairs rx with the tx of the same session. |
| **One frame split (HEVC tiles)** | Up to 4 uniform tiles (`MAX_TILE_NUM`). Each tile is its own register set with `tile_pos`, `tile_cfg` and `rc_ctu_num = tile width`. Neighbouring tiles exchange loop-filter lines through `lpfw/lpfr` (`hw_tile_buf[k]` / `[k-1]`), synchronised by DCHS with `dchs_ofst = 2` ("dual core runtime offset should set to 2 to avoid data access conflict"). Tiles after the first write into separate `hw_tile_stream[]` buffers, which userspace then **memcpy**s after tile 0. | MPP `hal_h265e_v580_set_uniform_tile()`, `hal_h265e_v580_start/ret_task`. Parallel only if the service supports `MPP_CMD_SET_SESSION_FD`+ (`tile_parall_en = cap->send_cmd > MPP_CMD_SET_SESSION_FD`). **The port does not implement `SET_SESSION_FD`** (`rkvenc_service.c:1114-1254`), so MPP falls back to serial per-tile SEND/POLL **[UNVERIFIED that the capability query returns that]**. |
| H.264 one-frame split | None. H.264 uses the external line buffer for width > 4096 instead of tiles. | — |

---

## 2. Per-frame inputs

### 2.1 Source picture

| Item | Register | Notes |
|---|---|---|
| Formats | `src_fmt.src_cfmt` via `vepu5xx_set_fmt()` (M `vepu5xx_common.c`) | **YUV:** NV12, NV21, I420 (YUV420P), NV16/NV61 (422SP), 422P, YUYV/YVYU, UYVY/VYUY, Y800 (YUV400), NV24 (444SP), 444P, AYUV (1/2 bpp variants). **RGB:** RGB565/BGR565, RGB888/BGR888, ARGB/ABGR/BGRA/RGBA8888, ARGB4444, ARGB1555. Hardware CSC converts to YUV with programmable BT.601/709, limited/full coefficients. **Not supported:** any 10-bit input (YUV420SP_10BIT etc. map to BUTT), 440, 411, RGB555/444/101010. |
| FBC/AFBC input | `src_proc.afbcd_en`, Y stride from `mpp_frame_get_fbc_hdr_stride()` | Rockchip FBC frames, e.g. from the RK3588 decoder or ISP **[UNVERIFIED which producers]** |
| Planes | `adr_src0/1/2`, same dma-buf + offsets (reg 161/162 offset patches) | YUV420P: U at w*h, V at w*h*5/4 (HEVC HAL) |
| Strides | `src_strd0` (17 bits), `src_strd1` (16 bits) | bytes |
| Size | `enc_rsl` = ALIGN(w,16)/8-1, ALIGN(h,16)/8-1, with fill = aligned minus real | H.264 aligns to 16. HEVC aligns to 8 in `enc_rsl`, with fill to the CTU **[UNVERIFIED]** |
| Crop | `pic_ofst_x/y` | Set in gen_regs from the frame offset |
| Rotation / mirror | `src_rot` (2 bits: 0/90/180/270 **[UNVERIFIED encoding]**), `src_mirr` | |
| Scaling | none | The SCL class is scaling *lists*. There is no downscaler apart from the internal ¼ thumb. |

### 2.2 Recon / reference buffers

Recon is **always FBC** in MPP (`rec_fbc_dis` = 0; the bit exists, `rkvenc_hw.h:197`). The header and body live in one buffer, and the hardware-internal format is undocumented.

| Buffer | H.264 (M `setup_hal_bufs`) | HEVC (M `vepu580_h265_setup_hal_bufs`) |
|---|---|---|
| geometry | `aw = ALIGN(w,64)`, `ah = ALIGN(h,16)+16` ("FBC data require extra 16 lines space for hardware io") | `cw = ceil(w/64)`, `ch = ceil(h/64)+1` (one extra CTU row) |
| FBC header | `ALIGN(aw*ah/64, 8K)` | `ALIGN(cw*ch*64, 8K)` |
| FBC body | `aw*ah*3/2` | `cw*ch*4096*3/2` |
| Pixel buffer (`buf[0]`) | header + body; `rfpw_b`/`rfpr_b` = base + header size | same |
| Thumb / DSP (`buf[1]`) | `ALIGN(aw/64 * ah/64 * 256, 8K)` | `cw*ch*256` |
| Collocated MV (`buf[2]`) | not used (no B, no col MV) | `ALIGN(cw*ch*96, 256)` (TMVP: `cmvw` = recon slot, `cmvr` = ref slot) |
| Count | `max(4, dpb_size+1)` slots | same |
| Example 1920x1080 | aw 1920, ah 1104: header 40 KiB, body 3.03 MiB, thumb 128 KiB | cw 30, ch 18: header 40 KiB, body 3.16 MiB, thumb 135 KiB, cmv 51 KiB |

Rules (M `setup_vepu580_recn_refr`, `vepu580_h265_set_hw_address`):
- Recon is written only when the frame is a reference (`enc_pic.cur_frm_ref = nal_ref_idc > 0`; HEVC skips `rfpw` when `non_reference_flag`).
- Exactly **one** reference slot is read (`rfpr_*`, `dspr`, `cmvr`), so `num_ref_idx_l0_active = 1` in practice. "Multiple references" and LTR in MPP mean *choosing which stored slot* is the single reference, plus signalling MMCO/reordering in the slice header.
- The down-sampled thumb of the reference is required for coarse ME, so it must be kept with each reference.

### 2.3 Other side buffers

| Buffer | Size | When |
|---|---|---|
| External line buffer (`ebuft/ebufb`) | `(aw - 3072)/64 * 480` bytes ("480 bytes for each ctu above 3072"). Allocated per task | H.264 width > 4096. Can be replaced by on-chip SRAM via `MPP_CMD_SET_RCB_INFO` (reg 183 + size, reg 182 + 0) |
| Loop-filter line buffers (`lpfw/lpfr`) | per tile, depends on pic height | HEVC tiles only |
| MEI (`meiw`) | optional motion-info output | smart/“md_info” users |
| ROI | base cfg: `ALIGN(mb_w,4) * mb_h * 8` (intra refresh); AMV `mb_w*mb_h/4`; MV `mb_w*mb_h*96/4`; QP map. All 64-aligned plus 32 B padding | ROI / intra refresh / qpmap |
| OSD | 8 regions, buffers 16-byte aligned, `blk_len = mb_x*mb_y*256` | OSD overlay |
| HEVC tile streams | `frame_size / tile_num` each (up to 3) | tile-parallel |

### 2.4 Output bitstream buffer

- `bsbb` = base, `bsbt` = base + size - 1 (**top is an end pointer**, and the port's guardrail allows `== end`, `rkvenc_service.c:847-851`), `adr_bsbs` = base + header bytes already in the packet, `bsbr` = base.
- The hardware treats this as a ring with a read pointer. On `bsf_oflw` the port's ISR bumps the read pointer to write+128 so the hardware can continue, which corrupts the stream (`rkvenc2_bs_overflow_handle`, `rkvenc_hw.c:383-401`). A V4L2 driver should treat overflow as a frame error and ask userspace for a larger CAPTURE buffer.
- Size readback is `bs_lgth_l32` (0x4000) plus `bs_lgth_h8` (0x4004[7:0]), so the length is 40 bits. Slice lengths come from the `st_snum`/`st_slen` FIFO (0x4034/0x4038).

### 2.5 Codec syntax carried in registers

**H.264** (M(verbatim) `hal_h264e_vepu580_reg.h`, filled in `setup_vepu580_codec()`):

| Reg | Fields |
|---|---|
| 0x3b0 `synt_nal` | nal_ref_idc[1:0], nal_unit_type[6:2] |
| 0x3b4 `synt_sps` | max_fnum[3:0] (log2_max_frame_num-4), drct_8x8, mpoc_lm4[8:5] (log2_max_poc_lsb-4, so POC type 0 is implied) |
| 0x3b8 `synt_pps` | etpy_mode (CABAC), trns_8x8, csip_flag (constrained intra), num_ref0_idx[1:0], num_ref1_idx[1:0], pic_init_qp[5:0], cb_ofst[4:0], cr_ofst[4:0], wght_pred, dbf_cp_flg (deblocking_filter_control_present) |
| 0x3bc `synt_sli0` | sli_type[1:0] (MPP: I→2, P→0), pps_id[7:0], drct_smvp, num_ref_ovrd, cbc_init_idc[1:0], frm_num[15:0] |
| 0x3c0 `synt_sli1` | idr_pid[15:0], poc_lsb[15:0] |
| 0x3c4 `synt_sli2` | rodr_pic_idx[1:0], ref_list0_rodr, sli_beta_ofst[3:0], sli_alph_ofst[3:0], dis_dblk_idc[1:0], rodr_pic_num[15:0] (one ref_pic_list_modification op) |
| 0x3c8–0x3d0 `synt_refm0..2` | nopp_flg (no_output_of_prior_pics), ltrf_flg (long_term_reference_flag), arpm_flg (adaptive_ref_pic_marking), mmco4_pre, up to 3 MMCO ops (type 3 bits + param 16 bits), long_term_frame_idx0..2 |
| `pic_qp` (0x300) | slice QP |
| 0x2200 SCL | scaling matrices (MPP writes a flat table) |

Not in registers: weighted-prediction tables (only the flag; weighted P is effectively unsupported), more than one reordering op, slice_group/FMO, redundant_pic_cnt, POC types 1/2 (amend path), delta_pic_order. Multiple slices come from `sli_splt` (by bytes or MB count). The hardware writes each slice header. `sli_crs_en` controls deblocking across slices.

**HEVC** (M `hal_h265e_vepu580.c`; names `reg0237…0245`, offsets assumed 0x3b4…0x3d4 **[UNVERIFIED]**):
- SPS: smpl_adpt_ofst_e (SAO), num_st_ref_pic, num_lt_ref_pic, lt_ref_pic_prsnt, tmpl_mvp_e, log2_max_poc_lsb, strg_intra_smth.
- PPS: dpdnt_sli_seg_en, out_flg_prsnt_flg, num_extr_sli_hdr, sgn_dat_hid_en, cbc_init_prsnt_flg, pic_init_qp, cu_qp_dlt_en/depth, chrm_qp_ofst_prsn, lp_fltr_acrs_sli/til, dblk_fltr_ovrd_en, lst_mdfy_prsnt_flg, sli_seg_hdr_extn.
- Slice: cbc_init_flg, mvd_l1_zero_flg, mrg_up/lft_flg, ref_pic_lst_mdf_l0, num_refidx_l0/l1_act, num_refidx_act_ovrd, sli_sao_luma/chrm_flg, sli_tmprl_mvp_e, pic_out_flg, sli_type, dpdnt_sli_seg_flg, sli_pps_id, no_out_pri_pic, tc/beta offsets, sp_dblk_fltr_dis, dblk_fltr_ovrd_flg, sli_cb_qp_ofst, max_mrg_cnd, col_ref_idx, col_frm_l0_flg, lst_entry_l0, sli_poc_lsb, sli_hdr_ext_len.
- Inline short-term RPS: st_ref_pic_flg, num_negative_pics, num_pos_pic, used_by_s0_flg, dlt_poc_s0_m10..m13. Long-term: poc_lsb_lt0..2, used_by_lt_flg0..2, dlt_poc_msb_prsnt/cycl0..2, num_lt_pic.
- Tiles: `tile_pos`, `tile_cfg`. `num_pic_tot_cur` in enc_pic.

---

## 3. What hardware generates vs software

| Element | H.264 | HEVC | Evidence |
|---|---|---|---|
| VPS/SPS/PPS | **SW** (`h264e_sps_to_packet`, `h264e_pps_to_packet` in `h264e_gen_hdr`, copied into the output packet as segments) | **SW** | M `h264e_api_v2.c` |
| SEI, prefix NAL (SVC/TSVC), AUD | **SW** ("prefix nal is added after SEI packet and before hw_stream") | SW | M |
| Start code + NAL header for slices | **HW** (amend assumes a 4-byte start code then the NAL header at `p[4]`) | **HW** | M `h264e_vepu_stream_amend_sync_ref_idc` |
| Slice header | **HW**, from `synt_*` | **HW** | M amend parses the hardware header with `h264e_slice_read()` |
| Slice data + emulation prevention | **HW** **[UNVERIFIED: no explicit EPB statement; `bs_scp` is the candidate control]** | HW | — |
| Header placement | HW writes from `adr_bsbs` = base + `packet_length` (offset patch reg 175), right after the SW headers | same, with `bsbt` = size-1 (reg 172) | M `setup_vepu580_io_buf` |
| SW post-fix: H.264 | `h264e_vepu_stream_amend_proc()` is enabled when `lt_cfg_cnt \|\| st_cfg_cnt > 1 \|\| hw_poc_type != poc_type \|\| hw_log2_max_frame_num != log2_max_frame_num`. It re-parses each hardware slice header, writes a SW header and bit-shifts the payload (byte copy for CABAC, bit copy for CAVLC). `..._sync_ref_idc()` patches `nal_ref_idc` in the NAL byte. | — | M `hal_h264e_stream_amend.c` |
| SW post-fix: HEVC | `hal_h265e_amend_temporal_id()`: patches byte 5 of the NAL header (`nuh_temporal_id_plus1`), so the hardware cannot emit TemporalId ≠ 0 | | M |
| Kernel role | none (no header bytes touched) | | K |

Design consequence: in a stateless V4L2 encoder, **userspace must produce the parameter sets** (as for the VC8000E RFC). The per-frame slice-header syntax goes to the driver as controls. Whatever the hardware cannot express (temporal_id, rich MMCO/RPLM, POC type ≠ 0) needs either a userspace header rewrite on the CAPTURE buffer or a restriction in the uAPI.

---

## 4. Rate control

### 4.1 Hardware RC (per frame, per row)

| Reg | Function | MPP setting (`setup_vepu580_rc_base`, `vepu580_h265_set_rc_regs`) |
|---|---|---|
| `enc_pic.pic_qp` | frame/slice start QP | from SW RC `quality_target` |
| `rc_cfg.rc_en`, `aq_en`, `aq_mode` | enable row RC and adaptive QP | rc_en=1, aq_en=1, aq_mode=0. FIXQP: min=max=pic_qp |
| `rc_cfg.rc_ctu_num` | RC unit = one CTU/MB row | mb_w (H.264), CTU width (HEVC), tile width (HEVC tiles) |
| `rc_qp.rc_qp_range` | maximum row ΔQP | `qp_delta_row_i` / `qp_delta_row`. 0 for SMTRC |
| `rc_qp.rc_min_qp/max_qp` | clamp | from SW RC |
| `rc_tgt.ctu_ebit` | target bits per CTU/MB ×16 | `(bit_target<<4)/num_blocks`, clamped to 0x50000 if ≥ 0x100000 |
| `rc_dthd_0_8[9]` (0x1008) | cumulative bit-deviation thresholds | H.264: {4n, n, p, 4p, MAX…}. HEVC: {2n, n, p, 2p, MAX…}. p = 5/16 × row target bits (HEVC) |
| `rc_adj0/1.qp_adj0..8` (0x1000) | ΔQP per deviation bucket | {-2,-1,0,1,2,0,0,0,1} |
| `aq_tthd[16]`, `aq_step[16]` (0x1044/0x1054) | texture-adaptive QP (MADI→ΔQP) | per I/P tables |
| `madi_cfg`, `md_sad_thd`, `madi_thd` | thresholds for stats histograms | H.264 4/9/15; HEVC 20/30/40, `madi_thd` = 25 |
| `roi_qthd0..3` | 8 QP areas (min/max) + `qpmap_mode` | ROI / qpmap |
| `RDO_QUANT.quant_f_bias_I/P` | deadzone | tuning |

### 4.2 Software RC (MPP `rc_model_v2.c`)

- Per frame, inputs to the HAL: frame type, `bit_target` (GOP-budget allocation in `bits_model_alloc`), `quality_target` (start QP), `quality_min/max`, plus the row ΔQP (from config).
- Modes: CBR, VBR, AVBR (motion-aware via MADP), FIXQP, plus SMT/SE stubs.
- Re-encode: if `bit_real` exceeds 1.5× (I) or 3× (P) the target, or the instantaneous bitrate breaks `bps_max`, MPP **re-encodes the same frame** with QP+1..3, or drops it, or turns it into P-skip (`check_re_enc`, `rc_model_v2_check_reenc`). This requires being able to re-run a frame with the same source and reference. A stateless uAPI handles that naturally (resubmit) only if the driver keeps the reference/recon slot valid until userspace commits.

### 4.3 Feedback registers (M(verbatim) `Vepu580Status`, 0x4000)

| Off | Name | Used by MPP for |
|---|---|---|
| 0x4000 / 0x4004[7:0] | bs_lgth_l32 / h8 | `bit_real`, payload length |
| 0x4004[31:16] / 0x4008 | sse_l16 / sse_h32 | `sse` (PSNR) |
| 0x400c | qp_sum | `quality_real` = qp_sum / blocks |
| 0x4010 | sao_cnum/ynum | — |
| 0x4014–0x401c | rdo_head_bits, rdo_res_bits | — |
| 0x4020 | st_enc, st_sclr | state |
| 0x402c | st_bsb (write pointer, ovfl) | overflow handling (K) |
| 0x4030 | st_bus | AXI idle/err |
| 0x4034 / 0x4038 | st_snum / st_slen | slice count / slice-length FIFO (24-bit length + last flag, K `rkvenc_hw.h:589-596`) |
| 0x4100–0x411c | st_pnum_p64/p32/p16/p8/i32/i16/i8/i4 | block-type counts, giving `iblk4_prop` (debreath) and `lvl*_inter/intra_num` |
| 0x4120 / 0x4124 | madp / num_ctu | `madp` (AVBR motion) |
| 0x4128 / 0x412c | madi / num_b16 | `madi` (complexity, I/P ratio) |
| 0x4130–0x4150 | num_madi_max_b16, md_sad_b16num0-3, madi_b16num0-3 | `motion_level`, `complex_level`, min-QP floor |
| 0x4200–0x42cc | st_b8_qp[52] | per-QP CU histogram (HEVC `st_cu_num_qp`) |
| 0x5200+ | frame_cyc, per-stage cycles | perf / devfreq |

---

## 5. Features and limits

| Feature | VEPU580 | Source / confidence |
|---|---|---|
| Codecs | H.264, HEVC, JPEG (JPEG via the same core, `RKVENC_FMT_JPEGE`) | K `rkvenc_hw.h:145-156` |
| Max resolution | Field maximum 16384x16384 (`enc_rsl` 11 bits ×8). RK3588 marketing: 8K@30 (7680x4320). Watchdog table up to >8K. H.264 >4096 wide needs the external line buffer. HEVC >4096 likely uses tiles **[UNVERIFIED threshold]** | M, K `rkvenc_hw.c:141-145` |
| Throughput | 4K@60 single stream reported working on this port (rcawston README); 8K@30 needs both cores **[UNVERIFIED]** | D |
| Bit depth | 8-bit only. No 10-bit input formats. HEVC Main and H.264 BP/MP/HP 8-bit 4:2:0 output (`out_fmt` also allows 4:0:0) **[UNVERIFIED levels]** | M `vepu5xx_common.c` |
| Input formats | §2.1 (NV12/NV21/I420/NV16/422P/YUYV/UYVY/Y800/NV24/444P/AYUV/RGB565/RGB888/RGBA variants/ARGB4444/1555, AFBC) | M |
| B-frames | Not used by MPP on 580. `version.bfrm_cap` exists and `num_ref1_idx`/`drct_*` fields exist, but there is only one ref read port, so treat it as **P-only** | M **[UNVERIFIED hw capability bit value]** |
| References | one per frame. Short-term and long-term via slot choice + MMCO/RPS fields. SVC-T (temporal layers) via prefix NAL / SW TID patch | M |
| Slices | split by bytes or CTU count, up to `sli_max_num_m1`+1. Low-latency per-slice IRQ + length FIFO (`slen_fifo`, `slc_done`) | M, K |
| Entropy | CABAC/CAVLC (H.264), CABAC (HEVC). 8x8 transform, constrained intra, scaling lists | M |
| HEVC tools | SAO, deblock overrides, TMVP, sign data hiding, strong intra smoothing, cu_qp_delta, tiles (≤4 uniform). Transquant bypass / lossless not seen | M |
| ROI | 8 QP areas, per-block QP map, forced intra/skip map, AMV/MV maps | M |
| OSD | 8 regions, 256-entry palette, inversion | M |
| Rotation / mirror / crop | yes (`src_rot`, `src_mirr`, `pic_ofst`) | M |
| Scaling | no (beyond the internal thumb) | M |
| Intra refresh, 2-pass (pass1 save/use), deblur/qpmap, smart encoding | yes (MPP features built on registers above) | M |

---

## 6. Kernel duties in the MPP design (what rkvenc_service does)

### 6.1 Request flow

uAPI `include/uapi/linux/rkvenc.h`: one ioctl, `MPP_IOC_CFG_V1`, carrying a chain of `struct mpp_request {cmd, flags, size, offset, data}`.

| Cmd | Kernel action | Ref |
|---|---|---|
| `INIT_CLIENT_TYPE` | bind the session to device type RKVENC (16) | `rkvenc_service.c:1127` |
| `INIT_TRANS_TABLE` | optional per-session override of the fd-register list | `:1168` |
| `SET_REG_WRITE` | copy register blocks into per-class kernel buffers. Each request is split by class and must not clip a class (recent hardening) | `:467-536`, `:181-420` |
| `SET_REG_READ` | record which status ranges to read back | `:537` |
| `SET_REG_ADDR_OFFSET` | list of `{reg index (absolute dword), byte offset}` added after fd→IOVA translation | `:580`, `rkvenc_task.c:307-359` |
| `SET_RCB_INFO` | list of `{reg index, size}` to point at on-chip SRAM | `:592`, `:691-735` |
| `POLL_HW_FINISH` | wait. In slice mode, returns once per slice (kfifo) | `:1320-1388` |
| `TRANS_FD_TO_IOVA`, `RELEASE_FD` | pre-import / release a dma-buf | `:1208-1229` |
| `SEND_CODEC_INFO` | stores w/h/fmt/fps/bitrate for debugfs only | `:1230-1251` |
| `SET_SESSION_FD`, batch (`mpp_bat_msg`) | **not implemented** | — |

### 6.2 Address patching

- For each fd-capable register (PIC 0x280–0x2dc, OSD 0x3050–0x306c), the value is `fd | (offset << 10)` (offset limited to 22 bits = 4 MiB) unless `MPP_FLAGS_REG_NO_OFFSET`. Larger offsets use `SET_REG_ADDR_OFFSET`. The kernel imports the dma-buf (dedup per task), writes `iova + offset` (`rkvenc_translate_reg_address`, `rkvenc_task.c:260-305`), then adds any extra offset (`rkvenc_service.c:785-791`).
- Guardrail (port addition): every translated address must fall inside its buffer `[iova, iova+len)`, with `== end` allowed for BSBT (`rkvenc_service.c:794-858`).
- DMA max segment size is set to 4 GiB so that `sg_dma_len(sgl)` equals the full buffer length (`rkvenc_hw.c:906-941`).
- **No register validation beyond class bounds.** Userspace can program any register in the exposed classes. That alone rules this uAPI out for upstream.

### 6.3 Run / IRQ / reset sequence (`rkvenc_hw.c`)

1. `pm_runtime_get_sync` on the IOMMU then the core, enable 3 clocks, take the reset-group rwsem for read (`:509-557`).
2. IOMMU attach + activate (`:560-570`).
3. **Erratum:** `enc_clr = force_clr (0x2)`, `udelay(5)`, `enc_clr = 0` before every frame, "Add force clear to avoid pagefault (VEPU580 workaround)" (`:572-577`).
4. Clear AXI perf counter (`0x5300 = 0x2`, `axip0_cmd.axip_clr`) (`:580`).
5. Patch DCHS IDs (`:583`). Write all class registers except `enc_strt` (`:585-608`). Flush IOMMU TLB (`:611`).
6. Hardware watchdog: `enc_wdg.vs_load_thd = timeout_ms * core_clk / 1024000` (units of 1024 core cycles), with timeout 200 ms (≤4K), 500 ms (≤8K), 800 ms (larger), keeping `rfp_load_thd[31:24]` (`:310-336`). Software delayed work at 200 ms (`MPP_WORK_TIMEOUT_DELAY`) (`:620-622`).
7. `wmb()`, write `enc_strt` with the userspace value (`:625-626`).
8. ISR: read and clear `int_sta`. Mask WDG to "prevent watch dog irq storm". In split mode read the slice FIFO. Handle overflow (pointer bump). On done/error, deactivate the IOMMU and queue the kthread bottom half (`:404-496`).
9. Finish: release DCHS, copy requested status ranges, write the sticky `irq_status` into the int_sta slot for userspace (`:657-700`). Any error bit triggers `reset_request`.
10. Reset: safe clear (`int_msk = 0x3ff`, `enc_clr = safe_clr`, poll int_sta for sclr-done for 5 µs), then force clear, clear IRQs. If that fails, CRU reset of a/h/core, then cycle the IOMMU's runtime PM, because "CRU reset wipes the IOMMU registers (DTE, paging)" (`:703-788`).
11. Cache maintenance: the kernel syncs only the JPEG bitstream buffer (`bs_buf` set only for `RKVENC_FMT_JPEGE`, `rkvenc_service.c:768-775`, `:861-869`). For H.264/HEVC, **userspace does dma-buf sync**.
12. PM: runtime-PM autosuspend after 2 s (`rkvenc_hw.c:950-953`). There is no devfreq / clock-mode switching (the `clk_mode` field is set but unused).

Other errata handled in the kernel:
- **H.264 + slice split + slen FIFO + external line buffer:** clear `sli_flsh` (bit 15 of 0x360), "H.264 bug: external line buffer + slice flush = bad" (`rkvenc_service.c:677-681`).
- MPP-side notes: "dual core runtime offset should set to 2 to avoid data access conflict" (HEVC tiles), "disable split to avoid lowdelay slice output" (2-pass), "FBC data require extra 16 lines space for hardware io", "480 bytes for each ctu above 3072".

### 6.4 Discrepancies in the port to resolve before reuse

| Item | Port | MPP register struct | Effect if the port is wrong |
|---|---|---|---|
| `INT_STA_SLC_DONE_STA` | BIT(1) (`rkvenc_hw.h:203`) | slc_done = bit 3 | Low-latency slice IRQs are never recognised as slice-done, and the ISR can return `IRQ_NONE` for a pure slice IRQ |
| `INT_STA_BSF_OFLW_STA` | BIT(2) | bsf_oflw = bit 4 (bit 2 = sclr_done) | The overflow handler runs on safe-clear-done. Real overflow arrives only via the error path |
| `RKVENC_SCLR_DONE_STA` | BIT(4) | sclr_done = bit 2 | The soft-reset poll waits on the wrong bit, so every reset probably falls back to CRU reset |
| `INT_STA_WDG_STA` | BIT(5) | wdg = bit 8 (bit 5 = brsp_otsd) | The watchdog-storm mask hits the wrong bit |
| DCHS layout | union `txe:1, rsv:3, txid:4, rxe:1, rsv:3, rxid:4` and `DCHS_TXE` BIT(8) (`rkvenc_hw.h:563-587`, `:209`) | `dchs_txid[1:0] rxid[3:2] txe[4] rxe[5] ofst[26:16]` | Frame-parallel DCHS would be mis-programmed. This only matters when MPP runs `task_cnt` = 2 or tiles |
| Bitstream size for JPEG sync | reads `0x4064` (`rkvenc_hw.c:686`) | 0x4064 is reserved. Length is at 0x4000 | JPEG cache sync length is wrong |
| Register naming | `RKVENC2_REG_ADR_BSBS 0x2b8`, `…BSBR 0x2bc` (`rkvenc_hw.h:179-182`) | 0x2b8 = bsbr, 0x2bc = adr_bsbs | Cosmetic. The code uses 0x2b8 as the read pointer, which is consistent with MPP |

All of these are **[UNVERIFIED against the BSP `mpp_rkvenc2.c` / TRM]**. The port claims to mirror the BSP. The comparison here is against MPP's `vepu580_common.h`, which is what drives the hardware in practice.

---

## 7. First-cut mapping to a V4L2 stateless encoder

### 7.1 RFC uAPI being compared (R, verbatim fields)

`V4L2_CID_STATELESS_H264_ENCODE_PARAMS` (`CODEC_STATELESS_BASE+8`), `struct v4l2_ctrl_h264_encode_params`:
`slice_type, pic_parameter_set_id, frame_num, idr_pic_id, cabac_init_idc, disable_deblocking_filter_idc, slice_alpha_c0_offset_div2, slice_beta_offset_div2, slice_size_mb_rows, pic_init_qp_minus26, chroma_qp_index_offset, flags, reference_ts` + (03/11) `nal_ref_idc, nal_unit_type`.
Flags: `ENTROPY_CODING_MODE, TRANSFORM_8X8_MODE, CONSTRAINED_INTRA_PRED` + (04/11) `NUM_REF_IDX_OVERRIDE, NO_OUTPUT_OF_PRIOR_PICS, LONG_TERM_REFERENCE`.
`V4L2_CID_STATELESS_H264_ENCODE_RC` (+9): `qp, qp_min, qp_max, mad_qp_delta, mad_threshold, cp_distance_mbs, cp_target[10], cp_target_error[6], cp_qp_delta[7]` (Hantro checkpoint RC).
`V4L2_CID_STATELESS_H264_ENCODE_FEEDBACK` (+10): `qp_sum, cp[10], mad_count, rlc_count`. Not read back in the RFC driver ("TODO").
The RFC driver also consumes the existing decoder `V4L2_CID_STATELESS_H264_SPS/PPS` controls for SPS/PPS values. Recon/ref buffers are **driver-internal** (DMA-coherent), tagged with the source buffer's timestamp, looked up by `reference_ts`, and dropped on IDR. Non-reference frames use a scratch recon. bytesused is read from a hardware register. Patch 03/11's commit message names **VEPU540 and VEPU580** as motivation for `nal_ref_idc`/`nal_unit_type`.

### 7.2 VEPU580 mapping

| VEPU580 input | V4L2 home | Fit with RFC |
|---|---|---|
| Source frame (formats §2.1, strides, crop, rotation) | OUTPUT queue buffer + `S_FMT`/`S_SELECTION` (crop), `V4L2_CID_ROTATE`/`HFLIP` | n/a (normal m2m) |
| Bitstream (`bsbb/bsbt/adr_bsbs`) | CAPTURE buffer. bytesused = start offset + `bs_lgth` | as RFC |
| SPS fields (`max_fnum`, `mpoc_lm4`, `drct_8x8`) | existing `V4L2_CID_STATELESS_H264_SPS` (`log2_max_frame_num_minus4`, `log2_max_pic_order_cnt_lsb_minus4`, `direct_8x8_inference`). Reject `pic_order_cnt_type` ≠ 0 | good fit, RFC already does this |
| PPS fields (`etpy_mode`, `trns_8x8`, `csip_flag`, `num_ref_idx_l0_default`, `pic_init_qp`, `cb/cr_ofst`, `dbf_cp_flg`, `wght_pred`) | existing `V4L2_CID_STATELESS_H264_PPS` (it carries `second_chroma_qp_index_offset` for `cr_ofst`), or the RFC encode_params copies (`pic_init_qp_minus26`, `chroma_qp_index_offset`, flags) | good fit. The RFC's TODO on duplicating PPS applies |
| `synt_nal` | `nal_ref_idc`, `nal_unit_type` (03/11) | exact fit (written for this hardware) |
| `synt_sli0/1/2` | `slice_type, pic_parameter_set_id, frame_num, idr_pic_id, cabac_init_idc, disable_deblocking_filter_idc, alpha/beta offsets` | exact fit. **Missing:** `pic_order_cnt_lsb` (needed for `poc_lsb`; the RFC lacks it), `num_ref_idx_active_override` value (the flag exists), one RPLM op (`modification_of_pic_nums_idc`, `abs_diff_pic_num`/`long_term_pic_num`), SP/direct flags N/A |
| `synt_refm0..2` | `NO_OUTPUT_OF_PRIOR_PICS`, `LONG_TERM_REFERENCE` flags exist. **Missing:** `adaptive_ref_pic_marking_mode_flag` + up to 3 MMCO ops + `long_term_frame_idx` | partial. Extend the struct, or restrict to sliding-window + IDR-LTR |
| Reference selection | `reference_ts` (one ref) | **exact fit**. VEPU580 reads one reference per frame |
| Recon/ref FBC + thumb (+ HEVC cmv) | **driver-internal pool**, keyed by source timestamp. Retained when `nal_ref_idc ≠ 0`, freed on IDR / eviction. Pool size from SPS `max_num_ref_frames` (+1 scratch, or none since non-ref frames skip `rfpw`) | as RFC. Format is proprietary FBC, so exporting it is pointless |
| Slice split (`sli_splt` by bytes or MBs) | RFC `slice_size_mb_rows`. VEPU580 also does byte-based splits | partial. Add byte mode. Per-slice low-latency output would need a per-slice completion/partial-buffer mechanism that V4L2 lacks |
| Frame QP, min/max QP | `ENCODE_RC.qp`, `qp_min`, `qp_max` | fit |
| Row RC (`rc_qp_range`, `ctu_ebit`, `rc_dthd[9]`, `qp_adj[9]`, `rc_ctu_num`) | the RFC's Hantro checkpoint fields do **not** map (cp_target per checkpoint ≈ dthd, cp_qp_delta ≈ qp_adj, but VEPU580 uses per-row targets and 9 buckets). Needs either a generic "target_bits + row ΔQP range" model with driver-computed LUTs (MPP's are fixed formulas, so the driver can derive them) or a vendor control | **poor fit**. Recommend a generic `target_bits` field and computing dthd/adj in the driver |
| AQ / MADI / quant bias / RDO / PAR / SQI tuning blocks | driver-internal defaults (copy MPP's static tables). Optional vendor control later | n/a |
| Scaling lists | existing `V4L2_CID_STATELESS_H264_SCALING_MATRIX` (driver re-packs into SCL) | fit |
| ROI / qp map / OSD | ROI: `V4L2_CID_MPEG_VIDEO_*` ROI proposals or a vendor control with a QP-map buffer. OSD: out of scope | n/a |
| Feedback (`bs_lgth`, `qp_sum`, `sse`, madi/madp, block counts, histograms, cycles) | `ENCODE_FEEDBACK` read back from the completed request. `qp_sum` maps directly. Add `sse`, `madi`, `madp`, `num_blocks`, intra/inter counts. Hantro's `cp[]`/`rlc_count` are irrelevant here | partial fit. Make the struct extensible or per-vendor |
| SPS/PPS/SEI bytes | userspace writes them itself (separately or by prepending to the frame). Optional: a driver "prefix bytes" control copied before `adr_bsbs`, or userspace mmaps the CAPTURE buffer and the driver gets a `data_offset` | RFC silent. Must be specified |
| DCHS / frame-parallel / tiles | driver-internal. Initially disabled (`txe/rxe = 0`) | n/a |
| HEVC | no stateless HEVC encode uAPI exists. The HEVC register set (RPS inline, SAO, TMVP, tiles) is a natural template for one | — |

### 7.3 Driver-internal duties for an upstream driver

1. One V4L2 m2m device covering both cores (like `rkvdec2`/`rkvenc` multi-core discussions). Either expose core 0 only at first, or schedule whole frames from different contexts onto whichever core is idle. With per-core IOMMUs, buffers must be mapped for both cores. Options: share one domain (as the BSP does), or map each vb2 buffer on both devices **[UNVERIFIED best upstream approach; check how rk3588 hantro/vepu121 multi-core and rkvdec2 handle it]**.
2. Program registers from controls only, with no userspace register access. Use fixed MPP-derived defaults for the PAR/SQI/RCKLUT tuning blocks.
3. Allocate the recon/ref pool (FBC pixel + thumb + cmv) and the >4K external line buffer (or SRAM).
4. Bitstream: `bsbb` = CAPTURE base, `bsbt` = base + size - 1, `adr_bsbs` = base + data_offset. On overflow, return an error (no ring pointer bump).
5. Watchdog + software timeout. Soft reset (with the fixed SCLR bit) and CRU fallback, followed by IOMMU re-init. Force-clear before each frame.
6. Cache: rely on vb2 dma-buf sync (the vendor design leaves it to userspace).
7. Frame-parallel (DCHS) needs two in-flight jobs from one context where job N+1 references N's recon before N completes. v4l2-m2m runs one job per context at a time, so this needs a custom scheduler. Defer. HEVC tile-parallel at 8K additionally needs per-tile bitstream buffers and a kernel-side memcpy (or chained `adr_bsbs`). Defer.

### 7.4 Open questions to settle on hardware

- Units and semantics of `dchs_ofst`. `bs_scp` meaning. `src_rot` encoding. Whether `rec_fbc_dis = 1` gives a usable linear NV12 recon (useful for debugging or recon export).
- Whether the hardware writes emulation-prevention bytes in slice data (almost certainly yes) and whether `poc_type` 2 is impossible (the amend path suggests yes).
- The HEVC width at which tiles become mandatory, and the HEVC equivalent of the external line buffer.
- `version` register value on RK3588 (`bfrm_cap`, `fbc_cap`, `res_cap`).
- Confirm the §6.4 bit discrepancies (enable slice IRQ and watch which bit fires; trigger a safe clear and read `int_sta`).
