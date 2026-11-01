# DP-1 4K30 (297 MHz) through the USB-C dock / DP->HDMI PCON: results

## Verdict
No 4K30 fault on the source side and no fault with the Samsung. With the Samsung on the dock, the
board drives 3840x2160@30 CEA (297 MHz, 82 % of 2-lane HBR2) correctly:
- The webcam shows crisp SMPTE bars (cam/run3-A.jpg, cam/b5-p1.jpg, cam/b5-p2.jpg).
- The PCON sink CRC equals the CRC of the RB timing that does work.
The Samsung's "all black" under GNOME is the greeter's dark uniform background on the
secondary monitor. The panel is lit (cam/b5-g4.jpg, cam/b5-g5.jpg), and the sink CRC
d346d346d346 has equal R/G/B CRCs, i.e. a uniform grey frame. Login/top bar are on the
primary HDMI monitor.
The Zerlon's striped 4K30 is still unexplained and needs that monitor reconnected (see the end).

## Evidence
- Link at 4K30: HBR2 x2, CR/EQ/symbol lock, interlane aligned. Symbol error counters (0x210-0x213)
  read 0x8000 (valid, 0 errors).
- PCON sink CRC (DPCD 0x246 = 0x20 TEST_CRC_SUPPORTED; TEST_SINK_START at 0x270; tools/crc.sh),
  modetest XR24 pattern, stable over 6 samples and across runs:
  1080p60 d00430118d0a, 1440p 6699d3e9200e,
  4K30 CEA 297 MHz e094ff653ce7, 4K30 CVT-RB 262.75 MHz (EDID override) e094ff653ce7.
  The active pixels received by the PCON are bit-identical for both 4K timings.
  This rules out the dw-dp TU/average_bytes_per_tu/init_threshold/HBLANK_INTERVAL settings,
  the bandwidth check, MSA and the VOP2 dclk (297.000 MHz exactly from gpll/4, quad pixel,
  same divider structure as 1080p) as causes of pixel corruption.
- The dw-dp TU maths and bandwidth_ok are identical to the Rockchip BSP dw-dp.c (develop-6.1).
- Kernel 7.3.0-5 vs -6: the extra patches (1103, 1104, 1203, 1801-1805) touch only usb,
  rkvdec, iommu and dw_hdmi_qp-rockchip.c. No DP/VOP2 change, so no regression from them.
  "4K worked before" was the Dell at 4K30 CVT-RB 262.75 MHz.
- Camera batches (batch5.log, cam/b5-*.jpg; control = 1440p bars, also saved as
  ../cam/reference-1440p-smpte.jpg):
  - p1 DP 4K30 XR24 linear, with HDMI at 4K60 (left over from gdm): bars OK, CRC e094ff653ce7.
  - p2 atomic DP 4K30 + HDMI 4K60, both XR24 linear, separate fbs on Cluster1/Cluster0:
    bars OK, CRC e094ff653ce7.
  - p3 XR30 linear on the cluster planes: modetest "failed to add fb" (no linear XR30 fb), not run.
  - g4 GNOME/gdm with DP 4K30 + HDMI 4K60 (both XR30 AFBC on Cluster1/Cluster0): Samsung lit,
    uniform greeter background, CRC d346d346d346.
  - g5 the same with HDMI at 1080p: identical.
  - run3 (07:28): 4K30 CEA with the PCON in DVI mode (0x3050 = 0) and in HDMI mode (0x3050 = 1),
    plus 4K30 RB: bars OK in all of them.
- PCON control: dw-dp leaves DPCD 0x3050 (PROTOCOL_CONVERTER_CONTROL_0) at 0 (DVI mode) and never
  reads the downstream port caps. The branch reports DPCD 1.2 but implements 0x3050 (write 1 reads back 1).

## Patch series: DP branch device / protocol converter support (as i915 does)
Made in build/series (git). Module: build/c/dw-dp.ko, vermagic 7.3.0-opi5.
1. 0001-drm-bridge-synopsys-dw-dp-Configure-DP-protocol-conv.patch
   - Reads the downstream port caps on every detect (dw_dp_link_parse).
   - On enable, for a branch with DPCD rev >= 1.3 (the same gate as i915), it writes:
     - 0x3050 = HDMI when the DFP is HDMI and display_info.is_hdmi, else DVI;
     - 0x3051 = 0 (no 4:4:4->4:2:0 conversion);
     - RGB->YCbCr conversion off via drm_dp_pcon_convert_rgb_to_ycbcr(aux, 0).
   - dw-dp always sends the format the sink is to receive, so no conversion is ever chosen.
     Using the PCON's 4:4:4->4:2:0 conversion is a possible follow-up.
   - DPCD rev: this dock reports 0x12 at 0x000, but 0x00E bit 7 is set and the extended caps
     at 0x2200 report rev 0x14. drm_dp_read_dpcd_caps() uses the extended caps, as in i915,
     so link->dpcd[DP_DPCD_REV] = 0x14 and i915 would program this PCON too.
     No quirk or probing is needed.
2. 0002-drm-bridge-synopsys-dw-dp-Respect-the-limits-of-a-br.patch
   - Caches the DFP limits when the EDID is read: drm_dp_downstream_max_bpc, max_dotclock,
     min/max_tmds_clock, is_tmds and 420_passthrough.
   - mode_valid rejects modes above the DFP dot clock or outside its TMDS range.
   - Output bus formats are capped by the DFP max bpc and the TMDS clock.
   - YCbCr 4:2:0 is offered only with a VSC SDP and, behind a TMDS converter, only with 4:2:0
     pass-through.
   - This PCON (DFP caps 0b f0 02 17) has max TMDS 600 MHz, 12 bpc and 4:2:0 pass-through.
   - FRL: the PCON advertises no FRL (port_cap[2] FRL bits = 0). HDMI 2.1 FRL link training
     (drm_dp_pcon_frl_*) is a follow-up; these patches don't touch FRL.
3. 0003-drm-bridge-synopsys-dw-dp-Re-detect-when-a-branch-s-.patch
   - On a short HPD from a branch, DOWNSTREAM_PORT_STATUS_CHANGED (0x204 bit 6) or a changed
     SINK_COUNT triggers full detection.
   - Detection already reports SINK_COUNT 0 as disconnected (existing code), so a dock with
     nothing on its HDMI port shows as disconnected.
checkpatch: clean except the expected missing Signed-off-by.

## Still open
- Zerlon "YDC PD22320W" striped at 4K30 CEA: the source stream is the same bit-exact stream that
  the Samsung displays correctly, so the problem is between the PCON's HDMI output and that
  monitor. Next test with the Zerlon on the dock, camera on it, in one batch:
  4K30 CEA with 0x3050 = 0 vs 1, and 4K30 CVT-RB (EDID override built with tools/edid-add-rb.py
  from ../hdmi-10bpc/dp-1-zerlon.edid). If 0x3050 = 1 fixes it, the candidate patch is the root fix.
  If only RB works, it's a PCON/monitor timing quirk and not a kernel bug.

## Deployment (board)
build/c/dw-dp.ko (patches 0001-0003) installed as
/lib/modules/7.3.0-opi5/updates/opi5-dp-pcon/dw-dp.ko, followed by depmod and update-initramfs.
The initramfs contains both updates/opi5-dp-pcon/dw-dp.ko and updates/opi5-hdmi10/rockchipdrm.ko.
Undo: remove updates/opi5-dp-pcon, run depmod -a 7.3.0-opi5 and update-initramfs -u -k 7.3.0-opi5,
then reboot.

## Post-patch test (batch6.log, cam/b6-*.jpg; reboot at 07:55, both drop-ins loaded, srcversions checked)
- DFP limits read at detect: max bpc 12, max dotclock 0 (not reported), TMDS 25-600 MHz.
  DP-1 mode list unchanged: 4K30 is preferred; 4K60 is still rejected by link bandwidth.
- The PCON is now in HDMI mode: 0x3050-0x3052 = 01 00 00 in every phase (it was 00 before).
- Samsung, sink CRCs identical to pre-patch, camera shows clean SMPTE bars:
  - 1440p control: 6699d3e9200e (cam/b6-ctl.jpg)
  - 1080p60: d00430118d0a (cam/b6-p1080.jpg)
  - 4K30 CEA 297 MHz: e094ff653ce7 (cam/b6-p4k30.jpg)
- GNOME greeter (monitors.xml: DP 1440p, HDMI 1080p): Samsung lit, uniform greeter background,
  CRC 921c921c921c (cam/b6-greeter.jpg). HDMI-A-1 connected at 1080p60, XR30 on Cluster0.
- Audio: the dp0 ELD shows the LU28R55 (DisplayPort); a 5 s speaker-test on hw:dp0 ran without
  errors (audio startup/prepare/unmute in dmesg). Whether sound comes out needs ears on the
  Samsung's headphone jack.
- Not tested: unplug/replug of the monitor on the dock's HDMI port (patch 0003 path). Ask the user.
  With dynamic debug on (module dw_dp +p, already enabled until reboot), dmesg should show
  "Downstream port status changed", and DP-1 should go disconnected/connected.
- Quirk patch not needed: this dock's extended DPCD rev is 1.4, so the i915-identical >= 1.3
  gate applies.

## Zerlon batch (about 75 s; tools/zerlon-batch.sh, zerlon-rb4k30.edid)
Phases: 1440p control; 4K30 CEA in HDMI mode (patched default); 4K30 CEA forced to DVI
(0x3050 = 0, test only); 4K30 CVT-RB (EDID override). Captures land in /tmp/zb-*.jpg.
- If HDMI mode is clean and DVI is striped: patch 0001 is the root fix for the Zerlon.
- If both are striped and RB is clean: PCON/monitor timing quirk, not a source bug.

## Zerlon batch (08:12-08:16, camera framed on the Zerlon, patches 1204-1206 deployed)
| phase | DP sink CRC | PCON 0x3050-52 | Zerlon (camera) |
|---|---|---|---|
| 1440p control | 6699d3e9200e | 01 00 00 | (control) |
| 4K30 CEA, HDMI mode (default with 1204) | e094ff653ce7 | 01 00 00 | scrambled stripes |
| 4K30 CEA, DVI mode (forced) | e094ff653ce7 | 00 00 00 | identical stripes |
| 4K30 CVT-RB 262.75 MHz | e094ff653ce7 | 01 00 00 | identical stripes |
| 4K30 CEA, HDMI_FORCE_SCRAMBLING (0x3051=08) | - | 01 08 00 | identical stripes |
| 4K30 CEA, autonomous scrambling disabled (0x3051=04) | - | 01 04 00 | (same run) |
Conclusion: the PCON receives bit-identical pixels (same CRC the Samsung displays correctly) and no source-side PCON control
changes the Zerlon's picture. The Zerlon works at 4K60 on another dock. Not a source/kernel bug: this dock's HDMI output
and the Zerlon at 4K are incompatible. Optional confirmation: this dock + Zerlon on the Windows PC. Captures cam/zb-*, cam/zs-*;
script tools/zerlon-batch.sh, tools/zerlon-scramble.sh.
