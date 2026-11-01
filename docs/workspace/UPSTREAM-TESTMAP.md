# Hardware test map (Orange Pi 5 / RK3588S)

One entry per patch of ours, grouped by series. `TESTED` = existing evidence shows that the patch's code path ran on the board and behaved correctly (path + what it proves); `NEEDS TEST` = the concrete run that would prove it. A patch in two series (same change, two bases) is counted once in the totals.

## asoc-rockchip-pcm-order

- **0402** TESTED (01): ~/orangepi5/work/_out/hdmi-audio/s2-verify.txt + s2-speaker-test.txt + README.txt: kernel 7.3.0-10dclkn1901i2s (branch opi5/test-k10-dclk-no1901-i2s-pcm = k10 + both PCM-order patches) -- debugfs asoc/hdmi0 now has dma:fddf0000.i2s, speaker-test plughw:CARD=hdmi0 plays (st_plug=0), aplay on the hdmi0 card succeeds; before (s1-*: 10dclkn1901, ~/orangepi5/work/_out/klog-19b/board-k10.txt) open failed with EINVAL and the component was missing.
- **0403** NEEDS TEST; the rk3588-i2s + spdif-dit simple-card DT was prepared (~/orangepi5/work/_out/needtest/testboot/needtest-overlay.dts) but the combined test boot hung (see 2107), no result. (NEEDS TEST entry: (02): no rockchip_i2s (non-TDM, "rockchip,rk3588-i2s"/rk3399 etc.) instance is used on the Orange Pi 5 (HDMI and ES8388 are on i2s-tdm), so the rockchip_i2s.c path never ran; on an RK3399/RK3568 board with a card whose codec probes before the I2S controller, `aplay -D hw:<card>,0` must open (or on the OPi5: enable an rk3588-i2s instance such as i2s2_2ch with a dummy codec card).)
- **0401** TESTED (03): ~/orangepi5/work/_out/board-hygiene/RESULTS.md section 4 (module snd-soc-rockchip-i2s-tdm.ko from 0401, in the image kernel since kernel 5) and ~/orangepi5/work/_out/workaround-removal/board/boot-v2.txt (kernel #4): the only remaining flat-cache warning is for rockchip-spdif, none for fddf0000.i2s; HDMI audio playback verified in the hdmi-audio run above.

## cpufreq-unlisted-freq

- **1102** NEEDS TEST; pm_test=core run prepared in ~/orangepi5/work/_out/needtest/scripts/testboot-run.sh, not run (board handed back). (NEEDS TEST entry: on a kernel with the patch (all image kernels since kernel 5 carry 1102, but no deep/core suspend was run since), `echo core > /sys/power/pm_test; rtcwake -m mem -s 20` (then a real deep suspend): expect no "kernel BUG at drivers/cpufreq/cpufreq.c" and CPU4/CPU6 back at a listed frequency (`cpufreq_resume: ... Running at unlisted initial frequency ... changing to` in dmesg). The bug itself is documented in ~/orangepi5/work/_out/suspend/RESULTS.md ("Bug 2", kernel #2 without the fix).)

## devfreq-resume-freq

- **0514** TESTED: ~/orangepi5/work/_out/gpu-npu/RESULTS.md ("Results on the fixed kernel", step 5): kernel #2 of 2026-10-29 17:38 with 0501-0514, 200 glmark2 jobs with runtime suspends in between, trans_stat 200 MHz -> {300..1000} transitions grew by ~200, i.e. resume went straight to the remembered OPP.

## dp-altmode-hpd

- **0268** 01 TESTED: ~/orangepi5/work/_out/dp-smooth/RESULTS.md: "Verified after the 22:23 reboot (all three modules from updates/opi5-dp-smooth)": D->C->D pin-assignment switches, dw-dp logs "short HPD -> Retraining link -> 2 lanes at 5400 MHz, CR and EQ succeeded" ~0.36 s after each switch (the OOB-as-short-pulse path of this patch), DPCD 0x202 = 77 00, no black screen and no modeset; before: DPCD 00 00 and black until a modeset, reproduced 3 times.
- **0269** 02 TESTED: ~/orangepi5/work/_out/dp-smooth/RESULTS.md: same run; the C->D direction produces no Attention from the dongle ("After C->D the dongle sent no Attention at all"), so the retrain seen after C->D is triggered by this patch's OOB "connected" event after Configure.

## dw-dp-aux-fixes

- **1902** 01 BLOCKED: needs camera (USB-C dock regression on kernel 11). Evidence collected but not accepted without camera frames: ~/orangepi5/work/_out/needtest/1902-1904/dw-dp-aux/k11-*/summary.txt: 20-min `dw-dp-aux-test.sh after` run: 20/20 DPCD reads ok in A and B, 0 "timeout waiting for AUX reply" in A-D, 0 retrain/hotplug/WARN (no Mutter on this image: the display was never blanked, link up throughout). (NEEDS TEST entry: ~/orangepi5/work/_out/dw-dp-aux/RESULTS.md says "Board test (board busy, not run)" and HANDOFF.md "board test queued"; no later result exists (no dw-dp-aux/results/, nothing in tests/results). Run `~/orangepi5/work/_out/dw-dp-aux/test/host-run.sh` (phases A-D: aux-dev DPCD reads with display on/blanked, soak with IRQ_HPD pulses) on the Orange Pi 5 with the dock; expect 0 "timeout waiting for AUX reply" in every phase and -ENXIO-free reads while HPD is high. Note: kernels 9-11 (7.3.0-9/-10) contain 1902-1904 and the k10 s2idle proof (suspend-k10/RESULTS.md, 47 cycles) ran with them: DP-1 stayed connected/enabled, but one "dw-dp: timeout waiting for AUX reply" occurred in one of 47 cycles, so the fix is not proven.)
- **1903** 02 BLOCKED: needs camera; the link-off/runtime-resume path was not exercised (no Mutter, DP-1 stayed enabled and runtime-active during the soak); kmsctl-based link-off script prepared in ~/orangepi5/work/_out/needtest/scripts/display-tests.sh. (NEEDS TEST entry: same test as 01 (the resume-after-idle part of phases C/D: autosuspend 500 ms between the dock's IRQ_HPD pulses); expect the first DPCD read after each runtime resume to succeed and no "Hot plug detected" after a timeout burst.)
- **1904** 03 BLOCKED: needs camera; same as 1903 (phase B ran with the PHY on). (NEEDS TEST entry: same test, phase B (display blanked via Mutter PowerSaveMode=3, 20 aux-dev DPCD reads of 0x000-0x00f): before, reads fail with the PHY off; after, all 20 return the DPCD (12 14 c2 81 ...).)
- **1101** 04 TESTED: ~/orangepi5/work/_out/suspend/RESULTS.md: Bug 1 (dw-dp link dead after any resume that runs the noirq phase: 40x "timeout waiting for AUX reply" in S3 platform test) and "Proof (2026-10-30 21:52-22:50): test kernel 7.3.0-opi5-susp = patches/linux (321) + 1104 + v2": 55 fast s2idle resumes, "After every resume: DP-1 + HDMI-A-1 connected, DP AUX DPCD read OK ... no 'AUX reply / failed to enable link'"; plus ~/orangepi5/work/_out/suspend-k10/RESULTS.md 47/47 cycles on k10 with DP-1 connected/enabled after every resume.

## dw-dp-pcon

- **1204** 01 TESTED: ~/orangepi5/work/_out/dp-4k30/RESULTS.md: "Post-patch test (batch6.log, cam/b6-*.jpg)": with build/c/dw-dp.ko (patches 0001-0003 = 1204-1206) the PCON is in HDMI mode (DPCD 0x3050-0x3052 = 01 00 00, was 00), 1080p60/1440p/4K30 clean on camera with sink CRCs identical to pre-patch, GNOME greeter on DP 1440p + HDMI 1080p, dp0 ELD shows the monitor.
- **1205** 02 TESTED: ~/orangepi5/work/_out/dp-4k30/RESULTS.md: same run, "DFP limits read at detect: max bpc 12, max dotclock 0 (not reported), TMDS 25-600 MHz. DP-1 mode list unchanged: 4K30 is preferred; 4K60 is still rejected by link bandwidth" (the DFP-limit code path ran; no mode of this dock hits a DFP limit, so the rejection branch itself is unexercised -- the cover letter says so).
- **1206** 03 BLOCKED: needs the user (HDMI replug at the dock) and the camera. (NEEDS TEST entry: ~/orangepi5/work/_out/dp-4k30/RESULTS.md says "Not tested: unplug/replug of the monitor on the dock's HDMI port (patch 0003 path)". On the Orange Pi 5 with the dock: `echo 'module dw_dp +p' > /sys/kernel/debug/dynamic_debug/control`, unplug the HDMI cable at the dock, wait 3 s, replug; expect dmesg "Downstream port status changed" and DP-1 status disconnected -> connected (`cat /sys/class/drm/card*-DP-1/status`) without a USB-C replug. Also 5x repeat; no "Retrain link failed".)
- **1210** 04 BLOCKED: needs the user (CEC-tunnelling USB-C->HDMI adapter) and the camera. (NEEDS TEST entry: dock PCON has CEC_TUNNELING_CAPABILITY = 0 (dp-cec/NOTES.md, HANDOFF "DP CEC code present (dormant: dock not CEC-capable)"); needs a CEC-tunnelling USB-C->HDMI adapter (Parade/MegaChips based): with the adapter and TV, `ls /dev/cec*` must show a new adapter, `cec-ctl -d /dev/cecN --playback` then `cec-ctl -d /dev/cecN -t0 --give-device-power-status` must get a reply from the TV; unplug -> adapter removed; `rmmod dw_dp`/unbind must not WARN. Dormancy with the non-capable dock is covered (kernel 8+ boots, DP works, no cecN for DP).)

## dw-hdmi-qp-fixes

- **1907** 01 1907: BLOCKED: needs camera (HDMI patch); DDC-poll run under injected IOMMU fault storms prepared in ~/orangepi5/work/_out/needtest/scripts/hantro-robust-test.sh (debug hantro module). (NEEDS TEST entry: on a kernel >= 7.3.0-9 run ~/orangepi5/work/_out/hdmi-ddc/ddc-poll-test.sh <label> <rkvdec stress cmd> (per hdmi-ddc/RESULTS.md) and compare the summary lines: with the patch, bad/scdc_fail must stay ~0 even when "i2c read timed out" appears in dmesg. The only observation so far is the original failure (one timeout in ~400 injected rkvdec recoveries, rkvdec-reset logs); kernel #10 ran the 140-case HDMI matrix (testmatrix-runs/tm/k10-hdmi/results.tsv) with no DDC failure, which does not exercise the retry.)
- **1202** 02 1202: TESTED: ~/orangepi5/work/_out/audio/RESULTS.md: "Hardware results after the reboot": with a 48 kHz PCM open and playing, modesets 4K60->4K120->4K60 and 4K60 FRL->1080p TMDS->4K60 FRL each reprogrammed the ACR from atomic_enable (kprobes on dw_hdmi_qp_set_sample_rate/drm_hdmi_acr_get_{frl_,}n_cts: acr_tmds tmds=185625000 at 1080p, acr_frl at 4K), PCM stayed RUNNING with hw_ptr advancing, no xruns; HANDOFF.md: HDMI audible through 4K60/4K120 FRL/1080p TMDS mode changes (user listened).
- **1906** 03 1906: BLOCKED: needs camera; script section prepared in ~/orangepi5/work/_out/needtest/scripts/display-tests.sh (speaker-test on hdmi0 with HDMI-A-1 disabled, then enable with the stream open). (NEEDS TEST entry: on a kernel >= 7.3.0-9 that also has the PCM registration fix (series asoc-rockchip-pcm-order), with HDMI output off or the sink unplugged: `speaker-test -D hdmi:CARD=hdmi0 -c2 -l1` must open and play silently without "hdmi-audio-codec ... -19" in dmesg, then enable the output (modeset) while a stream is open: audio must come up without reopening. The kernel #10 attempt (~/orangepi5/work/_out/klog-19b/board-k10.txt) was blocked by the unrelated PCM open EINVAL (audit item 4) before prepare was reached, so the patch's path has not run on hardware.)

## dwc3-s2idle

- **1104** TESTED: ~/orangepi5/work/_out/suspend/RESULTS.md: "Follow-up slot" C1 (dwc3 power_lost drop-in dwc3-powerlost-k5.ko on kernel 5: "xHC error in resume, USBSTS 0x401" gone, only "root hub lost power" remains) and the 7.3.0-opi5-susp proof (55 fast s2idle cycles, "xHC error in resume, USBSTS 0x401 no longer appears (1104)"): on those kernels the core was torn down in s2idle (no 1901 yet), so the power_lost=true path ran on every resume and xhci reinitialised without the failed CRS.
- **1901** TESTED: ~/orangepi5/work/_out/suspend-k10/RESULTS.md (+ s2c/q20/summary.txt, s2c/q20/dmesg-after.txt): kernel 7.3.0-10rtc (k10 + rtc fix, 1901 included) ran 47 s2idle cycles (fix10 7/7, dbg20 20/20, q20 20/20); every cycle reports usb=14/14 and ss=7/7 with the same device numbers, and the 20-cycle q20 dmesg contains zero "root hub lost power", "reset SuperSpeed" or "USB disconnect" lines after boot (40 "PM: suspend entry" lines), i.e. the kept-core path ran and the devices resumed from U3 instead of being reset-resumed; usb-resume/RESULTS.md documents the pre-1901 failure (Extreme/Transcend disconnected after every resume) from persist-pd1 dmesg.

## fw-devlink-sync-state

- **1905** TESTED: ~/orangepi5/work/_out/hdmi-audio/s2-verify.txt (kernel 7.3.0-10dclkn1901i2s, branch opi5/test-k10-dclk-no1901-i2s-pcm which contains ef76e6ec8fd4 = this patch): `dmesg | grep -c 'Failed to create device link'` = 0; the same count is 0 in ~/orangepi5/work/_out/klog-19b/board-k10.txt (10dclkn1901), versus 3 lines per boot without it (~/orangepi5/work/_out/workaround-removal/board/boot-v2.txt, kernel #4). regulator_summary evidence that the domains still hold the supplies: ~/orangepi5/work/_out/board-hygiene/RESULTS.md section 3.

## h264-encode-fixes

- **0808** 01: TESTED: ~/orangepi5/work/_out/vepu121-h264enc/board-logs/p_1080_q28.h264: 60-picture GOP-30 1080p stream encoded on the board by the VEPU2 driver with this patch in v4l2-h264-enc.ko; NAL unit types parsed from the file are 7,8,5,29x1,7,8,5,29x1 (one SPS/PPS per IDR, not per picture), and RESULTS.md in the same directory shows every stream decoding in FFmpeg with 0 errors.
- **0809** 02: TESTED: ~/orangepi5/work/_out/vepu121-h264enc/RESULTS.md: the VEPU2 driver constrains every stream to pic_order_cnt_type 2 (board-logs/run.log: "final SPS: ... poc_type 2"); all 14 stream types in the results table (I-only, IPPP CAVLC/CABAC, High 8x8, CBR, CQ, 720p/1080p) decode in FFmpeg with 0 errors at the expected PSNR, which requires the type-2 POC derivation and SPS writer of this patch.

## hantro-codec-fixes

- **1402** 01 TESTED: ~/orangepi5/work/_out/codec-quality/RESULTS.md (section 1, conformance table): with the drop-in module (0715 = this patch) the ISO/IEC 13818-4 field-picture streams sony-ct1..4, tcela-8/9/10 and hhi_burst_short/long went from "rejected (0 frames)" to decoding through GStreamer v4l2slmpeg2dec on the RK3588 VPU121.
- **1404** 02 TESTED: same file, same table: adding 0716 (= this patch) raised the field-picture streams from 10-35 dB to 53-67 dB PSNR vs FFmpeg (tcela-8/9/10: 63.6/56.3/63.9, sony-ct1/2/4: 52.9/54.5/66.7) with the 26 frame-picture streams unchanged.
- **1408** 03 TESTED: ~/orangepi5/work/_out/needtest/1408/run.log: VPU121 decoder `--list-framesizes=VP8F` = 48x48 - 1920x1088; try-fmt/S_FMT OUTPUT 3840x2160 VP8F clamp to 1920x1088 (CAPTURE NV12 1920x1088); a 1080p libvpx VP8 clip decodes bit-exact vs libvpx (10/10 frames); the 4K VP8 clip is refused by v4l2slvp8dec (pads do not link) and decodebin picks the software vp8dec. (was NEEDS TEST: the bug was observed (~/orangepi5/work/_out/codec-quality/RESULTS.md: VP8F 3840x2160 accepted, GStreamer `info->width <= meta->width` assertions, 0/10 frames match) but the fixed module was "installed, verification pending a reboot" and no later run was found. On the Orange Pi 5: `v4l2-ctl -d <vpu121 dec> --list-framesizes=VP8F` must stop at 1920x1088, `--try-fmt-video-out=width=3840,height=2160,pixelformat=VP8F` must clamp to 1920x1088, and a 4K VP8 stream must be refused by v4l2slvp8dec (falls back to another decoder) while a 1080p VP8 stream still decodes bit-exact.)
- **1916** 04 TESTED: ~/orangepi5/work/_out/needtest/1916/run.log + alloc-*.txt: one v4l2slav1dec context decoding 1920x1080 10-bit 4-column then 8-bit 5-column AV1 (clip AB) and 2048x128 4-column then 8-column (CD2) is bit-exact vs libdav1d (32/32 frames each; each clip alone too); kprobe trace of dma_alloc/free_attrs shows all five column buffers freed and reallocated at the A->B switch (415030/215062/366852/2701448/1278528 -> 414336/275744/393568/3568480/1278528 B) although the deblocking-data buffer alone was big enough, i.e. the per-buffer check decided it (stock would have reused all five, three too small). AV1-TEST-VECTORS fluster not re-run (board handed back). (was NEEDS TEST: ~/orangepi5/work/_out/av1-tiles/RESULTS.md lists the fix as 0001 and the board run as "(pending)"; ~/orangepi5/work/_out/av1-tiles/board/ is empty and no SUMMARY.txt/state.txt exists, so the queued test (HANDOFF step 9, "av1-tiles test reworked to drop-ins + reboots") never ran. The fluster-fix tile ladder (~/orangepi5/work/_out/fluster-fix/RESULTS.md, 2026-10-31) ran one geometry per decoder instance on stock and doesn't exercise the reuse check. Needed: in one decoder context, decode a 10-bit 1088-line 4-tile-column AV1 clip followed by an 8-bit 1088-line 5-column clip (and an 8-bit 128-line 4-column clip followed by a 64-line 8-column one) with the stock driver showing a page fault/corruption or the debug guard (dbg_av1_colmap) reporting OVER, and the patched driver bit-exact vs dav1d; plus the AV1-TEST-VECTORS fluster run unchanged (203/242 or better).)
- **1403** (dropped from this series) 

## hantro-h264-enc

- **0824** 01: TESTED: ~/orangepi5/work/_out/vepu121-h264enc/RESULTS.md: CABAC streams (IPPP QP20/28/36, High+8x8) encoded on the board with the context states derived from the shared table decode in FFmpeg with 0 errors and give the same PSNR as CAVLC with 10-15% fewer bits; VDPU121 H.264 decode (the table's original user) stays md5-identical to FFmpeg.
- **0825** 02: TESTED: ~/orangepi5/work/_out/vepu121-h264enc/RESULTS.md (raw logs in board-logs/run.log, compliance.txt): on the Orange Pi 5 the VEPU2 encoder of the VPU121 encoded 14 stream configurations at 720p/1080p (I-only, IPPP CAVLC/CABAC, High 8x8, Constrained Baseline, CBR 2/8 Mbit/s, CQ 80), 2/4 parallel contexts, encode+decode on the same VPU, and a live webcam, all decoding with 0 FFmpeg errors at the expected PSNR; v4l2-compliance 44/49, 0 warnings.
- **0826** 03: TESTED: ~/orangepi5/work/_out/vepu121-h264enc/RESULTS.md: the encoder is only registered when the "vepu" interrupt added here is in the DTB (combined DTB with this hunk on the board); the frame-ready interrupts of every run above arrived on GIC SPI 120, so the interrupt number and the shared clocks/PD/IOMMU of the node are right.

## hantro-jpeg-enc-fixes

- **0711** 01 TESTED: ~/orangepi5/work/_out/needtest/0711-0714/jpeg/run.log section 2: explicit CAPTURE 1920x1080 JPEG + OUTPUT 1920x1080 NM12 stream: out_b.mjpeg 765757 bytes, 8 decodable 1920x1088 frames, CAPTURE sizeimage 4178544; `--try-fmt-video=...,sizeimage=1000` -> 4178544, `sizeimage=8000000` kept. (was NEEDS TEST: ~/orangepi5/work/_out/hantro-validate/TESTING.md section 2 on the Orange Pi 5: `v4l2-ctl -d $D --set-fmt-video-out=width=1920,height=1080,pixelformat=NM12 --set-fmt-video=width=1920,height=1080,pixelformat=JPEG --stream-out-mmap=4 --stream-mmap=4 --stream-from=src.nv12 --stream-to=out_b.mjpeg --stream-count=8` must give a non-empty out_b.mjpeg with 8 decodable frames and `--try-fmt-video=...,sizeimage=1000` must return 4178544; the before-state (0-byte output) is documented, no after-run was found.)
- **0712** 02 FAILED on kernel 11 (fix proposed, re-test pending): the sync itself works (G_FMT after the OUTPUT S_FMT shows CAPTURE 1920x1088 sizeimage 4178544), but TESTING.md reproducer (a) streams 0 bytes with IOMMU faults at IOVA 0..0x1a40 and a watchdog timeout: v4l2-ctl re-applies S_FMT(CAPTURE) with the unchanged format while OUTPUT is busy, hantro_set_fmt_cap() -> hantro_reset_raw_fmt() clobbers ctx->vpu_src_fmt before hantro_set_fmt_out() returns -EBUSY, the encoder is programmed as planar and reads the V plane from address 0 (pre-existing upstream bug). Root cause and traces: ~/orangepi5/work/_out/needtest/RESULTS.md Finding 1, ~/orangepi5/work/_out/needtest/0711-0714/trace-fail.txt; fix: ~/orangepi5/work/_out/needtest/fixes/0001-media-verisilicon-Don-t-reset-the-encoder-raw-format-while-OUTPUT-buffers-exist.patch (applies on k11, checkpatch clean; built into ~/orangepi5/work/_out/needtest/hantro-dbg/out/hantro-vpu.ko, not yet run). (was NEEDS TEST: TESTING.md section 1: `v4l2-ctl -d $D --set-fmt-video-out=width=1920,height=1080,pixelformat=NM12 --set-fmt-video=pixelformat=JPEG --get-fmt-video --get-fmt-video-out` shows CAPTURE 1920x1088 sizeimage >= 4178544, and the 8-frame stream produces no rk_iommu/timeout messages; the crop (selection) case still gives 1920x1080 JPEGs.)
- **0713** 03 NEEDS TEST (indirect check inconclusive while reproducer (a) fails for the 0712 reason; no "inconsistent geometry"/"CAPTURE buffer too small" in ~/orangepi5/work/_out/needtest/0711-0714/jpeg/dmesg.txt). (NEEDS TEST entry: not reachable from userspace once 01/02 are in; indirect: none of the section 1/2/5 runs prints "inconsistent geometry" or "CAPTURE buffer too small" (a forced-fault test would need a debug patch).)
- **0714** 04 TESTED: ~/orangepi5/work/_out/needtest/0711-0714/jpeg/run.log section 3+5: `v4l2-compliance -d <vepu121>`: test VIDIOC_S_FMT: OK, 49/49 (and -s 58/58) succeeded, 0 failed; both queues sRGB / sRGB / ITU-R 601 / Full Range; 9/9 GStreamer v4l2jpegenc pipelines reach EOS, frame.jpg 1920x1080 baseline, no colorimetry warnings. (was NEEDS TEST: TESTING.md section 3: `v4l2-compliance -d $D` on the VEPU121 node must report "test VIDIOC_S_FMT: OK" (was `fail: v4l2-test-formats.cpp(892): fmt_raw.g_colorspace() != V4L2_COLORSPACE_SRGB`) and `--get-fmt-video --get-fmt-video-out` must show sRGB / sRGB / ITU-R 601 / Full Range on both queues; the GStreamer regression loop of section 5 (9 pipelines) must reach EOS.)
- (series note) Note: ~/orangepi5/work/_out/integration/MANIFEST.md records 0711-0714 as "built W=1 only; the board runs hantro without them" at integration time; kernels 5-11 (patches 0001-1408 and later) contain them in-tree, so the board has booted and encoded JPEG with them, but no run of the TESTING.md checks was recorded.

## hantro-multicore

- **0701** 01 TESTED: ~/orangepi5/work/_out/hantro-multicore/RESULTS.md: the 4-commit drop-in module (01+02+03+0704) on the Orange Pi 5 kept the single-core behaviour of the G1 (VP8 decode md5 identical to stock, 60 IRQs on fdb50000) and AV1 (md5 identical) instances and the JPEG encoder output identical to stock for NV12/I420/YUY2 1080p and NV12 4K, which exercises the split probe for every variant on the SoC. (v7.3-based kernel; this rebase is compile-tested only.)
- **0702** 02 TESTED: same file: single-core variants unchanged (above), and the per-core curr_ctx/watchdog path was exercised by the multi-core runs (IRQs on all four cores, 600 IRQs per 600-frame single stream).
- **0703** 03 TESTED: same file: dmesg "bound fdba4000/8000/c000 ... using 4 cores", one /dev/video node; 1/2/4/8 parallel 1080p NV12 gst v4l2jpegenc streams at 62.1/119.6/216.0/223.1 fps vs 62.1/65.1/67.5/67.9 fps stock with the IRQs spread over fdba0000/4000/8000/c000; all 4/8 parallel outputs md5-identical to stock; v4l2-compliance unchanged (48/49, same pre-existing colorspace failure); two modprobe -r/modprobe cycles clean with 0704. (v7.3-based kernel; the next-20261030 rebase with the runtime-PM clock handling is compile-tested only.)

## hantro-robust

- **0709** 01 TESTED: ~/orangepi5/work/_out/needtest/0709/*.log: dt_binding_check on media/rockchip,rk3568-vepu.yaml rc=0 and CHECK_DTBS=y on rk3588s-orangepi-5.dtb clean; ~/orangepi5/work/_out/needtest/phase1-reads.txt: live DT reset-names "axi ahb" with reset ids 0x163/0x164 .. 0x169/0x16a on video-codec@fdba0000/4000/8000/c000, all four encoders probed and encoding (0711 run). (was NEEDS TEST: on the Orange Pi 5 with the DTB of patch 5, `tr '\0' ' ' < /proc/device-tree/video-codec@fdba0000/reset-names` shows "axi ahb" and the four encoders still probe and encode (dt_binding_check on the yaml is a build and was not run here).)
- **0704** 02 TESTED: ~/orangepi5/work/_out/hantro-multicore/RESULTS.md: `modprobe -r hantro_vpu && modprobe hantro_vpu` twice with a 1 s gap on the drop-in module panicked (SError in vsi_iommu_suspend) without this patch and was clean with it, with the AV1 decoder bound; encodes/decodes re-checked afterwards.
- **0707** 03 NEEDS TEST; side evidence from the 0712 wedges (~/orangepi5/work/_out/needtest/0711-0714/trace-fail.txt): hantro_watchdog -> rockchip_vpu2_enc_reset -> rk_iommu_attach_device/identity_attach/enable, no stall/paging timeouts, next jobs on the same core succeed; the fault_inject runs (debug module built in ~/orangepi5/work/_out/needtest/hantro-dbg, script ~/orangepi5/work/_out/needtest/scripts/hantro-robust-test.sh) were not run (board handed back). (NEEDS TEST entry: ~/orangepi5/work/_out/hantro-robust/TESTING.md test 4 (debug module, `echo 8 > /sys/module/hantro_vpu/parameters/fault_inject`, then 8 JPEG frames through v4l2-ctl on the VEPU121 with the patch-5 DTB): expect the rk_iommu page fault and one "frame processing timed out", NO "Enable stall request timed out"/"Disable paging request timed out", and the remaining frames valid; the TESTING.md procedure exists but no result file was found.)
- **0708** 04 NEEDS TEST; same side evidence as 0707 (IOMMU re-attached after the timeout, IOMMU runtime-suspends cleanly afterwards: `suspended usage=0` in the experiments), fault_inject 4/8 x5 not run. (NEEDS TEST entry: same TESTING.md tests 3 and 4 (fault_inject 4 and 8): after the timeout the next jobs on the same core must succeed and the IOMMU must runtime-suspend cleanly (`suspended usage=0`, no paging timeouts); repeat 5 times.)
- **0710** 05 NEEDS TEST for the pulse; the DT part is proven (resets present on all four nodes, see 0709) and the reset ran once per wedge (rockchip_vpu2_enc_reset in the trace). (NEEDS TEST entry: as 01 plus TESTING.md test 4 (the reset pulse only works once the DT describes the lines); optional: `devmem 0xfd7c0ab0` low 16 bits read 0 outside the pulse.)
- **0705** (dropped from this series) 
- **0706** (dropped from this series) 
- (series note) Note: a module containing 0704-0708 (branch hantro-robust-mc) ran on the board under the VEPU121 H.264 encoder work (~/orangepi5/work/_out/vepu121-h264enc/RESULTS.md, 2026-10-29), which is regression evidence (encodes work) but exercises none of the recovery paths.

## hdmi-frl-fixes

- **1202** 01 1202: TESTED: ~/orangepi5/work/_out/audio/RESULTS.md: "Hardware results after the reboot": PCM open at 4K60 FRL, modesets 4K60->4K120->4K60 and 4K60 FRL->1080p TMDS->4K60 FRL reprogrammed ACR on each atomic_enable (kprobes: acr_tmds tmds=185625000 at 1080p, acr_frl lane_gbps=10 at 4K), stream stayed RUNNING; HANDOFF.md: audible through 4K60/4K120 FRL/1080p TMDS mode changes. The frl_configure() hunk (rate fallback during training) itself was not provoked (link trained at 10G x 4 every time).
- **1203** 02 1203: TESTED: ~/orangepi5/work/_out/hdmi-10bpc/RESULTS.md and HANDOFF.md 08:30/08:40: 4K60 10 bpc RGB FRL batch (cases A-F) all camera GOOD with the drop-in; the A/B run without it was also GOOD on this TV, so the patch is verified not to regress and to pass bpc=10 to the PHY in FRL mode, but it is a consistency fix, not needed for the picture here.
- **1207** 03 1207: TESTED: ~/orangepi5/work/_out/hdmi-wedge/RESULTS.md: finding 4 (every probe during FRL logged "Resetting CRTC to restore SCDC status" and retrained) and the Summary (0001 in the deployed updates/opi5-hdmi-wedge drop-in, verified with the wedge runs: probes no longer retrain; topics.conf hdmi-frl-fixes "yes").
- **1208** 04 1208: TESTED: ~/orangepi5/work/_out/hdmi-wedge/RESULTS.md Summary: waiting for IPI_CLK_OFF in .atomic_mode_set -> 10/10 + 5/5 GOOD on the 4096 YUV420 -> 4096 10 bpc FRL trigger (previously ~1/2 failed), 16/16 separate-commit variants, run-2 order 13/13; ~/orangepi5/work/_out/hdmi-10bpc-k10/runs/ab-A.log: every W1..W3 wedge case GOOD on a 7.3.0-10 test kernel.
- **1209** 05 1209: TESTED: same evidence as 04 (the glue call is what makes the helper run).
- **1213** 06 1213: TESTED: ~/orangepi5/work/_out/hdmi-clk/RESULTS.md section 7: LINK_CONFIG0 = 0 and FLT_CONFIG1 = 0 in every TMDS step after an FRL mode (was 0x100 / 0x0f), camera GOOD.
- **1214** 07 1214: BLOCKED: needs camera; TV EDID with HF-VSDB Max_TMDS_Character_Rate 600 -> 340 MHz prepared for debugfs edid_override (~/orangepi5/work/_out/needtest/1214/tv-edid-tmds340.bin) so 3840x2160@60 8 bpc must use FRL; script section in ~/orangepi5/work/_out/needtest/scripts/display-tests.sh. (NEEDS TEST entry: the branch it adds (FRL link whose pixel clock fits the TMDS limit) never decided on this TV (all FRL modes used were above the PHY-PLL limit and went to the CRU anyway, hdmi-clk/RESULTS.md section 7). Prove it with a sink whose max TMDS character rate is below 594 MHz, or by forcing FRL for 3840x2160@60 8 bpc through the series' link selection, and check in clk_summary that dclk_vop0 stays on the CRU (not the PHY PLL) and the picture is GOOD. The refactor itself ran for every mode of the fix2 matrix without regression.)
- **1215** 08 1215: TESTED: ~/orangepi5/work/_out/hdmi-clk/RESULTS.md section 7 (fix2): 3840/4096x2160@59.94 10 bpc FRL now -EINVAL (were 500 MHz = 50.5 Hz, measured from vblank timestamps), all exactly clockable modes 27 MHz..1188 MHz accepted and measured within 20 ppm, camera GOOD; section 9: wedge regression 10/10 GOOD.
- **1908** (dropped from this series) 

## hdptx-lanes-pwroff

- **2224** 01 2224: TESTED (7.3.0-10hdptx installed 2026-11-01, kernel 11 #11 also contains it): ~/orangepi5/work/_out/hdmi-10bpc-k10/runs/pwrchk/trace.txt: on each HDMI CRTC ACTIVE=0 commit, rk_hdptx_phy_power_off writes fed60000.phy reg=81c (LNTOP_REG(0207)) val=0 before consumer_put; lanes stay 0 through the 3 s off window; power_on writes val=f and the picture returns. runs/hdptx-B: 80 GOOD / 22 off, 0 BLACK/SCRAMBLED (camera, lights off), 0 'Failed to get PHY lane lock', 3/3 s2idle. Never read regmap debugfs registers on this board (panics).

## hevc-encode-uapi

- **0811** 01: TESTED: ~/orangepi5/build/kunit-hevc-enc-uapi/test.log: KUnit on UML (2026-10-29, source = the opi5/hevc-enc-uapi branch these patches were exported from) wrote byte-exact VPS/SPS/PPS/AUD/slice headers using these NAL/profile/slice-type definitions, 19/19 RBSP tests pass (KUnit evidence for a helper patch, not hardware proof).
- **0812** 02: TESTED: ~/orangepi5/work/_out/rkvenc-hevc/board-run-k10.txt: on the Orange Pi 5 (kernel 10 build containing the patch) the VEPU580 driver's HEVC_ENCODE_PARAMS control was set per request and HEVC_ENCODE_FEEDBACK read back on every picture of 30+ streams ("feedback errors: 0"), v4l2-compliance 44/49 with 0 warnings (the 5 failures are the tool not knowing stateless encoders).
- **0813** 03: TESTED: ~/orangepi5/build/kunit-hevc-enc-uapi/test.log: 19/19 byte-exact header tests pass (KUnit, helper patch); and ~/orangepi5/work/_out/rkvenc-hevc/board-run-k10.txt: the VPS/SPS/PPS it writes head every stream FFmpeg decoded with 0 errors on the board.
- **0814** 04: TESTED: ~/orangepi5/build/kunit-hevc-enc-uapi/test.log: "v4l2-hevc-enc-rbsp: pass:19 fail:0 skip:0 total:19" (the patch is the test itself; KUnit evidence).
- **0815** 05: TESTED: ~/orangepi5/build/kunit-hevc-enc-uapi/test.log: 4/4 core tests (GOP, hw slice header, intra-only, validate) pass (KUnit, helper patch); and ~/orangepi5/work/_out/rkvenc-hevc/board-run-k10.txt: RPS/DPB/reference-list resolution and feedback of the core ran under the VEPU580 driver for GOP 1/10/30, LTR and TMVP streams that decode in FFmpeg with 0 errors.
- **0816** 06: TESTED: ~/orangepi5/build/kunit-hevc-enc-uapi/test.log: "v4l2-hevc-enc: pass:4 fail:0 skip:0 total:4" (the patch is the test itself; KUnit evidence).
- **0817** 07: TESTED (host): ~/orangepi5/work/_out/needtest/0817/RESULT.txt + htmldocs.log/htmldocs-base.log: `make SPHINXDIRS=userspace-api/media htmldocs` (Sphinx 9.2.0) on the upstream/hevc-encode-uapi tip and on its base: 13 warnings each, all pre-existing (diff empty); ext-ctrls-codec-stateless.html contains V4L2_CID_STATELESS_HEVC_ENCODE_PARAMS/_FEEDBACK with the flat-tables rendered. (was NEEDS TEST: `make SPHINXDIRS=userspace-api/media htmldocs` on the series tip (only a docutils + rstFlatTable check was done, see work/_out/hevc-enc-uapi/DESIGN.md "0 new messages"); documentation has no board test.)

## iep2

- **0911** 01 TESTED: ~/orangepi5/work/_out/iep2/RESULTS.md: board run 3 lists the controls (deinterlacing_mode default Bob, output_one_frame_per_field) and exercised bob/MA x frame/field rate through them; v4l2-compliance -s 57/57 covers the control enumeration.
- **0912** 02 TESTED: ~/orangepi5/work/_out/iep2/RESULTS.md: dt_binding_check and CHECK_DTBS clean on 2026-10-29, and the node described by it probed on the Orange Pi 5 (device + IOMMU on shared GIC SPI 117).
- **0913** 03 TESTED: ~/orangepi5/work/_out/iep2/RESULTS.md: final build f79075dcb (diff-identical to 0913) ran as a module on the Orange Pi 5: v4l2-compliance -s 57/57, 32 deinterlace runs 576i/1080i NV12/NV16 TFF/BFF bob/MA frame/field rate without errors (PSNR 35-37 dB), bypass bit-exact, 50 STREAMOFF/ON + 30 open/close cycles, 0 IOMMU faults, runtime PM suspended idle; also ~/orangepi5/work/_out/maxout/RESULTS.md (IEP2 driven by iep-test in the 50-cycle torture, part 2).
- **0914** 04 TESTED: ~/orangepi5/work/_out/iep2/RESULTS.md: the combined board DTB carried exactly these iep/iep_mmu nodes (dt/0001-...patch is identical) and the device probed with them in runs 2 and 3.
- (series note) Note: the two carry-back code changes (constant instead of module parameter with the same value; modern PM_OPS macros) were not run on the board; they do not alter the tested code paths but need the user's compile test.

## iommu-rockchip-reset

- **1804** 01 TESTED: ~/orangepi5/work/_out/rkvdec-reset/RESULTS.md section 6 and 7: the first P3 run (KREV=2, KASAN kernel) oopsed in rk_iommu_irq+0x490 = log_iova() (rockchip-iommu.c:569/628, "KASAN: probably wild-memory-access") during fault injection; with the patch (KREV=3) the "fault while page table lost to reset" path was taken 14 times in the 3178-recovery P3 run (logs/p3-intree/summary.txt, dmesg.txt), every fault acknowledged, 0 KASAN/oops.

## ohci-platform-resume

- **1103** TESTED: ~/orangepi5/work/_out/suspend/RESULTS.md: test kernel 7.3.0-opi5-susp (pkg 7.3.0-susp2 = stack 321 + 1104 + this patch, section "Proof (2026-10-30 21:52-22:50)") ran 55 fast s2idle cycles with 0 wedges and 0 resets (proof-susp2/proof50, proof30, proof-copy-usb summaries) plus 20 OHCI runtime PM cycles, where the unmodified ohci_resume() wedged on every fast resume before (PF1/PF2 2/2 PASS with the PHYs powered first vs ~25/25 wedges); the OHCI resume path with the PHY bracket ran on every cycle.

## opi5-dts-fixes

- **1001** TESTED (01): ~/orangepi5/work/_out/workaround-removal/board/boot-v2.txt (kernel #4, 2026-10-30, combined board DT with rgmii-id): `init for RGMII_ID`, YT8531 PHY bound, no delay warnings; ~/orangepi5/work/_out/maxout/RESULTS.md (same day/kernel): end0 940 Mbit/s receive, 0 rx errors; the board has run every test since on this DT (ssh/scp/streaming). TX direction only exercised by normal traffic, no iperf -R style TX line-rate number after the change (FIXLIST #24 can be closed on the RX/link evidence or after a 30 s iperf3 upload).
- **1002** TESTED: ~/orangepi5/work/_out/needtest/phase1-reads.txt + boot-k11.txt: no "supply vcc" message in the kernel 11 boot log; `regulator_summary` lists spi5.0-vcc under vcc_1v8_s3 (spi5.0 = spi:spi-nor). (was NEEDS TEST: (02): on the board DT (contains it since 2026-10-29): `dmesg | grep 'supply vcc'` must print nothing and `cat /sys/kernel/debug/regulator/regulator_summary | grep -B1 spi5.0` must list spi5.0-vcc under vcc_1v8_s3 (the message is present in the pre-DT log ~/orangepi5/work/_out/iep2/journal-storm1.txt line 693; no post-DT log captured the spi-nor probe).)
- **1003** NEEDS TEST; the live DT carries rockchip,reset-mode = <0> at /spi@feb20000/pmic@0 (~/orangepi5/work/_out/needtest/1003/dt-property.txt); the regmap-read proof needs a boot with trace_event=regmap:regmap_reg_read (no debugfs register reads), which needs the user's approval now. (NEEDS TEST entry: (03): on the board DT: `sudo cat /sys/kernel/debug/regmap/spi2.0/registers | grep ^72:` must read 02 (RST_FUN = 0) and `reboot`/`poweroff` still work (value was already 0x02 before the property, so the only observable is that nothing changed).)
- **0001** TESTED: premise corrected: the patch adds a plain rk3588s-orangepi-5-sata.dts (#include of the 5.dts + node overrides), not an overlay, so `make dtbs` builds it with dtc (~/orangepi5/work/_out/needtest/0001/RESULT.txt, rk3588s-orangepi-5-sata.dts: sata0 okay, pcie2x1l2 disabled, sata-port target-supply = vcc3v3_pcie20). The DTB built from the k11 tree is byte-identical (md5 6f51fbb1e5281f9dac16f818262c5a3c) to /usr/lib/linux-image-7.3.0-opi5/rockchip/rk3588s-orangepi-5-sata.dtb that U-Boot loads on the board; kernel 11 boot (~/orangepi5/work/_out/needtest/0001/boot-sata.txt, phase1-reads.txt): model "Xunlong Orange Pi 5 (M.2 SATA)", fe210000.sata present and fe190000 absent, "SATA link up 6.0 Gbps", UDMA/133, root on /dev/sda1. (was NEEDS TEST: (04): build with `make dtbs` (the overlay application test produces rk3588s-orangepi-5-sata.dtb) and boot that combined DTB: SATA link 6.0 Gbps, root on the SSD, pcie2x1l2 absent. The board boots a hand-merged DTB with the same three node changes daily (~/orangepi5/work/_out/shutdown-hang/RESULTS.md: SATA UDMA/133, 0 ata errors), but the overlay form itself has not been built or applied.)
- **1004** TESTED (host): ~/orangepi5/work/_out/needtest/1004/symbols.txt: `fdtget rk3588s-orangepi-5b.dtb /__symbols__ gmac1` = /ethernet@fe1c0000 (same on the 5 and 5-sata DTBs built with -@ from the k11 tree). (was NEEDS TEST: (05): `make dtbs` then `fdtget arch/arm64/boot/dts/rockchip/rk3588s-orangepi-5b.dtb /__symbols__ gmac1` prints a path (compile-level; no 5B board to apply an overlay on).)

## opi5-dts-usbc-dp-a

- **1005** 01 TESTED: ~/orangepi5/work/_out/dp-smooth/RESULTS.md: with this DT (kernel 7.3.0-opi5, patches/linux incl. 1005) the USB-C dock enters DP Alt Mode (pin assignment D, 2x HBR2), DP-1 runs the monitor at 4K30 next to HDMI, pin assignment D->C->D switches and the dock's USB3 devices work; ~/orangepi5/work/_out/tcpm/RESULTS.md 100/100 attach cycles configure DP Alt Mode on this connector description; ~/orangepi5/work/_out/dp-altmode/RESULTS.md: CHECK_DTBS=y clean for rk3588s-orangepi-5 / -5b / -5-sata (endpoint@a fix included).

## opi5-dts-usbc-dp-b

- **1201** 01 TESTED: ~/orangepi5/work/_out/audio/RESULTS.md: "DP0: speaker-test as a normal user on plughw:dp0: dw-dp 'audio prepare with 2 channels using DAI=1' (SPDIF), audio SDP sent (prepare rc 0), hw_ptr +48k frames/s, no xrun, rc 0" and dp-4k30/RESULTS.md "the dp0 ELD shows the LU28R55 (DisplayPort); a 5 s speaker-test on hw:dp0 ran without errors" -- signal-level only; "Whether sound comes out needs ears" (audible check pending; the reviewer note says so). The renamed card ("RK3588 DP0") itself has not been booted; the rename does not change the DAI link.

## panthor-suspend-clk

- **0512** TESTED: ~/orangepi5/work/_out/gpu-npu/RESULTS.md ("Results on the fixed kernel", steps 3-6): kernel #2 of 2026-10-29 17:38 with 0501-0514 incl. the SCMI core clock DT -- `min_freq=1000000000` written while suspended: no SError, next job at 1017-1024 MHz; max_freq=300 MHz honoured; 200 suspend/resume jobs and 3 min sustained load without faults.

## phy-usbdp-fixes

- **0267** 01 TESTED: ~/orangepi5/work/_out/dp-smooth/RESULTS.md: "Verified after the 22:23 reboot (all three modules from updates/opi5-dp-smooth)": D->C->D pin-assignment switches, DPCD 0x202 = 77 00 within 1-3 s after each switch and dw-dp "short HPD -> Retraining link -> 2 lanes at 5400 MHz, CR and EQ succeeded"; before this patch the retrain ran but clock recovery failed on every lane (22:11 update).
- **0270** 02 TESTED: ~/orangepi5/work/_out/workaround-removal/RESULTS.md: section 3 board evidence (board/usb3-{before,after,after2}.txt): stock PHY module 3 hub disconnects in 3 exit/entry transitions and a wedged dock; with 0270 two runs of 3x exit/entry + D->C->D with O_DIRECT reads from the dock's reader: 0 disconnects, 0 read errors; section 8 (0270 v2, boots boot-{no0270,alt,v2}.txt, usb3-v2.txt): attach-time re-init gives 0 AUX errors across forced detects after 3x exit/entry, D->C->D and another exit/entry, DP-1 detected from boot.

## pmdomain-rockchip-clk-put

- **2107** NEEDS TEST + finding: the deferral experiment (pwm-clock from a module as a PD_FEC clock, fw_devlink=permissive) hung the boot before userspace; host review (~/orangepi5/work/_out/needtest/RESULTS.md Finding 2) shows the probe error path cannot remove nested domains (pm_genpd_remove -EBUSY) and devm frees them, so a deferred domain clock is not survivable on RK3588 regardless of 2107. (NEEDS TEST entry: no Orange Pi 5 log ever contains "failed to get clk at index" (no domain clock defers on this board), so the error path never ran here; to prove it, make a domain clock provider defer (e.g. build clk-rk3588 or the SCMI clock as a module, or temporarily return -EPROBE_DEFER from a domain clock lookup) and check that the boot log has no `clk_put` WARNING and that the deferral is reported through dev_err_probe (/sys/kernel/debug/devices_deferred).)

## rkjpegd

- **0901** (dropped from this series) 
- **0902** (dropped from this series) 
- **0903** (dropped from this series) 
- **1401** (dropped from this series) 
- (series note) 01 TESTED: ~/orangepi5/work/_out/jpeg-dec/RESULTS.md: binding passed dt_binding_check and CHECK_DTBS on the board DTBs; the node probed (hardware id 0xdb1f0005) on the Orange Pi 5.
- (series note) 02 TESTED: ~/orangepi5/work/_out/jpeg-dec/RESULTS.md: decoded 4:2:0/4:2:2/4:4:4/GREY vectors at 66-80 dB PSNR vs FFmpeg, 4K MJPEG at 145 fps, UVC MJPEG camera live, v4l2-compliance 48/48, truncated/corrupt/garbage streams returned ERROR without faults.
- (series note) 03 TESTED: ~/orangepi5/work/_out/jpeg-dec/RESULTS.md: with this node in the combined DTB the decoder and its IOMMU probed (IOMMU group 3), ACLK_JPEG_DECODER ran at 594 MHz, runtime PM suspended when idle.
- (series note) 04 TESTED: ~/orangepi5/work/_out/codec-quality/RESULTS.md: with the fix as a drop-in module v4l2-compliance -s -f on rockchip-jpegd went from a 900 s DQBUF hang to 57/57, and the 640x360 JPEG decode stayed at 63.28 dB vs FFmpeg.
- (series note) (Evidence is for our driver only; irrelevant for sending since the group is dropped.)

## rkvdec-ccu

- **2001** 01 TESTED: rkvdec-reset/RESULTS.md section 8 + rkvdec-ccu/RESULTS.md "Update (8)": every CCU-mode decode (fluster, 600/600 bit-exact, reopen cycles) goes through the detach helper; the k4c/k5 v4l2-mem2mem.ko exported it (58 existing symbol CRCs unchanged).
- **2002** 02 TESTED: same: job tracking in use for every CCU run; rkvdec-ccu/RESULTS.md "Update (8)" reopen.sh 50x3 and section 8 200x3 close/reopen cycles with a 4K stream, 0 hangs.
- **2003** 03 TESTED: same: H.264/HEVC CCU runs (HEVC 227 fps, 600/600 bit-exact, fluster identical) use per-slot tables.
- **2004** 04 TESTED (binding exercised, not schema-checked): the CCU node per this binding was booted as the test DT overlay (rkvdec-ccu/dt/rk3588-vdec-ccu-overlay.dts, same content) -> "rkvdec rockchip,rk3588-vdec: 2 cores, decoding with the CCU" (rkvdec-reset/RESULTS.md section 8 boot line). TESTED (host): ~/orangepi5/work/_out/needtest/2004/*.log: `make dt_binding_check DT_SCHEMA_FILES=media/rockchip,rk3588-vdec-ccu.yaml` (and rockchip,vdec.yaml) rc=0, no warnings; CHECK_DTBS=y with both schemas on rk3588s-orangepi-5.dtb and -5-sata.dtb clean (1 ccu + 2 vdec nodes matched). (was NEEDS TEST: for the schema: `make dt_binding_check DT_SCHEMA_FILES=media/rockchip,rk3588-vdec-ccu.yaml` (the CCU agent ran it clean on the 7.3 branch per rkvdec-ccu/RESULTS.md status line; not re-run here per the brief).)
- **2005** 05 TESTED: rkvdec-ccu/RESULTS.md "Update (8)" + rkvdec-reset section 8: HEVC 4K 130 -> 227 fps, H.264 67 -> 121 fps, 600/600 bit-exact, fluster identical per vector to single core (HEVC 146/147, AVC_V1 129/135, FR-EXT 65/69, VP9 230/305), two streams 121.6/121.4 fps.
- **2006** 06 TESTED via the equivalent overlay (rkvdec-ccu/dt/rk3588-vdec-ccu-overlay.dts, byte-equivalent node content) on every CCU board run; the dtsi patch itself has only been compiled (kernel 9 build). TESTED: ~/orangepi5/work/_out/needtest/2006/boot-ccu.txt (kernel 11 boot log with the packaged DTB): "rkvdec rockchip,rk3588-vdec: 2 cores, decoding with the CCU". (was NEEDS TEST: strictly: boot the kernel-9 DTB and check the "decoding with the CCU" line.)
- **2007** 07 TESTED: rkvdec-ccu/RESULTS.md "Update (8)" ccu-verify fps A/B includes the cache toggle (pipeline/cache/ccu_hw A/B parameters) with 600/600 bit-exact; every later CCU run has the caches enabled and flushed.
- **2008** 08 TESTED: rkvdec-ccu/RESULTS.md "Update (4)": k4b wedge (JVT-AVC_V1 30/135, field-coded streams corrupting the following ones) fixed by the POC high bits; later AVC_V1 129/135 identical to single core.
- **2009** 09 TESTED: rkvdec-ccu/RESULTS.md "Update (4)/(5)": core 1 stuck with HCBP2_HHI_A + HCMP1_HHI_A fixed; rkvdec-reset section 8 ccu-repro 5/5 for every pair; FMO pair x50 680 recoveries.
- **2010** 10 TESTED: rkvdec-ccu/RESULTS.md "Update (8)": JVT-AVC_V1 run repeated with field pairs on both cores (fieldpair=Y), identical to single core; rkvdec-reset section 8 FR-EXT 65/69.
- **2011** 11 TESTED: same as 10 (interlaced vectors of JVT-AVC_V1/FR-EXT decoded with both fields in flight).
- **2012** 12 TESTED: rkvdec-ccu/RESULTS.md "Update (4)" (VP9 hardware adaptation, tables byte-identical to MPP's writers on 10000 random headers in the host harness) and "Update (8)": VP9 600/600 bit-exact in CCU mode, fluster VP9 230/305 identical to single core, 137 -> 147 fps.
- **2013** 13 TESTED: same as 12 (VP9 in CCU mode).
- **2014** 14 TESTED: rkvdec-reset/RESULTS.md section 8 (P4 with 1805): watchdog sweep 4/6/8 ms 100/97/38 timeouts, 1734 recoveries, 0 reports, bit-exact after each step; fluster victims HCBP1_HHI_A/HCHP3_HHI_A no longer fail next to failing vectors.
- **2015** 15 TESTED: rkvdec-ccu/RESULTS.md "Update (8)" (context use-after-free and job-start/reset race found and fixed in the k5 slot; reopen.sh 50x3 0 hangs) and rkvdec-reset section 8 (200x3 close/reopen with KASAN, 0 reports).
- **2016** 16 TESTED: rkvdec-ccu/RESULTS.md "Update (8)" root cause (2): HCHP3_HHI_A (frame and field pictures in flight) decoded wrong once in a few runs before, identical to single core after; rkvdec-reset section 8 HCHP3_HHI_A + Hi422FREXT17 5/5.
- **2017** 17 TESTED: rkvdec-reset/bisect/stats/runs.tsv: without it ("ccu") 3 of 10 JVT-AVC_V1 runs had the 7 SVA_* vectors (or HCBP1_HHI_A) differ from single core; with it ("varF") 0 of 10, plus svasp 64/64 bit-exact (SVA vectors next to SP1_BT_A), 0 timeouts/KASAN/oops/canary; integration/MANIFEST.md: reproducer 8/8.
- (series note) Evidence common to the series: the P4 KASAN runs in ~/orangepi5/work/_out/rkvdec-reset/RESULTS.md section 8 (the 16xx series on 1801/1802/1804/1805 = 2001-2016 minus the 2017 fix; logs/p4-ccu, logs/p4-ccu3) and the final stats run ~/orangepi5/work/_out/rkvdec-reset/bisect/stats/runs.tsv + stats-final/log (variants "ccu" = 2001-2016, "varF" = with the reset-work fix 2017: 10/10 JVT-AVC_V1 runs with no vector differing from single-core, svasp 64/64 bit-exact, 0 timeouts/KASAN/oops/canary; integration/MANIFEST.md "Kernel 9" table ties 2017 to that run). The official kernel 9 build (7.3.0-9, first with 2001-2017 in patches/linux) was built "assume it's good" and has NOT been booted/tested yet (MANIFEST.md, BOARD-QUEUE.md step 2); the KASAN test modules carry the same code.

## rkvdec-colmv

- **1405** 01 TESTED: ~/orangepi5/work/_out/codec-quality/RESULTS.md ("rkvdec H.264 4K ~65 fps" item and the colmv section): H.264 4K/1080p 240 frames give the same per-frame checksum with compression off and on, 30/30 bit-exact vs FFmpeg (verify2.txt), 65.4 -> 68.4 fps 4K and 214 -> 234 fps 1080p on the board; bytes written by the hardware into a poisoned colmv area measured (4147200 uncompressed vs up to 4146800 compressed for H.264 4K); fluster JVT-AVC_V1 129/135 and JVT-FR-EXT 65/69 with it on (work/_out/rkvdec-ccu/RESULTS.md section 3 baseline without, section 8 / rkvdec-reset P3 with) -- same results.
- **1406** 02 TESTED: same file: HEVC 4K 240 frames same checksum off/on, 30/30 bit-exact vs FFmpeg, 98.6-102.8 -> 104.6 fps; compressed size 556064-556128 bytes vs 522240 uncompressed measured (basis of the reservation in 01); fluster JCT-VC-HEVC_V1 146/147 unchanged.

## rkvdec-reset

- **1801** 01 TESTED: ~/orangepi5/work/_out/rkvdec-reset/RESULTS.md section 7 (logs/p3-intree): KASAN kernel 7.3.0-5kasan3 with 1801+1802+1804, watchdog sweep 4/6/8 ms (858/395/2 and 569/413 timeouts racing the interrupt, the case where the stock driver hit the NULL dereference in rkvdec_irq_handler+0x1c, HANDOFF.md 2026-10-30 10:28 panic): no crash, 600/600 bit-exact after.
- **1802** 02 TESTED: same file, section 7: 3178 recoveries, 2241 timeouts, 96 injected faults, 109 IOMMU faults all on injected IOVAs, 0 KASAN/ODEBUG/lockdep/list/oops/WARNING/hung, 0 canary hits; FMO pair x50 350 recoveries; bit-exact 600/600 x3 after every step; 30 min dual 4K; fluster HEVC 146/147, AVC_V1 129/135, FR-EXT 65/69, VP9 230/305 identical to the unpatched reference (logs/fluster-rr-stock vs fluster-rr-p3-intree); 200 reopen cycles x3 variants. Section 3b shows the stock driver panicking under the same watchdog sweep.
- **1805** 03 TESTED: same file, section 9 (logs/p5-intree-1805): in-tree + 1805 on the KASAN kernel with the 112 MiB RAM canary: 1300 recoveries, 902 timeouts, 0 "still busy", 0 KASAN/ODEBUG/lockdep/list/oops/WARNING/hung, 0 RAM-canary and physical-canary hits; the P4 CCU panic that motivated it (section 8) no longer reproduced with it (P4 rerun: 6 ms sweep point clean).

## rkvdec-rga-v7.4-sync

- **0101** (dropped from this series) 
- (series note) 01 n/a (DROP; the upstream commits it mirrors are what the stack runs on the board through the kernel builds 5-11).

## rkvdec-vp9-fixes

- **0605** 01 TESTED: ~/orangepi5/work/_out/rkvdec-vp9/NOTES.md: fluster VP9-TEST-VECTORS 224/305 on the Orange Pi 5 with the VP9 series running on the multi-core driver (updates/opi5-multicore module), which only works through this port; every later VP9 run (vp9-conf, vp9-perf, rkvdec-reset P3/P4 fluster VP9 230/305) ran on it.
- **0606** 02 NEEDS TEST; userspace half ready: GStreamer v4l2codecs VP9 non-keyframe resize patch + arm64 plugin build in ~/orangepi5/work/_out/needtest/0606/ and gst-wip/ (BOARD-TEST.md), not run on the board. (NEEDS TEST entry: decode vp90-2-21-resize_inter_320x180_5_1-2.webm (and the other 23 resize_inter vectors) on the Orange Pi 5 with a userspace that keeps the CAPTURE queue across the non-keyframe size change (GStreamer v4l2slvp9dec patched per work/_out/rkvdec-vp9/NOTES.md "TODO (GStreamer half)", or a request-API test program), and compare the output with libvpx frame by frame. So far only regression-checked: ~/orangepi5/work/_out/vp9-conf/RESULTS.md ("after-resize-patch.md" baseline 224/305 includes it, no regression).)
- **0607** 03 TESTED: ~/orangepi5/work/_out/vp9-conf/RESULTS.md: with the per-frame register clear (commit 1 of the fix1 module) vp90-2-09-lf_deltas went FAIL (25/30 frames wrong from display frame 5) -> PASS, fluster 224 -> 230/305 with no regression (board results fix1.md).
- **0608** 04 TESTED: ~/orangepi5/work/_out/vp9-conf/RESULTS.md: with the segmentation-map rule (commit 2 of fix1) vp90-2-09-aq2, vp90-2-15-segkey_adpq, vp90-2-19-skip, -skip-01, -skip-02 went FAIL -> PASS (frame-by-frame cmp.py vs libvpx), fluster 230/305.
- **0609** 05 TESTED: ~/orangepi5/work/_out/vp9-perf/RESULTS.md: done handler 437 -> 81 us per frame (ftrace), fps table of the commit message measured on the board, per-frame md5 of 2700 frames identical with the cached table on and off (md5-slot1.txt).

## rkvenc

- **0831** 01: TESTED: ~/orangepi5/work/_out/rkvenc/RESULTS.md: `dt_binding_check` on this schema is clean ("Build and checks" table) and the two nodes written to it (patch 3) probe and bind both cores on the Orange Pi 5 (board-run2.txt "registered encoder core 0/1"); a binding has no other code path.
- **0832** 02: TESTED: ~/orangepi5/work/_out/rkvenc/board-run2.txt (summarised in RESULTS.md "Board test results", 2026-10-29): H.264 1080p/4K I-only and GOP-30 at QP 22-37, profiles 66/77/100, CBR 2-20 Mbit/s, two parallel 4K streams on both cores, runtime PM; every stream decodes in FFmpeg with 0 errors at 39-53 dB PSNR; v4l2-compliance 44/49, 0 warnings; and ~/orangepi5/work/_out/rkvenc-hevc/board-run-k10.txt (2026-11-01, kernel 10 build) repeats the H.264 regression on the final code.
- **0833** 03: TESTED: ~/orangepi5/work/_out/rkvenc/board-run2.txt: both cores (fdbd0000, fdbe0000) probe from these nodes with their clocks, resets, power domains, interrupts and IOMMUs; the parallel-stream test shows interrupts on both cores (+60 each) and no IOMMU faults.
- **0834** 04: TESTED: ~/orangepi5/work/_out/rkvenc-hevc/board-run-k10.txt: "H.264 regression (shared code changed)": 1080p GOP-30 QP 27 through the refactored helpers decodes with 0 errors at 47.3 dB, output byte-identical to before the refactor per RESULTS.md; the shared row-RC table and statistics read-back are exercised by every HEVC run below.
- **0835** 05: TESTED: ~/orangepi5/work/_out/rkvenc-hevc/board-run-k10.txt (and board-run2.txt, 2026-10-29): HEVC 1080p/4K at QP 22-37 GOP 1/30, TMVP/no-SAO/LTR/GOP-10/CQ variants, odd size with conformance window, CIF, CBR 2-20 Mbit/s, two parallel 4K streams on both cores; 0 FFmpeg decode errors, "feedback errors: 0" on every picture, 38-59 dB PSNR, both cores runtime-suspended afterwards. (FIXLIST entry 26 "compile/KUnit only" is stale.)

## rtc-minute-alarm

- **1917** TESTED: ~/orangepi5/work/_out/suspend-k10/RESULTS.md (+ rtcwake-m-no-fixed.txt): deb 7.3.0-10rtc (k10 + this patch, branch opi5/rtc-minute-alarm-k10) -- `rtcwake -m no -s 15` arms 18:11:00 with alarm_IRQ: yes; 47/47 `rtcwake -m freeze -s 15` cycles woke from the hym8563 IRQ (unfixed 10dclkn1901: alrm_time 17:55:00, alarm_IRQ: no, board slept forever).

## smmu-v3-pcie-pd

- **0130** TESTED (01): ~/orangepi5/work/_out/shutdown-hang/RESULTS.md: dt_binding_check clean on arm,smmu-v3.yaml and the full-fix kernel (#2 2026-10-29 16:45, 0130-0134 + combined DTB) boots with the property consumed (pm_genpd: pcie on, fc900000.iommu listed).
- **0132** TESTED (02): same file: binding check clean, CHECK_DTBS clean for rk3588s-orangepi-5{,-sata} and rock-5b with the clocks property.
- **0133** TESTED (03): ~/orangepi5/work/_out/shutdown-hang/RESULTS.md "Board, full fix": clk_summary `aclk_mmu_pcie 1 2 ... Y iommu@fc900000`, 3 consecutive reboots with `reboot: Restarting system` and SPL 0.59 s later (was ~89 s via watchdog).
- **0131** TESTED (04): same file, "Serial evidence" reboot C: with power-domains alone pm_genpd shows `pcie on`, but the reboot still hangs at `arm-smmu-v3 fc900000.iommu: shutdown` -- proves the domain is held and that the clock patch is also required; fixed state in the full-fix run.
- **0134** TESTED (05): same file, full-fix run: clock held by the SMMU, reboot hang gone, SATA 6.0 Gbps, 0 ata errors.

## stmmac-dwmac-rk-delays

- **0400** TESTED: ~/orangepi5/work/_out/workaround-removal/board/boot-v2.txt: kernel #4 (image kernel with the patch, module dwmac-rk) and the rgmii-id board DT boot with "init for RGMII_ID" and no "Can not read property" lines; ~/orangepi5/work/_out/maxout/RESULTS.md (same kernel): end0 940 Mbit/s receive, 0 errors.

## tcpm-vdm-fixes

- **0271** 01 TESTED: ~/orangepi5/work/_out/tcpm/RESULTS.md: kernel 5 (0271-0274 in-tree) natural run r-k5b 100/100 dock attach cycles entered DP Alt Mode with 0 VDM timeouts; the resumed Discover Modes path (this patch) runs on every retry cycle of the injected test (20/20) and discovery reached COMPLETE with the DP SVID's mode found.
- **0272** 02 TESTED: ~/orangepi5/work/_out/tcpm/RESULTS.md: injected late-response test on kernel 5, stock tcpm.ko 0/20 (the dock's Not_Supported killed the unsent Discover SVIDs every cycle) vs fixed tcpm.ko 20/20 (Discover SVIDs resent, DP configured); plus 100/100 natural cycles.
- **0273** 03 TESTED: ~/orangepi5/work/_out/tcpm/RESULTS.md: injected test 20/20 cycles log "VDM response timeout, retry discovery (1)" and Discover SVIDs is resent after 100 ms, discovery COMPLETE, DP configured ~1.0-1.1 s after attach; 100/100 natural cycles with 0 timeouts.
- **0274** 04 TESTED: ~/orangepi5/work/_out/tcpm/RESULTS.md: injected test 20/20 cycles log "Ignoring unexpected VDM response 0xff00a042" for the late ACK and no Not_Supported is sent (stock: Not_Supported 0xbb0 sent, dock replies 0x690, discovery dead, 0/20).

## usb-port-pairing

- **1501** TESTED: ~/orangepi5/work/_out/usb3-port/RESULTS.md: kernel build 5 (stack with 1501-1504 and the DTB built from this binding, rk3588s-orangepi-5-sata-usb3port.dtb) shows "usb3-port1/peer -> usb6-port1" and the reverse link, i.e. the EHCI ports graph was parsed and consumed by the core; dt_binding_check (generic-ehci.yaml) and CHECK_DTBS for rk3588s-orangepi-5/-5-sata/-5b/-5-pro were clean on the v7.3 stack (static, not re-run on next per the brief).
- **1502** TESTED: ~/orangepi5/work/_out/usb3-port/RESULTS.md: same kernel 5 run: the EHCI root hub port and the xHCI SuperSpeed port are linked as peers across controllers ("usb3-port1/peer -> usb6-port1", reverse link exists), which only 02's connector pairing can produce.
- **1503** TESTED: ~/orangepi5/work/_out/suspend/RESULTS.md ("Extreme at 480M on the test kernel: on plain #5 the drive always enumerates first at HS via EHCI host1 (usb 4-1, 3.16 s) and switches to SS on host2 (usb 6-1, 3.76 s)") plus ~/orangepi5/work/_out/usb3-port/RESULTS.md ("usb 3-1: SuperSpeed peer port available, resetting" logged at 3.539 s on kernel 5) and FIXLIST.md #28 / HANDOFF.md 2026-10-30 20:45 (Extreme at 480M on kernels without 1501-1504, both the susp test kernel and the KASAN kernel): 03's reset fired and moved the SanDisk Extreme from the EHCI to 5 Gb/s on the xHCI at boot; the Ultra Fit case documents the one-reset-no-loop behaviour.
- **1504** TESTED: ~/orangepi5/work/_out/usb3-port/RESULTS.md: the DTB carrying this connector/graph description (kernel 5 and the current image DTB, usb3-port in the image per topics.conf) is what produced the peer links above; dtbs_check clean on the v7.3 stack.

## vop2-fixes

- **1211** 01 1211: TESTED: ~/orangepi5/work/_out/hdmi-clk/RESULTS.md: with the drop-in on kernel 7.3.0-7 VP0_CLK_CTRL reads 0x0a in RGB modes (dclk_out_div = dclk_core_div) instead of 0x0e with the garbage divider 3, and the fix2 matrix (1080p ... 4K120, 720x480) is camera GOOD with measured DCLKs within 20 ppm (section 7/8).
- **1212** 02 1212: TESTED: ~/orangepi5/work/_out/hdmi-clk/RESULTS.md: section 8, the sync polarities seen in dw-hdmi-qp VIDEO_INTERFACE_STATUS0 bits 17/18 now match the mode flags for +/+ (1080p, 2160p) and -/- (720x480) modes, camera GOOD for both.
- **1909** 03 1909: BLOCKED: needs camera. (NEEDS TEST entry: on a kernel >= 7.3.0-9 run ~/orangepi5/work/_out/vop2-underflow/v2/test/vop2uf-test.sh: cases ii-rg16-ytr-p35/47/53 must be rejected (RG16 modifier 0x...51 absent from IN_FORMATS) and ii-rg16-noytr-p35/47/53 / ii-xr24-ytr-p35 must scan out clean (camera, pbe=0). The kernel #10 display-matrix run (testmatrix-runs/tm/k10-hdmi) stopped after 140/850 cases, before the planes group, so this is unverified on hardware; only the failure it fixes is documented (HDMI-RUN1.md).)
- **1301** 04 1301: TESTED: ~/orangepi5/work/_out/vop2-underflow/RESULTS.md: "Verification" with the fixed rockchipdrm module (boots of 22:33/22:45): 3840x2160@120 Cluster0 + Esmart0 full-screen layers, previously ~120000 POST_BUF_EMPTY/s, now 0 bad frames in 720 frames; dual-display weston (HDMI 4K60 + DP 4K30, two players, 10+ min) 0 underflows; port assignment read back from the window registers.
- **1302** 05 1302: TESTED: ~/orangepi5/work/_out/vop2-underflow/RESULTS.md: same runs; POST_BUF_EMPTY now counted as one line per bad frame (plus "callbacks suppressed" gone), vblank IRQ rate back to ~30/s at 4K120 with underflow cases, no lost vblank events in planetest 120/120 flips.
- **1910** 06 1910: BLOCKED: needs camera. (NEEDS TEST entry: on a kernel >= 7.3.0-9 run ~/orangepi5/work/_out/vop2-underflow/v2/test/vop2uf-test.sh: case i-c0+e0+dp(-test) (console Cluster0 linear + Esmart0 4K120 + DP Cluster1 4K30) must be refused with "AXI port N would fetch ... MB/s" in dmesg, control cases ctl-4k60-rgb / ctl-4k120-rgb must stay clean. Not yet run (board busy; the k10 matrix did not reach the planes group).)

## vop2-video-pll-a

- **1911** 01 1911: TESTED: ~/orangepi5/work/_out/testmatrix-runs/tm/k10-hdmi/results.tsv: on kernel 7.3.0-opi5 #10 (contains 1911-1915) the 3840x2160@120/1186813 (cases 12, 109-117) and 3840x2160@60/593407 / 4096x2160@60/593407 10 bpc FRL (cases 68-70, 131-132) modes were committed ("ok") with pbe=0, which 1215 refuses unless the computed V0PLL rate is exact; computed settings cross-checked against the host model in ~/orangepi5/work/_out/hdmi-frl-pll/RESULTS.md (593407000 -> 593406990 Hz, 1186813000 -> 1186812988 Hz). No independent frequency measurement of the PLL output on those runs (the hdmi-clk vblank-timestamp measurement was not repeated).
- **1912** 02 1912: TESTED: same evidence (the flag is what lets V0PLL take those rates; the 119.88 Hz cases are camera GOOD).

## vop2-video-pll-b

- **1913** 01 1913: TESTED: ~/orangepi5/work/_out/testmatrix-runs/tm/k10-hdmi/results.tsv: kernel 7.3.0-opi5 #10 (with 1913-1915 and the matching DTB) found "pll_v0" (no probe error, the V0PLL path worked, see 02), i.e. the documented clock name is what the driver and DT use.
- **1914** 02 1914: TESTED: same file: 3840x2160@120/1186813 8 bpc RGB/YUV444/YUV422 and 10 bpc FRL (cases 12, 109-117) and 3840/4096x2160@60/593407 10 bpc FRL (cases 68-70, 131-132) committed "ok" with pbe=0 (refused by 1215 without this patch, hdmi-clk/RESULTS.md section 7), 119.88 Hz cases camera GOOD; the 59.94 10 bpc cases have "UNTRUSTED" camera verdicts (classifier, not a kernel finding). The resulting DCLK was not measured on that kernel; the DP/eDP/DSI branch (non-HDMI outputs get V0PLL too) was not exercised.
- **1915** 03 1915: TESTED: same (the DT with pll_v0 was in use on kernel #10).

## Per-patch summary

| patch | series | status |
|---|---|---|
| 0001 | opi5-dts-fixes | TESTED |
| 0101 | rkvdec-rga-v7.4-sync (dropped) | DROP |
| 0130 | smmu-v3-pcie-pd | TESTED |
| 0131 | smmu-v3-pcie-pd | TESTED |
| 0132 | smmu-v3-pcie-pd | TESTED |
| 0133 | smmu-v3-pcie-pd | TESTED |
| 0134 | smmu-v3-pcie-pd | TESTED |
| 0267 | phy-usbdp-fixes | TESTED |
| 0268 | dp-altmode-hpd | TESTED |
| 0269 | dp-altmode-hpd | TESTED |
| 0270 | phy-usbdp-fixes | TESTED |
| 0271 | tcpm-vdm-fixes | TESTED |
| 0272 | tcpm-vdm-fixes | TESTED |
| 0273 | tcpm-vdm-fixes | TESTED |
| 0274 | tcpm-vdm-fixes | TESTED |
| 0400 | stmmac-dwmac-rk-delays | TESTED |
| 0401 | asoc-rockchip-pcm-order | TESTED |
| 0402 | asoc-rockchip-pcm-order | TESTED |
| 0403 | asoc-rockchip-pcm-order | NEEDS TEST |
| 0512 | panthor-suspend-clk | TESTED |
| 0514 | devfreq-resume-freq | TESTED |
| 0605 | rkvdec-vp9-fixes | TESTED |
| 0606 | rkvdec-vp9-fixes | NEEDS TEST |
| 0607 | rkvdec-vp9-fixes | TESTED |
| 0608 | rkvdec-vp9-fixes | TESTED |
| 0609 | rkvdec-vp9-fixes | TESTED |
| 0701 | hantro-multicore | TESTED |
| 0702 | hantro-multicore | TESTED |
| 0703 | hantro-multicore | TESTED |
| 0704 | hantro-robust | TESTED |
| 0705 | hantro-robust (dropped) | DROP |
| 0706 | hantro-robust (dropped) | DROP |
| 0707 | hantro-robust | NEEDS TEST |
| 0708 | hantro-robust | NEEDS TEST |
| 0709 | hantro-robust | TESTED |
| 0710 | hantro-robust | NEEDS TEST |
| 0711 | hantro-jpeg-enc-fixes | TESTED |
| 0712 | hantro-jpeg-enc-fixes | FAILED on kernel 11 |
| 0713 | hantro-jpeg-enc-fixes | NEEDS TEST |
| 0714 | hantro-jpeg-enc-fixes | TESTED |
| 0808 | h264-encode-fixes | TESTED |
| 0809 | h264-encode-fixes | TESTED |
| 0811 | hevc-encode-uapi | TESTED |
| 0812 | hevc-encode-uapi | TESTED |
| 0813 | hevc-encode-uapi | TESTED |
| 0814 | hevc-encode-uapi | TESTED |
| 0815 | hevc-encode-uapi | TESTED |
| 0816 | hevc-encode-uapi | TESTED |
| 0817 | hevc-encode-uapi | TESTED |
| 0824 | hantro-h264-enc | TESTED |
| 0825 | hantro-h264-enc | TESTED |
| 0826 | hantro-h264-enc | TESTED |
| 0831 | rkvenc | TESTED |
| 0832 | rkvenc | TESTED |
| 0833 | rkvenc | TESTED |
| 0834 | rkvenc | TESTED |
| 0835 | rkvenc | TESTED |
| 0901 | rkjpegd (dropped) | DROP |
| 0902 | rkjpegd (dropped) | DROP |
| 0903 | rkjpegd (dropped) | DROP |
| 0911 | iep2 | TESTED |
| 0912 | iep2 | TESTED |
| 0913 | iep2 | TESTED |
| 0914 | iep2 | TESTED |
| 1001 | opi5-dts-fixes | TESTED |
| 1002 | opi5-dts-fixes | TESTED |
| 1003 | opi5-dts-fixes | NEEDS TEST |
| 1004 | opi5-dts-fixes | TESTED |
| 1005 | opi5-dts-usbc-dp-a | TESTED |
| 1101 | dw-dp-aux-fixes | TESTED |
| 1102 | cpufreq-unlisted-freq | NEEDS TEST |
| 1103 | ohci-platform-resume | TESTED |
| 1104 | dwc3-s2idle | TESTED |
| 1201 | opi5-dts-usbc-dp-b | TESTED |
| 1202 | dw-hdmi-qp-fixes, hdmi-frl-fixes | TESTED |
| 1203 | hdmi-frl-fixes | TESTED |
| 1204 | dw-dp-pcon | TESTED |
| 1205 | dw-dp-pcon | TESTED |
| 1206 | dw-dp-pcon | BLOCKED |
| 1207 | hdmi-frl-fixes | TESTED |
| 1208 | hdmi-frl-fixes | TESTED |
| 1209 | hdmi-frl-fixes | TESTED |
| 1210 | dw-dp-pcon | BLOCKED |
| 1211 | vop2-fixes | TESTED |
| 1212 | vop2-fixes | TESTED |
| 1213 | hdmi-frl-fixes | TESTED |
| 1214 | hdmi-frl-fixes | BLOCKED |
| 1215 | hdmi-frl-fixes | TESTED |
| 1301 | vop2-fixes | TESTED |
| 1302 | vop2-fixes | TESTED |
| 1401 | rkjpegd (dropped) | DROP |
| 1402 | hantro-codec-fixes | TESTED |
| 1403 | hantro-codec-fixes (dropped) | HOLD (not in a series yet) |
| 1404 | hantro-codec-fixes | TESTED |
| 1405 | rkvdec-colmv | TESTED |
| 1406 | rkvdec-colmv | TESTED |
| 1408 | hantro-codec-fixes | TESTED |
| 1501 | usb-port-pairing | TESTED |
| 1502 | usb-port-pairing | TESTED |
| 1503 | usb-port-pairing | TESTED |
| 1504 | usb-port-pairing | TESTED |
| 1801 | rkvdec-reset | TESTED |
| 1802 | rkvdec-reset | TESTED |
| 1804 | iommu-rockchip-reset | TESTED |
| 1805 | rkvdec-reset | TESTED |
| 1901 | dwc3-s2idle | TESTED |
| 1902 | dw-dp-aux-fixes | BLOCKED |
| 1903 | dw-dp-aux-fixes | BLOCKED |
| 1904 | dw-dp-aux-fixes | BLOCKED |
| 1905 | fw-devlink-sync-state | TESTED |
| 1906 | dw-hdmi-qp-fixes | BLOCKED |
| 1907 | dw-hdmi-qp-fixes | BLOCKED |
| 1908 | hdmi-frl-fixes (dropped) | DROP |
| 1909 | vop2-fixes | BLOCKED |
| 1910 | vop2-fixes | BLOCKED |
| 1911 | vop2-video-pll-a | TESTED |
| 1912 | vop2-video-pll-a | TESTED |
| 1913 | vop2-video-pll-b | TESTED |
| 1914 | vop2-video-pll-b | TESTED |
| 1915 | vop2-video-pll-b | TESTED |
| 1916 | hantro-codec-fixes | TESTED |
| 1917 | rtc-minute-alarm | TESTED |
| 2001 | rkvdec-ccu | TESTED |
| 2002 | rkvdec-ccu | TESTED |
| 2003 | rkvdec-ccu | TESTED |
| 2004 | rkvdec-ccu | TESTED |
| 2005 | rkvdec-ccu | TESTED |
| 2006 | rkvdec-ccu | TESTED |
| 2007 | rkvdec-ccu | TESTED |
| 2008 | rkvdec-ccu | TESTED |
| 2009 | rkvdec-ccu | TESTED |
| 2010 | rkvdec-ccu | TESTED |
| 2011 | rkvdec-ccu | TESTED |
| 2012 | rkvdec-ccu | TESTED |
| 2013 | rkvdec-ccu | TESTED |
| 2014 | rkvdec-ccu | TESTED |
| 2015 | rkvdec-ccu | TESTED |
| 2016 | rkvdec-ccu | TESTED |
| 2017 | rkvdec-ccu | TESTED |
| 2107 | pmdomain-rockchip-clk-put | NEEDS TEST |
| 2224 | hdptx-lanes-pwroff | TESTED |

## Totals (unique patches)

- ours: 141
- TESTED: 111 (needtest run 2026-11-01: +11, see ~/orangepi5/work/_out/needtest/RESULTS.md)
- FAILED, fix proposed: 1 (0712)
- BLOCKED (camera / USB-C dock regression, or user action): 10 (1902 1903 1904 1906 1907 1214 1909 1910 1206 1210)
- NEEDS TEST: 10 (0713 0707 0708 0710 1102 1003 0403 2107 0606, and 0712 re-test)
- DROP (not to be sent, evidence moot): 9
- unassigned / no evidence line: 0
