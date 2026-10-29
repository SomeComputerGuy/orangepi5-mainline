# V4L2 stateless video encoding: state of the uAPI (survey as of 2026-10-29)

Purpose: decide how to upstream an RK3588 VEPU580 (rkvenc) H.264/HEVC encoder.
Method: web and mailing-list archives (lkml.iu.edu / lkml.indiana.edu mirrors,
lists.infradead.org, patchew, LWN, ratatoskr.run, hverkuil.home.xs4all.nl, GitLab API),
plus read-only greps of local `~/orangepi5/src/linux` refs. lore.kernel.org,
patchwork.linuxtv.org, linuxtv.org and the gitlab.freedesktop.org web UI all returned
403/Anubis to the fetcher, so lore links are given where known but were read through mirrors.
"UNVERIFIED" marks claims I could not confirm from a primary source.

## TL;DR

- **Nothing is merged.** No stateless-encode uAPI exists in v7.3, torvalds/master (7.4 merge
  window) or next-20261028. Local `git grep` for `STATELESS_H264_ENCODE`, `v4l2-h264-enc`,
  `ENCODE_PARAMS`, `H264_SL`, `dev-stateless-encoder` finds nothing.
- **The live V4L2 proposal** is Paul Kocialkowski's (sys-base)
  `[PATCH 00/14] media: Add V4L2 H.264 stateless encode and VC8000E support`, 2026-05-22.
  It is H.264 only, for Hantro VC8000E on i.MX8MP. Its design is **kernel-driven**:
  the kernel writes SPS/PPS/slice headers, rate control runs in the kernel, and the kernel
  tracks the DPB and owns the reconstruction buffers. Userspace sets per-frame encode
  params through a request. Paul says v2 is in progress (Sep 2026) and will add the spec
  document. [cover](https://lkml.indiana.edu/2605.2/13184.html),
  [lore](https://lore.kernel.org/all/20260522101653.2565125-1-paulk@sys-base.io/),
  [patchew](https://patchew.org/linux/20260522101653.2565125-1-paulk@sys-base.io/),
  [v2 status](https://lkml.indiana.edu/2609.3/02661.html)
- **Collabora (Nicolas Dufresne) is pursuing a different direction for Rockchip encoders.**
  The plan is a thin, codec-agnostic kernel driver written in Rust (DRM/accel-style), with
  a Mesa **Vulkan Video** userspace driver. Detlev Casanova and Daniel Almeida are writing
  it for the **RK3588 encoder**, and it reportedly "finally got P-Frames support" in July
  2026. Nicolas explicitly does not want two interfaces for the same hardware. The only
  RK3576 VEPU510 V4L2 submitter has since agreed to join that effort instead.
  [Nicolas 2026-07-22](http://lists.infradead.org/pipermail/linux-arm-kernel/2026-July/1153134.html),
  [Nicolas 2026-07-23](http://lists.infradead.org/pipermail/linux-arm-kernel/2026-July/1153705.html),
  [Jiaxing Hu decision](http://lists.infradead.org/pipermail/linux-arm-kernel/2026-July/1153737.html),
  [Media Summit 2026 slides "Vulkan Video Encoder"](https://hverkuil.home.xs4all.nl/summit2026/Nicolas%20-%20Vulkan%20Video%20Encoder.pdf)
- **No HEVC, VP8 (beyond RFC), AV1 or JPEG stateless-encode uAPI has been proposed for
  merging.** HEVC stateless encode has never been posted.

## 1. Every posted series / proposal

| Date | Author (org) | Series / version | Codec | Target HW | uAPI style | Status |
|---|---|---|---|---|---|---|
| 2021 (branch only) | Paul Kocialkowski (Bootlin) | `hantro/h264-encoding-v5.11` branch. The origin of `v4l2_ctrl_h264_encode_params` | H.264 | Hantro H1 on PX30/RK3399 | Userspace-driven, HW-specific controls | Never posted as a series. Superseded. [2025 slides p5](https://hverkuil.home.xs4all.nl/summit2025/Paul%20Kocialkowski%20-%20Stateless%20Video%20Encoding%20uAPI.pdf), [Bootlin blog](https://bootlin.com/blog/open-source-linux-kernel-support-for-the-allwinner-v3-v3s-s3-h-264-video-encoder/) |
| ~2022-23 (branch only) | Michael Grzeschik (Pengutronix) | Bootlin port to RK3568 rkvenc (VEPU540), branch `v5.19/topic/rk3568-vepu-h264-stateless-bootlin`. RFC promised Jul 2023 | H.264 (I-only) | RK3568 rkvenc | Userspace headers via GStreamer codecparsers bitwriter | **RFC never found on lists (UNVERIFIED that it was posted).** [git](https://git.pengutronix.de/cgit/mgr/linux/commit/?h=v5.19/topic/rk3568-vepu-h264-stateless-bootlin&id=ec2b92670100c6bd075ca859bc3392b5b913be27), [Jul 2023 mail](https://lkml.iu.edu/hypermail/linux/kernel/2307.2/08265.html) |
| 2023-03-09 | Andrzej Pietrasiewicz (Collabora) | `[RFC 0/2] VP8 stateless V4L2 encoding uAPI + driver` | VP8 | Hantro VEPU2 on RK3399 | Userspace-driven, HW-specific controls, no docs | Stalled RFC, never respun as a PATCH. [infradead](https://lists.infradead.org/pipermail/linux-rockchip/2023-March/037686.html), [linuxtv pw](https://patchwork.linuxtv.org/comment/145546) |
| 2023-07-11 | Paul Kocialkowski (Bootlin) | "Stateless Encoding uAPI Discussion and Proposal" (design thread, no code) | generic | - | Discussion | Long thread with Nicolas, Michael Grzeschik and others. [start](https://lkml.iu.edu/hypermail/linux/kernel/2307.1/03552.html), [lore](https://lore.kernel.org/linux-media/ZK2NiQd1KnraAr20@aptenodytes/T/) |
| 2023-10-04 | Hugues Fruchet (ST) | VP8 encode for Hantro H1 (VC8000NanoE), derived from Andrzej's RFC | VP8 | STM32MP25 | Same as Andrzej's VP8 | RFC, stalled. linuxtv pw series 11358 (cited by Andrzej's H.264 RFC). Details UNVERIFIED (search summary only) |
| 2023-11 | Paul Kocialkowski (Bootlin) | Allwinner V3/V3s/S3 H.264 encoder in Cedrus (GitHub branch `cedrus/h264-encoding`, plus `v4l2-cedrus-enc-test`) | H.264 | Allwinner V3 | **Kernel-driven, reuses stateful controls**, no RC | Not posted for merge. Paul: "doesn't really help advance our uAPI discussion". [Bootlin blog](https://bootlin.com/blog/open-source-linux-kernel-support-for-the-allwinner-v3-v3s-s3-h-264-video-encoder/), [mail](https://lkml.iu.edu/hypermail/linux/kernel/2311.1/06591.html) |
| 2023-11-16 | Andrzej Pietrasiewicz (Collabora) | `[RFC 0/6] H.264 stateless encoder` | H.264 | Hantro H1 on STM32MP25 | Userspace-driven. `V4L2_CID_STATELESS_H264_ENCODE_PARAMS` (slice/PPS/NAL fields, `reference_ts`) + `V4L2_CID_STATELESS_H264_ENCODE_RC` (qp, MAD, checkpoint fields) | Stalled RFC. Superseded. [patchew](https://patchew.org/linux/20231116154816.70959-1-andrzej.p@collabora.com/), [uAPI patch](https://patchew.org/linux/20231116154816.70959-1-andrzej.p@collabora.com/20231116154816.70959-6-andrzej.p@collabora.com/), [LWN](https://lwn.net/Articles/951733/) |
| 2025-05-02 | Marco Felsch, Michael Tretter (Pengutronix), incl. one patch by Paul | `[RFC PATCH 00/11] VC8000E H.264 V4L2 Stateless Encoder` | H.264 (I/P) | Hantro VC8000E, i.MX8MP | Userspace-driven, HW-specific controls, plus first uAPI doc patch | RFC. Superseded by Paul's 2026 series, which carries 2 of Marco's patches. [openwall](https://lists.openwall.net/linux-kernel/2025/05/02/1002), [LWN](https://lwn.net/Articles/1020012/), [patchew](https://patchew.org/linux/20250502150513.4169098-1-m.felsch@pengutronix.de/), [Nicolas review 2025-06-10](https://lists.infradead.org/pipermail/linux-rockchip/2025-June/059199.html) |
| **2026-05-22** | **Paul Kocialkowski (sys-base)** | **`[PATCH 00/14] media: Add V4L2 H.264 stateless encode and VC8000E support`** (v1, non-RFC tag) | H.264 (I/P, CBR/CQ/direct-QP) | VC8000E, i.MX8MP | **Kernel-driven**: generic `v4l2-h264-enc{,-rbsp,-rc}.c` core in v4l2-core | **Under review, v2 in progress** (Paul, 2026-09-24). Nicolas treats v1 as an RFC because it has no spec doc. 27 files, +7231 lines. [cover](https://lkml.indiana.edu/2605.2/13184.html), [lore](https://lore.kernel.org/all/20260522101653.2565125-1-paulk@sys-base.io/), [LWN](https://lwn.net/Articles/1074067/) |
| 2026-07-22 | Jiaxing Hu | `[RFC PATCH 0/3] media: rockchip: VEPU510 H.264 encoder for RK3576` | H.264 | RK3576 VEPU510 (same VEPU5xx family as RK3588 VEPU580) | **Stateful** V4L2 m2m, from scratch. Intra works, P-frames hang in the reference read. Register tables are hex dumps of MPP defaults | Author withdrew to join the Collabora Vulkan Video effort (2026-07-23). [cover](http://lists.infradead.org/pipermail/linux-arm-kernel/2026-July/1153134.html), [decision](http://lists.infradead.org/pipermail/linux-arm-kernel/2026-July/1153737.html), [standalone repo](https://github.com/gahingwoo/vepu510-rk3576) |
| 2026-09-23/24 | Michael Nazzareno Trimarchi | Reply on Paul's series: port of the encode helpers to Rockchip PX30 VEPU (Hantro H1), `rockchip_vpu_hw_h264_enc.c`, not yet posted | H.264 | PX30 (RK3399 planned) | Paul's uAPI | Reported working. A second implementation may follow. [mail](https://lkml.indiana.edu/2609.3/00096.html), [Paul reply](https://lkml.indiana.edu/2609.3/02412.html) |
| 2026 (not posted) | Detlev Casanova, Daniel Almeida (Collabora) | Thin Rust kernel driver (codec-agnostic) + Mesa Vulkan Video ICD | H.264 first. Other codecs to land in userspace | **RK3588 rkvenc (VEPU580)** | Vulkan Video (non-V4L2) | P-frames working per Nicolas (Jul 2026). **No public code or branch found (UNVERIFIED).** [Nicolas](http://lists.infradead.org/pipermail/linux-arm-kernel/2026-July/1153134.html), [Nicolas](http://lists.infradead.org/pipermail/linux-arm-kernel/2026-July/1153705.html) |

Not found anywhere: any HEVC, AV1 or JPEG *stateless*-encode uAPI posting. (Hantro JPEG
encode upstream is a stateful-style driver and not relevant here.) Paul's VC8000E register
header already includes HEVC and JPEG register definitions
([2026 slides p20](https://hverkuil.home.xs4all.nl/summit2026/Paul%20-%20Stateless%20Video%20Encoding%20uAPI.pdf)),
but no HEVC uAPI exists. Other 2026 encoder-adjacent uAPI work is for stateful encoders only:
a generic ROI control from Qualcomm (Deepa Madivalara, up to v10 by 2026-10-16), found in
the [lkml.indiana.edu index](https://lkml.indiana.edu/2610.2/index.html).

## 2. Design questions and positions

### Two camps (Paul's own classification, [2025 slides p6](https://hverkuil.home.xs4all.nl/summit2025/Paul%20Kocialkowski%20-%20Stateless%20Video%20Encoding%20uAPI.pdf))
- *Userspace-driven*: userspace writes headers, HW-specific param/stats controls, userspace
  RC in lock-step. This covers Bootlin 2021, Andrzej 2023 and Felsch 2025. **This approach has
  been abandoned for the V4L2 path.**
- *Kernel-driven*: kernel headers, kernel RC, stateful-like controls. This covers Allwinner 2023
  and, in hybrid form, Paul 2026.

### Paul's 2026 design ([2026 slides](https://hverkuil.home.xs4all.nl/summit2026/Paul%20-%20Stateless%20Video%20Encoding%20uAPI.pdf), also at [paulk.fr](https://paulk.fr/talks/2026-linux-media-summit/2026-linux-media-summit-v4l2-stateless-video-encoding-uapi-progress-update.pdf))
| Topic | Proposal |
|---|---|
| Philosophy | Reuse the stateful encoder uAPI where possible. Hardware-agnostic. "Accommodation rather than combinatory capabilities reporting": the kernel adapts params to HW limits and **returns the final parameters**. |
| Setup | Same as the stateful encoder: ENUM_FMT/FRAMESIZES/FRAMEINTERVALS, S_FMT capture (coded) then output (raw), S_PARM for frame rate, S_SELECTION for crop. |
| Pixel format | Coded format names the mode. Proposal: rename `V4L2_PIX_FMT_H264_SLICE` to `V4L2_PIX_FMT_H264_SL`. **Approved at the 2026 Summit** ([minutes](https://ratatoskr.run/linux-media/2026/06/17137934)). One access unit per capture buffer. |
| Controls | `V4L2_CID_STATELESS_H264_SPS` and `_PPS` (reused decode structs), **new `V4L2_CID_STATELESS_H264_ENCODE_PARAMS`** (slice header and more), `_START_CODE`, existing `V4L2_CID_MPEG_VIDEO_H264_VUI_*`, `PREPEND_SPSPPS_TO_IDR`, `AU_DELIMITER`. |
| Bitstream headers | **Generated by the kernel** (`v4l2-h264-enc-rbsp.c`: AUD/SPS incl. VUI/PPS/slice header, exp-Golomb). Driver ops `bits/bits_raw/ue/se/align` let a driver use HW header writers or CPU writes. HW feature flags `V4L2_H264_ENC_FLAG_HW_AUD/SPS/PPS/SLICE_HEADER`, `INTER_PRED/BIPRED`. |
| Rate control | **In the kernel** (`v4l2-h264-enc-rc.c`). Modes: direct QP from controls, CQ, CBR (sliding-window budget, I-frame boost, QP from size stats). Uses existing `FRAME_RC_ENABLE`, `BITRATE_MODE`, `BITRATE`, `CONSTANT_QUALITY`, `H264_{I,P,B}_FRAME_(MIN/MAX_)QP`. Driver-specific RC ops hook. eBPF and module-selectable RC are future work. |
| References | Userspace marks references (`nal_ref_idc`, `V4L2_H264_ENCODE_FLAG_LONG_TERM_REFERENCE`). **The kernel tracks the DPB** (sliding window) and builds L0/L1 with the existing reflist builder. MMCO/RPLM and explicit DPB/L0/L1 feedback are open. |
| Recon/ref buffers | **Driver-internal**, not exposed to userspace: `rec_buffer_{alloc,free}` driver callbacks, initial slots from `ref_slots_count_init` or `V4L2_H264_NUM_DPB_ENTRIES/2`, only grown. |
| Feedback | Controls updated with the actual values used, ideally attached to the incoming request. **Read-only request support is missing.** Buffer flags KEYFRAME/PFRAME/BFRAME/ERROR. Bitstream size comes from capture `bytesused`. Average-QP return (`V4L2_CID_MPEG_VIDEO_AVERAGE_QP`) is listed as missing. |
| Multi-slice | Missing. Plan: stateful `V4L2_CID_MPEG_VIDEO_MULTI_SLICE_*`, with ENCODE_PARAMS applied to all slices. |
| Driver API | `v4l2_h264_enc_init` (start_streaming) / `_step` (device_run) / `_complete` (IRQ) / `_exit`, plus a `state_constrain` callback. |
| Still missing (v1) | Docs/spec, B-frame capability indication, frame skip/VBV, HRD, drain/resolution change via ENCODER_CMD, interlace, multiple SPS/PPS, POC type > 0. |

This evolved from his [2025 Summit proposal](https://hverkuil.home.xs4all.nl/summit2025/Paul%20Kocialkowski%20-%20Stateless%20Video%20Encoding%20uAPI.pdf).
That proposal had userspace decide params and an *explicit* reference list (VA-API and
Vulkan compatible), with RC and headers in the kernel. In 2026 references became
"userspace marks, kernel tracks". It also lists rkvenc VEPU510/540/580 as target
hardware (p4).

### Maintainer / reviewer positions (with sources)
- **Nicolas Dufresne (Collabora, media codec co-maintainer):**
  - A **spec document is mandatory** before real review. He calls v1 "RFC from my point of
    view" without it ([2026-05-22](https://lkml.indiana.edu/2605.2/13945.html)).
  - He also wants **"a second implementation, not just a variant of the same brand"**
    ([2026-09-24](https://lkml.indiana.edu/2609.3/02549.html)).
  - His spec wishes ([2026-09-24](https://lkml.indiana.edu/2609.3/02690.html)): drain as
    simple as the stateless decoder; capability query like stateless decoders "up-side
    down", with no pseudo-unset state; maybe mandatory `V4L2_FMTDESC_FLAG_ENUM_ALL`; keep
    S_PARM for RC; S_SELECTION for the conformance window; requests mandatory; drop
    keyframe-insertion controls since frame type is explicit.
  - **In-kernel RC is needed "for performance reason"**. RC must stay close to the IRQ and
    may become generic or eBPF ([Jul 2026](http://lists.infradead.org/pipermail/linux-arm-kernel/2026-July/1153134.html)).
    Same view in 2023, when he said no kernel GOP management but kernel RC is unavoidable
    ([2023 thread, search summary](https://lkml.iu.edu/hypermail/linux/kernel/2307.1/03552.html)).
  - Wants Rockchip encoders on **Vulkan Video plus a thin kernel driver**, requiring
    IOMMU-based per-process protection. He sees V4L2 high-level drivers as still valuable
    for HW without such protection.
  - Against two interfaces for the same hardware: "the transition path is near impossible
    unless you accept to support both APIs concurrently"
    ([Jul 23](http://lists.infradead.org/pipermail/linux-arm-kernel/2026-July/1153705.html)).
  - Frame-size semantics: coded size equals the CAPTURE size, kept separate from allocation
    size ([2025-06-10](https://lists.infradead.org/pipermail/linux-rockchip/2025-June/059199.html)).
- **Paul Kocialkowski:**
  - Thinks two drivers (V4L2 and DRM-ish) for the same HW is acceptable.
  - Believes his V4L2 proposal "will probably be finalized in a shorter time frame" and
    that the DRM-ish one "will likely require a complete redesign"
    ([Jul 23](http://lists.infradead.org/pipermail/linux-arm-kernel/2026-July/1153685.html),
    [later](http://lists.infradead.org/pipermail/linux-arm-kernel/2026-July/1153719.html)).
  - Says his RC helpers are mostly V4L2-independent.
  - Hopes to add an Allwinner implementation as the second driver, if funded.
- **Hans Verkuil, Laurent Pinchart, Sakari Ailus, Mauro Carvalho Chehab:** the 2026 minutes
  record **no attributed position** from them on either topic. Unattributed guidance
  recorded there: "Don't abuse existing controls, it's cheap to add new controls", and a
  read-only-request series (Hans, 2021) may be needed for encoder feedback
  ([minutes](https://ratatoskr.run/linux-media/2026/06/17137934)). I found no on-list
  review by Hans of the 2026 series in the LKML-CC'd traffic. linux-media-only replies
  could exist on lore, which I could not reach (UNVERIFIED).
- **Sebastian Fricke:** CC'd on the 2025 RFC. No recorded position found.

### Media Summit outcomes
- **2025 (Nice, 13 May):** Paul presented the hybrid design. Collabora's recap: "a hybrid
  approach: stateless encoding using compound controls and requests, combined with a
  stateful rate controller implemented in the kernel… single shared C implementation…
  could later be extended with eBPF". The proposal was "generally well received" and no
  formal decision is recorded ([Collabora recap](https://www.collabora.com/news-and-blog/blog/2025/06/23/linux-media-summit-2025-recap),
  [LWN brief](https://lwn.net/Articles/1026528)). Paul's timeline target was "technical
  community consensus before 2026" (slides p15). That target was missed. Hans's official
  2025 minutes were not retrievable (linuxtv.org Anubis), so they are UNVERIFIED.
- **2026 (Nice, 26 May)** ([minutes posted 2026-06-16](https://ratatoskr.run/linux-media/2026/06/17137934),
  [slides dir](https://hverkuil.home.xs4all.nl/summit2026/)):
  - **Decision:** rename `V4L2_PIX_FMT_H264_SLICE` to `V4L2_PIX_FMT_H264_SL`.
  - **Action:** write an RFC or document proposing reference handling in the uAPI (no
    owner named).
  - Read-only requests may be needed for feedback.
  - RC discussion: Vikash (Qualcomm) asked for configurable or HW-assisted RC. Paul said
    kernel RC can use hardware feedback and is cheap.
  - H.264/H.265 sharing: little to share beyond small bitstream helpers.
  - Vulkan Video session (Nicolas): "NOT a Linux Media Project". It will start with
    hardware that V4L2 never supported, and IOMMU protection is required. No decision
    recorded.
- No common per-codec "encode params" control set has been agreed. Only the H.264
  `ENCODE_PARAMS` control exists, in Paul's unmerged series.

## 3. Userspace
- **GStreamer `v4l2slh264enc` / `v4l2slvp8enc`:**
  - Upstream MR [!5676 "Draft: v4l2codecs: Add VP8 and H264 encoding support"](https://gitlab.freedesktop.org/gstreamer/gstreamer/-/merge_requests/5676)
    (Nicolas, opened 2023-11-16) is **still Draft/open, last updated 2025-10-21** (GitLab API).
  - The earlier VP8 MR [!3736](https://gitlab.freedesktop.org/gstreamer/gstreamer/-/merge_requests/3736)
    (Benjamin Gaignard) was closed 2024-02-21.
  - Paul's matching element is out of tree at
    [github.com/paulkocialkowski/gstreamer `v4l2codecs/h264enc`](https://github.com/paulkocialkowski/gstreamer/tree/v4l2codecs/h264enc)
    (based on 1.26.0, supports `rate-control=cbr`). He says it "needs rework before
    upstreaming" ([Jul 2026](https://lkml.iu.edu/2607.2/16577.html)).
  - No GStreamer MR for v4l2 stateless HEVC encode was found.
- **Vulkan Video encode in GStreamer** (the userspace that the Collabora path would use):
  `vkh264enc` was merged ([!7197](https://gitlab.freedesktop.org/gstreamer/gstreamer/-/merge_requests/7197),
  2025-08), and `vulkanh265enc` is open ([!12580](https://gitlab.freedesktop.org/gstreamer/gstreamer/-/merge_requests/12580),
  updated 2026-10-28). Both found via the GitLab API.
- **FFmpeg:** only V4L2-request *decode* hwaccels exist (Jonas Karlman, [2024 v2](https://ffmpeg.org/pipermail/ffmpeg-devel/2024-August/332034.html)).
  No stateless encode work was found.
- **libva / libcamera:** no stateless-encode users found (UNVERIFIED negative).

## 4. HEVC stateless encode
I found no posted proposal, RFC or GStreamer element. Paul's Summit decks list H.265 as
"common" but out of the immediate scope. The VC8000E (i.MX8MP) can do HEVC but only H.264
was implemented. The only RK3588 VEPU580 HEVC encode code I found is out of tree:
[rcawston/rockchip-rk3588-mainline-patches](https://github.com/rcawston/rockchip-rk3588-mainline-patches)
(described as "stateful H.265", tested on v6.19-rc8, dual-core, "Not intended for upstream
merge"). It requires a forked MPP and an `rkvenc-mpp` overlay, so it appears to be an
MPP-service-style port rather than V4L2 (inferred, UNVERIFIED). A packaging fork exists at
[CERALIVE/rk3588-kernel-patches](https://github.com/CERALIVE/rk3588-kernel-patches).

## 5. Rockchip VEPU580 / rkvenc upstream status and MPP split
- **Upstream:**
  - No rkvenc (VEPU510/540/580) driver exists in mainline or next (local grep, plus
    Nicolas's statement that RKVENC "had no upstream driver").
  - The only on-list attempt is the RK3576 VEPU510 stateful RFC (above). It was withdrawn
    in favour of the Collabora RK3588 Vulkan-Video driver.
  - The RFC reported the same P-frame watchdog stall in the reference/recon read path that
    Detlev hit on RK3588. Detlev's MMU faults and P-frame failure "cleared together"
    (recon FBC compression mentioned) ([Jul 2026](http://lists.infradead.org/pipermail/linux-arm-kernel/2026-July/1153635.html),
    [Jul 2026](http://lists.infradead.org/pipermail/linux-arm-kernel/2026-July/1153737.html)).
    Exact root cause: UNVERIFIED.
  - Earlier: Grzeschik's RK3568 rkvenc (VEPU540) work (2022-23), never posted (above).
  - OpenWrt carries a stateful RKVENC v1 (RV1126/RK3568) driver out of tree
    ([openwrt PR #25945](https://github.com/openwrt/openwrt/pull/25945), per search
    summary, UNVERIFIED in detail).
- **How the vendor stack splits the work (MPP is effectively the "userspace-driven
  stateless" model):**
  - Kernel (`drivers/video/rockchip/mpp/mpp_rkvenc2.c` in the
    [Rockchip BSP](https://github.com/rockchip-linux/kernel/blob/develop-6.1/drivers/video/rockchip/mpp/mpp_rkvenc2.c))
    is a generic register-blob executor via `/dev/mpp_service`:
    - `MPP_CMD_SET_REG_WRITE/READ`, `SET_REG_ADDR_OFFSET`, `SET_RCB_INFO`,
      `POLL_HW_FINISH`, `TRANS_FD_TO_IOVA` ([mpp_service.h](https://github.com/rockchip-linux/mpp/blob/develop/osal/inc/mpp_service.h));
    - dma-buf fd to IOVA patching in the register blob;
    - dual-core (CCU) handshake for RK3588's two VEPU580 cores;
    - slice-done FIFO for low-latency split output;
    - SRAM RCB setup;
    - `rec_fbc_dis` handling.
  - Userspace MPP does everything codec-related:
    - SPS/PPS generated in software (`h264e_sps_to_packet`/`h264e_pps_to_packet` in
      [h264e_api_v2.c](https://github.com/rockchip-linux/mpp/blob/develop/mpp/codec/enc/h264/h264e_api_v2.c),
      `h265e_ps.c`).
    - **Slice headers are written by the hardware** from syntax registers
      (`synt_nal/sps/pps/sli0-2/refm*`, including RPLM and MMCO fields) filled by
      [hal_h264e_vepu580.c](https://github.com/rockchip-linux/mpp/blob/develop/mpp/hal/rkenc/h264e/hal_h264e_vepu580.c).
      Software writes slice headers only for P-skip frames.
    - DPB/reference management in software (`h264e_dpb.c`).
    - Rate control in software (`mpp/codec/rc/rc_model_v2*.c`).
    - Hardware RC assist is configured via `reg_rc_klut` (MAD thresholds, QP adjust tables).
    - Per-frame feedback is read back from status registers: `bs_lgth_l32` (bitstream
      length), `qp_sum` (average QP), `madi`/`madp`, `sse` and per-threshold block counts,
      which feed motion/complexity levels
      (`hal_h264e_vepu580_ret_task`).
    - Large tuning tables in `hal_h264e_vepu580_tune.c` and `hal_h265e_vepu580_tune.c`.
  - Implication: with Paul's V4L2 design, the VEPU580 driver would declare
    `HW_SLICE_HEADER`, put SPS/PPS through the kernel RBSP helper, and hook the HW stats
    (qp_sum, MAD, SSE) into the RC `ops`. The tuning tables and RDO/lambda tables would have
    to become clean code in the kernel. Nicolas has already rejected hex-dumped MPP tables
    ([Jul 23](http://lists.infradead.org/pipermail/linux-arm-kernel/2026-July/1153705.html)).
    The Vulkan route keeps most of that (incl. HEVC) in Mesa.

## Facts that matter for our approach
1. **No merged uAPI, and no consensus on the subsystem.** For V4L2 the only viable base is
   Paul's kernel-driven H.264 design (v2 pending, spec required). For RK3588 rkvenc
   specifically, Collabora (Nicolas, who maintains the codec area and reviews these
   series) has stated a Vulkan-Video / thin-Rust-KMD direction. Detlev and Daniel already
   have P-frames working, and Nicolas opposes a second interface for the same HW.
2. **Talk to Detlev Casanova / Nicolas before writing code.** A competing V4L2 VEPU580
   driver would be the "two interfaces for one HW" situation Nicolas objected to. Paul
   would welcome a V4L2 VEPU5xx driver as the non-Hantro "second implementation" that his
   series needs. Both are in tension.
3. **What any V4L2 submission must have:** a written stateless-encoder spec (Nicolas);
   kernel-side headers, RC and DPB tracking via `v4l2-h264-enc*` helpers; driver-internal
   recon buffers; request-based per-frame params with feedback via controls (read-only
   requests not yet upstream); no abuse of existing controls; and clean,
   non-hex-dump register setup.
4. **HEVC is greenfield** in V4L2 stateless encode, so any HEVC work means designing a new
   uAPI on top of an H.264 design that has not landed. On the Vulkan path, HEVC is a
   userspace (Mesa) concern once the kernel driver exists.
5. **Hardware gotcha already known:** the first P-frame on VEPU5xx hangs the watchdog in the
   recon/ref read path unless the MMU/FBC setup is right. Detlev's fix is not public.
