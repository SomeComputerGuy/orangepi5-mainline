# Bugzilla text for patch 0002 (draft; not filed, not sent)

Product/Component: Core :: Audio/Video: Playback
Patch: `0002-Queue-a-VP9-superframe-or-AV1-temporal-unit-worth-of-hw-frames.patch`, against
Firefox 159.0.1 (release source; applies to `dom/media/platforms/ffmpeg/FFmpegVideoDecoder.{cpp,h}`).
Status: board A/B test bhw-5 (work/_out/browser-hwdec/bhw-5) pending. File it only once that A/B
shows the effect (the user decides whether to send).

## Summary
Hardware-decoded 4K60 AV1 with hierarchical GOPs drops frames: the 3-frame hardware video queue
(`media.video-queue.hw-accel-size`) is shorter than one AV1 temporal unit's worth of decode work.

## Description
`MediaDecoderStateMachine::GetAmpleVideoFrames()` keeps `media.video-queue.hw-accel-size` (3)
decoded frames ahead when the decoder is hardware accelerated. The comment in StaticPrefList.yaml
says hardware decoding is fast, so a small queue keeps latency low. That is true per frame. It is
not true per packet for VP9 and AV1. With pyramid GOPs (libaom/SVT-AV1 defaults, YouTube's AV1),
the first temporal unit of each mini-GOP carries the hidden ALTREF and the hidden frames of each
layer below it, and only then the shown frame. The following TUs are mostly `show_existing_frame`
and cost nothing. Hardware decoders (VA-API, V4L2 request, Vulkan) run one job per frame, so
playback stalls for N frame-decode-times once every mini-GOP and then catches up.

Measured on an RK3588 (Hantro VPU981 AV1 decoder, libva-v4l2-request, Firefox 159.0.1, Wayland):
- 4K60 AV1 clip with 16-frame mini-GOPs: ~10 ms per decoded frame (p50 10.05 ms, p99 18.6 ms,
  59.6 decodes/s), so the average rate keeps up, but 6-7 frames (~60 ms) go into the first TU of
  each mini-GOP: that is 3.6 frame periods, longer than the 3-frame queue covers.
- Dropped frames over 20 s: 6.16% and 3.08% (two runs, default queue) vs 2.41% with
  `media.video-queue.hw-accel-size=6`. 1080p clips drop 1.8-2.4% (the presentation floor of
  this setup). Chrome 157 drops 0.17% with the same driver.
- (bhw-5 adds three runs of each build: TODO fill in from work/_out/browser-hwdec/bhw-5/ff-out/SUMMARY.txt.)

## Proposed fix (attached patch)
The decoder already has a way to report this: `MediaDataDecoder::PropertyName::MinNumVideoBuffers`
(used by AppleVTDecoder for slow Intel decoders, bug 1230641, and on Android). GetAmpleVideoFrames()
takes max(pref, MinNumVideoBuffers). The patch makes the Linux FFmpeg video decoder report 8 when it
decodes VP9 or AV1 in hardware, outside low-latency mode:
- 8 is the bound from the bitstream: a hidden frame is only useful if it is stored in one of the 8
  reference slots (NUM_REF_FRAMES), and a VP9 superframe holds at most 8 frames;
- the FFmpeg hardware frame pool already sizes for it (8 references + EXTRA_HW_FRAMES 9);
- H.264/HEVC (one frame per access unit) keep the 3-frame default; SW decoding is not affected;
- the queue only fills while playing ahead; preroll becomes 5 frames instead of 2 (still under 100 ms
  at 60 fps).

Alternatives considered:
- Raising `media.video-queue.hw-accel-size` for everyone: it would also grow H.264/HEVC queues,
  which don't need it, and the pref is a global knob, not a per-codec property.
- Deriving the depth from the stream: AV1 sequence headers don't signal the GOP structure; the
  8-slot bound is the only one known at decoder init.
- Windows (D3D11VA) and macOS (VideoToolbox) decode AV1/VP9 the same way and could use the same
  property. The patch is limited to MOZ_USE_HWDECODE + MOZ_WIDGET_GTK (what was tested).

## Test notes
- The patch logs (FFmpegVideo:5) "Hardware av1 decoding: asking for at least 8 queued frames".
- Pref overrides still work: a larger `media.video-queue.hw-accel-size` wins (max).
