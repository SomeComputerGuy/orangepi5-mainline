# GStreamer follow-ups (deferred by the user: kernel work first)

Found while testing the new/updated kernel drivers on the Orange Pi 5 (GStreamer 1.28.x on Ubuntu 26.10).

1. **v4l2slvp9dec: inter-frame resolution changes** — drops frames ("Drop frame on non-keyframe format change") because it doesn't call `gst_vp9_decoder_set_non_keyframe_format_change_support()`. Kernel side (rkvdec VDPU381 accepts frames smaller than the CAPTURE format) is done on `opi5/rkvdec-vp9-7.3`. Plan: `work/_out/rkvdec-vp9/NOTES.md`. Expected gain: the 24 shrink-only `vp90-2-21-resize_inter_*` fluster vectors.
2. **v4l2convert can't deinterlace** — v4l2transform copies `interlace-mode` to the CAPTURE caps, the IEP2 driver (correctly) returns `V4L2_FIELD_NONE`, and negotiation fails ("Device wants progressive interlacing"). Needs v4l2transform to allow interlaced→progressive when the device reports it (plus field-rate output support). Details: `work/_out/iep2/RESULTS.md`.
3. **Element naming depends on probe order** — the first-probed m2m device gets the plain name (`v4l2convert`, `v4l2slh264dec`); others get `v4l2videoNconvert` etc. With IEP2 present, `v4l2convert` is the deinterlacer, not RGA; `v4l2slh264dec` is the 1080p-only Hantro G1, not rkvdec. Options: GStreamer ranks per device capability, or naming by driver/card. (User said they don't care about the H.264 naming; still relevant for convert.)
4. **v4l2slh264enc / VEPU121** — the stateless H.264 encoder element only exists in Paul Kocialkowski's tree / draft MR !5676; our encoder is tested with our own client.
5. **v4l2jpegdec single-image EOS hang** — with exactly one JPEG, GStreamer sends V4L2_DEC_CMD_STOP before dequeuing the driver's initial SOURCE_CHANGE event; after the drain it reads that stale event as a resolution change, renegotiates and waits forever. Two or more frames work. Driver follows dev-decoder.rst. Details: `work/_out/jpeg-dec/RESULTS.md`.
6. **v4l2jpegdec asks for 128 MiB OUTPUT buffers** per JPEG (driver allows up to 256 MiB) — wasteful; GStreamer should size from the image.
7. **Benchmarking pitfall / possible GStreamer improvement** — `fakesink` doesn't advertise GstVideoMeta, so v4l2codecs decoders CPU-copy every frame ("GstVideoMeta support required, copying frames"). Measured 4K VP9: 63 fps with fakesink vs 137 fps with `fakevideosink` (8-bit), 52 vs 115 (10-bit). Always benchmark with `fakevideosink` (or a real sink with video meta). Earlier HEVC/H.264 decode fps from today used fakesink and are underestimates. Details: `work/_out/vp9-perf/RESULTS.md`.

## kmssink can't change the display mode for overlay-plane video (2026-10-29)
`kmssink force-modesetting=true plane-id=<Esmart>` fails ("failed to configure video mode"): it sets the
mode with legacy drmModeSetCrtc using the video (NV12) buffer on the primary plane, which the RK3588
Cluster primary can't scan out. It also only picks the first mode with a matching WxH (no refresh
choice). Fix: an atomic modeset with an XR24 primary + the video on the overlay plane, and a refresh-rate
property. The kernel switches modes live without issue (modetest -a; work/_out/modesweep/report).

## 8. decodebin3/playbin3 picks the 1080p-only Hantro H.264 decoder for 4K streams (2026-10-29, codec-quality)
Symptom: playbin3 on a 3840x2160 H.264 stream (Big Buck Bunny 4K60) selects `v4l2slh264dec` (Hantro G1 /
RK3588 VPU121, max 1920x1088) and fails with "Failed to configure H264 decoder" instead of using rkvdec.
Cause: GStreamer only. The kernel reports the limits correctly: VIDIOC_ENUM_FRAMESIZES on the VPU121 OUTPUT
format S264 is `Stepwise 48x48 - 1920x1088 step 16/16` (MPEG-2 the same; VP8 too after kernel patch
"media: verisilicon: Don't offer VP8 above 1080p on the Rockchip VDPU2"). But v4l2codecs
(`sys/v4l2codecs/plugin.c` `register_video_decoder()`) registers every device's element with the codec's
*static* sink template (`video/x-h264, stream-format=..., alignment=au`, no width/height) and the same rank
(GST_RANK_PRIMARY + 1). ENUM_FRAMESIZES is only used on CAPTURE formats, for the scaler
(`gst_v4l2_decoder_enum_size_for_format`). decodebin3 sees two identical factories, takes the first
(by name), and doesn't fall back when the decoder later refuses the size at S_FMT.
Fix (GStreamer, gst-plugins-bad v4l2codecs): at registration, enumerate the OUTPUT format's frame sizes
(stepwise/continuous → `width=[min,max], height=[min,max]`) and register the element with that sink pad
template (per-device caps, as v4l2 stateful elements do via gst_v4l2_object_probe_caps). Then decodebin's
caps intersection skips Hantro for > 1080p. A secondary option is a rank per device capability. Workaround
until then: `GST_PLUGIN_FEATURE_RANK=v4l2slh264dec:NONE` (loses Hantro for <= 1080p, which is fine on RK3588
because rkvdec does everything) or set the rkvdec element's rank higher.
Kernel aside: rkvdec's VDPU381 frame-size ranges are "Continuous 1x1 - 65520x65520" (H.264) and 65472
(HEVC/VP9), far above the real hardware limits. Once GStreamer uses the ranges, they won't steer anything
away from rkvdec, but they should be tightened to the documented maximums (not done).
