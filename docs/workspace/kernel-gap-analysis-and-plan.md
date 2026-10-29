# Orange Pi 5 (RK3588S) on mainline Linux 7.3 — gap analysis & plan

Audit date: 2026-10-29. Trees examined (all fetched into `src/linux`, shallow):

| Ref | What | Commit |
|---|---|---|
| `v7.3` | current build base (released 2026-10-18) | c03c1a14507d |
| `torvalds/master` | 7.4 merge window, as of 2026-10-28 | c339f4010 |
| `next/master` | next-20261028 | 6d0933ae9 |
| `rockchip/for-next` | Heiko's queue for 7.4 | d2abcbb90 |

Board files: `arch/arm64/boot/dts/rockchip/rk3588s-orangepi-5.dts` →
`rk3588s-orangepi-5-5b.dtsi` → `rk3588s-orangepi-5.dtsi` → `rk3588s.dtsi` / `rk3588-base.dtsi`.

## 1. What already works on 7.3 (DT + driver present)

CPU DVFS (rk8602/rk806), thermal (tsadc), GbE (gmac1), USB 2/3 host + USB-C role/orientation
(fusb302 + usbdp PHY), M.2 PCIe 2.0 x1 (pcie2x1l2), SPI NOR (sfc), microSD, RTC (hym8563),
ES8388 analog audio, HDMI0 TX up to 4K60 TMDS with scrambling, CEC, HDR infoframe, HDMI audio
(i2s5), Mali-G610 (panthor), NPU (rocket), RGA2/RGA3, PWM LED, ADC key.

Video codecs with mainline drivers + DT nodes:

| Block | Driver | Codecs on RK3588 | Notes |
|---|---|---|---|
| rkvdec ×2 (VDPU381) | `rkvdec` | H.264 (incl. 4:2:2, 10-bit), HEVC (8/10-bit 4:2:0) | **only core 0 used**, VP9 missing |
| VDPU121 (Hantro G1) | `hantro` | MPEG-2, VP8, H.264 ≤1080p | via `rockchip,rk3568-vpu` fallback |
| VPU981 | `hantro` | AV1 (8/10-bit, film grain) | |
| VEPU121 ×4 | `hantro` | JPEG encode | **only 1 of 4 cores used** |

## 2. Gaps

### A. Our build configuration (fix immediately, no kernel code)

`build/linux/.config` produced by `scripts/build-kernel.sh` is missing:

| Symbol | Effect today |
|---|---|
| `CONFIG_VIDEO_ROCKCHIP_VDEC` (**not set**) | **No hardware H.264/HEVC 4K decode at all** — only Hantro's 1080p H.264 |
| `CONFIG_ROCKCHIP_DW_MIPI_DSI2`, `CONFIG_PHY_ROCKCHIP_SAMSUNG_DCPHY` | No MIPI-DSI panel output |
| `CONFIG_PHY_ROCKCHIP_INNO_CSIDPHY` (verify RK3588 support in 7.4) | No MIPI-CSI camera path |
| `CONFIG_DEVFREQ_EVENT_ROCKCHIP_DFI` | No DDR bandwidth counters (useful when profiling 4K/8K decode) |

### B. Kernel gaps with upstream work in flight (backport → test → help land)

| # | Gap | Upstream state (Oct 2026) | Impact for video testing |
|---|---|---|---|
| B1 | **VP9 decode on VDPU381** | "media: rkvdec: Add VP9 support for VDPU381" 4-patch series (Jul 2026), Profile 0 + 2, up to 8K30; 224/305 VP9 vectors pass. Packaged by Armbian for 7.2. Not in linux-next. | Most YouTube/WebM content is VP9 → currently software-only |
| B2 | **rkvdec multi-core** (2nd decoder core ignored, `rkvdec_disable_multicore()`) | "media: rkvdec: Enable multi-core support" v2 (Aug 2026, Detlev Casanova); depends on RGA multi-core + v4l2-m2m max-parallel-jobs. Not in linux-next. | Concurrent streams (e.g. 2×4K, multi-camera NVR) halve throughput |
| B3 | Hantro multi-core (VEPU121 ×4, `hantro_disable_multicore()`) | Same pattern as B2; would reuse the m2m parallel-jobs infra. Nothing posted that I found. | JPEG encode throughput only |
| B4 | **DisplayPort over USB-C (alt-mode)** | PHY side (usbdp rework, Type-C DP mux states) **landed in 7.4 merge window**. DRM side — "Synopsys DisplayPort Controller improvements for Rockchip" v10 (21 patches, out-of-band HPD from Type-C) — **pending**. Board DT needs `dp0` enabled, VOP2 vp→dp0 route, `altmodes { displayport { svid = 0xff01 } }` on the connector (template: ODROID-M2 RK3588S patch). | Second display; also tests HDR/10-bit over DP |
| B5 | Camera ISP (rkisp2) | Kernel driver v3 on list; libcamera pipeline handler v2/v3 (Aug 2026). VICAP + CSI-2 RX are already mainline. | Only if cameras matter; low priority for file playback |
| B6 | HDMI 2.1 FRL (4K120 / 8K60 output) | hdptx PHY FRL equalisation landed in 7.4; SCDC FRL helpers in linux-next; controller FRL training not posted. HDMI 2.0 series rejects >600 MHz TMDS. | 8K content can decode but can't be shown at native rate |

### C. No upstream work (new development)

| # | Gap | Notes |
|---|---|---|
| C1 | **VEPU580 H.264/HEVC encoder** (rkvenc ×2) | No mainline driver or binding. Out-of-tree stateful-API HEVC driver exists (github.com/rcawston/rockchip-rk3588-mainline-patches, CERALIVE fork), author says "not intended for upstream". Upstream would need a *stateless* encoder design (cf. Hantro H1/VC8000E work). Largest item. |
| C2 | **IEP2 deinterlacer** | No driver or DT node. Interlaced material (1080i broadcast TS, DVD MPEG-2) must be deinterlaced in software (GPU/CPU). New m2m driver, modest size. |
| C3 | Hardware JPEG/MJPEG decode | Hantro JPEG *decode* isn't wired for Rockchip variants, and the dedicated RK3588 JPEG decoder block has no driver. Matters for MJPEG webcams/AVI. |
| C4 | Small-frame / odd-size VP9 vectors, VP9 4:4:4 | Hardware limits; document, don't fix. |

### D. Board DTS items for the Orange Pi 5 itself

- `dp0` + USB-C alt-mode wiring (after B4).
- MIPI-DSI and 2× MIPI-CSI connectors: overlays once A/B5 are in place.
- Re-check `rk3588s-orangepi-5.dtsi` after 7.4-rc1: the OPi5 Pro refactor (`-5-5b.dtsi`) is already merged.

## 3. Plan

### Phase 0 — rebase & config (½ day, can start before hardware)
1. After 7.4-rc1 is tagged (~2026-11-01), fetch it into `src/linux` and switch the build to it. 7.4
   brings the usbdp/hdptx/hdmirx/hantro PM changes for free. Keep a `v7.3`-based branch as the baseline.
2. Add the section A symbols to `scripts/opi5.config` (`CONFIG_VIDEO_ROCKCHIP_VDEC=m`, etc.). The
   existing mismatch check in `build-kernel.sh` will flag anything that doesn't stick.
3. Make `src/linux` a real working branch (`opi5/dev`) with patches as commits, so the series can be
   exported with `git format-patch` for upstream or Armbian.

### Phase 1 — test platform & baseline (when the board is up)
1. Serial console on UART2 (1 500 000 baud) plus SSH. Fast iteration: `scp` the `linux-image` deb and
   `dpkg -i` + reboot. Later, TFTP/NFS boot from U-Boot.
2. Userspace stack on the image: `v4l-utils` (v4l2-compliance), GStreamer `v4l2codecs` (stateless
   H.264/HEVC/VP8/VP9/AV1/MPEG-2), FFmpeg with the v4l2-request hwaccel, `fluster`, `mpv`, `kmscube`,
   `modetest`, `cec-ctl`.
3. Baseline run on stock 7.3/7.4 + config fix, recording the results (see test plan).

### Phase 2 — land in-flight series (ordered by value for video playback)
1. **B1 VP9** → apply, run fluster VP9 suites, review/Tested-by upstream.
2. **B2 rkvdec multi-core** (+ RGA multi-core + m2m parallel jobs dependencies).
3. **B4 DP alt-mode** → dw-dp series + OPi5 DT patch (ours to write and submit).
4. B3 Hantro multi-core, reusing the B2 infrastructure.

### Phase 3 — new drivers (pick by need)
1. **C2 IEP2 deinterlacer**: smallest new driver, high value for broadcast/DVD files.
2. **C1 VEPU580 encoder**: start from the out-of-tree driver for the hardware programming
   sequences. Upstream needs agreement on a stateless encode API, so begin with an RFC.
3. C3 JPEG decode, B6 FRL, B5 cameras as time allows.

## 4. Test plan

### 4.1 Test-file corpus
Inventory your files once and bucket them by codec, profile, bit depth, resolution, frame rate,
interlacing, and container:

```sh
find /media/videos -type f \( -iname '*.mkv' -o -iname '*.mp4' -o -iname '*.webm' -o -iname '*.ts' -o -iname '*.m2ts' -o -iname '*.avi' -o -iname '*.mov' \) -print0 |
  xargs -0 -n1 ffprobe -v error -select_streams v:0 -of csv=p=0 \
    -show_entries stream=codec_name,profile,pix_fmt,width,height,r_frame_rate,field_order -show_entries format=filename \
  > corpus.csv
```

Pick ~3 representative files per bucket (H.264 High/High10/4:2:2, HEVC Main/Main10, VP9 P0/P2, AV1
Main 8/10, VP8, MPEG-2 progressive + interlaced, MJPEG; 1080p/4K/8K; 24/30/60 fps).

### 4.2 Correctness
- **Conformance**: `fluster` suites JVT-AVC_V1, JVT-FR-EXT, JCT-VC-HEVC_V1, JCT-VC-MAIN10,
  VP9-TEST-VECTORS (+ HIGH), AV1-TEST-VECTORS / CHROMIUM-10bit, VP8-TEST-VECTORS, MPEG2 suites,
  with GStreamer v4l2codecs and FFmpeg v4l2request decoders. Track pass counts per kernel build.
- **Real files**: frame-by-frame MD5 of hardware decode vs software decode
  (`ffmpeg -hwaccel v4l2request ... -f framemd5` vs `-hwaccel none`). Any mismatch is a bug, or
  a known hardware limit to document.
- `v4l2-compliance -d /dev/videoN` on every m2m node, every build.

### 4.3 Performance & concurrency
- Decode-only throughput (`fakesink sync=false`, `-f null`) per codec/resolution; target 4K60 HEVC/VP9
  and 8K30 HEVC/VP9.
- Playback to display (`kmssink` / mpv `--vo=drm`) with dropped-frame counts; CPU% and DDR bandwidth (DFI).
- Multi-core (B2): N parallel 4K streams, N=1..6. Throughput should roughly double from 1 to 2
  streams and frames must still match their MD5s.

### 4.4 Display / audio
- HDMI: modes up to 4K60, 10-bit/HDR infoframe, CEC (`cec-ctl --playback`), HDMI audio passthrough
  and PCM (`speaker-test`), hot-plug loops.
- DP alt-mode (B4): plug/unplug, cable flip, USB-C→HDMI adapters, USB3 data still working alongside 2-lane DP.

### 4.5 Stability & regression
- 12-hour looped playback mixing codecs; watch `dmesg` for IOMMU faults/timeouts.
- Runtime-PM idle → decode → idle cycles (rkvdec/hantro power domains); suspend/resume once TF-A allows it.
- A `scripts/test-media.sh` harness on the board that runs 4.2–4.3 and writes a CSV per kernel
  version, so each patch series gets a before/after comparison.

## 5. Sources
- rkvdec VP9 for VDPU381: https://ratatoskr.run/linux-rockchip/2026/07/17321148/t , Armbian packaging https://github.com/armbian/build/pull/10874
- rkvdec multi-core v2: https://ratatoskr.run/linux-media/2026/08/17392375/t
- dw-dp Rockchip improvements v10: https://ratatoskr.run/dri-devel/2026/08/17373539/t ; ODROID-M2 DP alt-mode DT: https://ratatoskr.run/linux-devicetree/2026/04/3497203
- HDMI 2.0 for DW HDMI QP v10: https://ratatoskr.run/linux-rockchip/2026/07/17350030/t
- VEPU580 out-of-tree: https://github.com/rcawston/rockchip-rk3588-mainline-patches , https://github.com/CERALIVE/rk3588-kernel-patches
- RK3588 ISP / rkisp2: https://www.collabora.com/news-and-blog/news-and-events/mainline-video-capture-and-camera-support-for-rockchip-rk3588.html , https://patchwork.libcamera.org/cover/28011/
- Hantro G1 (VDPU121) on RK3588 history: https://patches.linaro.org/project/linux-media/cover/20231231151112.3994194-1-liujianfeng1994@gmail.com/
