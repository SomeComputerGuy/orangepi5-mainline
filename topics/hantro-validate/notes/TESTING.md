# hantro-validate: on-board test procedure (Orange Pi 5, RK3588S, kernel 7.3.0-opi5)

Branch `opi5/hantro-validate`, module
`~/orangepi5/build/wt-hantro-validate/ext/hantro/hantro-vpu.ko` (signed, vermagic `7.3.0-opi5`).
Only `hantro-vpu.ko` changes; v4l2-core is unchanged.

## 0. Install the module

```sh
# on the board (copy the .ko over first, e.g. to /tmp)
sudo modprobe -r hantro_vpu          # see note: avoid if the encoder is already wedged
sudo install -m644 /tmp/hantro-vpu.ko /lib/modules/$(uname -r)/updates/hantro-vpu.ko
sudo depmod -a && sudo modprobe hantro_vpu
modinfo -F filename hantro_vpu       # must point at updates/
D=/dev/v4l/by-path/platform-fdba0000.video-codec-video-index0
v4l2-ctl -d $D --info | head -5
sudo dmesg -C
```

Note: if the old module already wedged the encoder (IOMMU stall), reboot instead of
`modprobe -r`; unloading in that state froze the board before.

Test input (frames of the *aligned* size, 1920x1088 NM12 = 3133440 bytes/frame):

```sh
gst-launch-1.0 videotestsrc num-buffers=8 pattern=smpte ! \
  video/x-raw,format=NV12,width=1920,height=1088 ! filesink location=src.nv12
```

After every test below: `dmesg | grep -Ei 'iommu|hantro|timed out|vpu'` must be empty
(except for the expected messages listed).

## 1. Coded-format/raw-format consistency (fix: "Keep the encoder coded size in sync with OUTPUT")

Reproducer (a):

```sh
v4l2-ctl -d $D --set-fmt-video-out=width=1920,height=1080,pixelformat=NM12 \
  --set-fmt-video=pixelformat=JPEG --stream-out-mmap=4 --stream-mmap=4 \
  --stream-from=src.nv12 --stream-to=out_a.mjpeg --stream-count=8
v4l2-ctl -d $D --get-fmt-video --get-fmt-video-out --get-selection-output target=crop
```

- Before: CAPTURE stayed 96x32 (sizeimage 6768) while OUTPUT was 1920x1088; IOMMU page
  faults at IOVA ~0, "frame processing timed out", "rk_iommu ... Enable stall request timed out".
- After: no dmesg errors; 8 frames dequeued; `out_a.mjpeg` is non-empty. Note that the
  `--get-fmt-*` in a new process sees a fresh context (defaults), so check the sizes in the
  same command instead:
  `v4l2-ctl -d $D --set-fmt-video-out=width=1920,height=1080,pixelformat=NM12 --set-fmt-video=pixelformat=JPEG --get-fmt-video --get-fmt-video-out`
  must show CAPTURE JPEG 1920x1088, sizeimage >= 4178544 (624 + 1920*1088*2), and OUTPUT
  NM12 1920x1088.
- Check the output: `ffprobe out_a.mjpeg` (or `gst-launch-1.0 filesrc location=out_a.mjpeg ! jpegparse ! jpegdec ! fakesink`)
  decodes 8 frames of 1920x1088.

Crop (selection) still works and is the only allowed divergence:

```sh
v4l2-ctl -d $D --set-fmt-video=pixelformat=JPEG \
  --set-fmt-video-out=width=1920,height=1080,pixelformat=NM12 \
  --set-selection-output=target=crop,left=0,top=0,width=1920,height=1080 \
  --get-selection-output=target=crop --get-fmt-video \
  --stream-out-mmap=4 --stream-mmap=4 --stream-from=src.nv12 \
  --stream-to=out_crop.mjpeg --stream-count=8
```

Expected: crop 1920x1080, CAPTURE width/height 1920x1080, JPEGs decode as 1920x1080,
no dmesg errors. An invalid crop (e.g. width=1280) is replaced by the full 1920x1088 frame.

Busy check: with CAPTURE buffers allocated for a small size, a larger OUTPUT S_FMT must
return EBUSY (it would need bigger CAPTURE buffers). There is no single v4l2-ctl line for
this; v4l2-compliance (section 3) covers basic busy behaviour.

## 2. CAPTURE sizeimage minimum (fix: "Enforce a minimum CAPTURE sizeimage for the encoder")

Reproducer (b):

```sh
v4l2-ctl -d $D --set-fmt-video-out=width=1920,height=1080,pixelformat=NM12 \
  --set-fmt-video=width=1920,height=1080,pixelformat=JPEG --stream-out-mmap=4 --stream-mmap=4 \
  --stream-from=src.nv12 --stream-to=out_b.mjpeg --stream-count=8 --verbose 2>&1 | tail -20
ls -l out_b.mjpeg
```

- Before: the stale 6768-byte sizeimage of the 96x32 default was accepted for 1920x1088;
  `out_b.mjpeg` was 0 bytes.
- After: CAPTURE sizeimage >= 4178544; `out_b.mjpeg` non-empty and decodes as 8 frames.

Explicit small/large sizeimage:

```sh
v4l2-ctl -d $D --try-fmt-video=width=1920,height=1080,pixelformat=JPEG,sizeimage=1000   # -> 4178544
v4l2-ctl -d $D --try-fmt-video=width=1920,height=1080,pixelformat=JPEG,sizeimage=8000000 # -> 8000000 kept
```


## 3. v4l2-compliance (fix: "Report fixed JPEG colorimetry on the encoder")

```sh
v4l2-compliance -d $D 2>&1 | tee compliance.txt | grep -E 'fail|FAIL|Total'
v4l2-compliance -d $D -s 2>&1 | tee compliance-s.txt | grep -E 'fail|FAIL|Total'   # streaming
v4l2-ctl -d $D --get-fmt-video --get-fmt-video-out | grep -iE 'colorspace|transfer|ycbcr|quant'
```

- Before: `fail: v4l2-test-formats.cpp(892): fmt_raw.g_colorspace() != V4L2_COLORSPACE_SRGB`,
  `test VIDIOC_S_FMT: FAIL`.
- After: test VIDIOC_S_FMT: OK. Both queues report Colorspace sRGB, Transfer Function sRGB,
  YCbCr/HSV Encoding ITU-R 601, Quantization Full Range. Compare the totals with the
  pre-fix run; no new failures expected. Any remaining failures were not analysed here.

## 4. Defensive run-path check (fix: "Refuse JPEG encode jobs with inconsistent geometry")

Not reachable from userspace any more after fix 1. Indirect check: none of the tests above
print `inconsistent geometry` or `CAPTURE buffer too small` in dmesg. If it ever triggers,
the job completes with V4L2_BUF_FLAG_ERROR instead of programming the hardware.

## 5. GStreamer regression check

```sh
for fmt in NV12 I420 YUY2; do
  for res in 1280x720 1920x1080 3840x2160; do
    w=${res%x*}; h=${res#*x}
    echo "== $fmt $res"
    gst-launch-1.0 -q videotestsrc num-buffers=60 ! video/x-raw,format=$fmt,width=$w,height=$h ! \
      v4l2jpegenc ! fakesink || echo "FAIL $fmt $res"
  done
done
# sanity check the content of one
gst-launch-1.0 -q videotestsrc num-buffers=10 ! video/x-raw,format=NV12,width=1920,height=1080 ! \
  v4l2jpegenc ! jpegparse ! jpegdec ! videoconvert ! fakesink silent=false -v 2>&1 | grep -m1 caps
gst-launch-1.0 videotestsrc num-buffers=1 ! video/x-raw,format=NV12,width=1920,height=1080 ! \
  v4l2jpegenc ! filesink location=frame.jpg && file frame.jpg
```

Pass: all 9 pipelines reach EOS without errors, `frame.jpg` is a 1920x1080 (or 1920x1088
if GStreamer does not set the crop) baseline JPEG, no dmesg errors.
Note: the CAPTURE buffers are now at least header + w*h*2 bytes (about 16.6 MB at 4K)
even if GStreamer asks for less; if a 4K pipeline fails to allocate, check CMA/IOMMU
allocation (`dmesg`) and report it.

Also check that the new fixed colorimetry (sRGB / BT.601 / full range on both queues
instead of V4L2_COLORSPACE_JPEG) does not break caps negotiation: run with
`GST_DEBUG=v4l2*:4` once and look for colorimetry warnings.

## Pass/fail summary

| Test | Pass criterion |
|---|---|
| (a) | 8 non-empty JPEGs, no IOMMU fault / timeout in dmesg |
| (b) | out_b.mjpeg > 0 bytes, sizeimage >= 4178544 |
| crop | 1920x1080 JPEGs, no dmesg errors |
| compliance | VIDIOC_S_FMT OK, no new failures |
| GStreamer | 9/9 pipelines EOS, no dmesg errors |
