# Bugzilla text for bug 2080696 (draft; not sent)

Product/Component: Core :: Security: Process Sandboxing
Bug: https://bugzilla.mozilla.org/show_bug.cgi?id=2080696 (UNCONFIRMED, filed by Christian Bartels)
Patch: `0001-Bug-2080696-Allow-V4L2-stateless-Request-API-decoder.patch`, against
mozilla-firefox/firefox main eed57099f5fd (2026-10-30). Based on attachment 9657436.

---

## Comment to post with the patch

**Summary.** On SoCs whose video decoders are V4L2 *stateless* devices (Rockchip RK3588/RK3399,
Allwinner, MediaTek, Raspberry Pi 5 HEVC), VA-API is provided by a VA driver that drives the
V4L2 Request API (libva-v4l2-request). `vaapitest` runs unsandboxed, succeeds, and
about:support reports hardware decoding as available. In the RDD process, though, the driver
finds no decoder and Firefox falls back to software decoding. With `MOZ_DISABLE_RDD_SANDBOX=1`
the same build decodes in hardware.

**What the sandbox blocks.** We traced every open and ioctl the driver makes (libva-v4l2-request
1.2, plus a fork with RK3588 HEVC support):

| Access | Current RDD policy | Needed for |
|---|---|---|
| `/dev/videoN` (M2M decoder), `VIDIOC_*` (type `'V'`) | already allowed (`AddV4l2Dependencies`, `kVideoType`) | buffers, controls, streaming |
| `/dev/mediaN` that owns the decoder, O_RDWR | **denied** by the broker | request allocation, topology |
| `MEDIA_IOC_G_TOPOLOGY`, `MEDIA_IOC_REQUEST_ALLOC` on it (type `'\|'`) | **SIGSYS/denied** by seccomp | finding the video node; one request per frame |
| `MEDIA_REQUEST_IOC_QUEUE`, `MEDIA_REQUEST_IOC_REINIT` on the request fds (type `'\|'`) | **denied** by seccomp | submitting and recycling requests |
| `/sys/dev/char/<maj>:<min>/uevent` of the video node, read-only | **denied** | mapping the topology's devnum to `/dev/videoN` (libudev-based users such as FFmpeg's v4l2-request hwaccel open the canonical `/sys/devices/...` path) |
| `poll` on request and video fds, `mmap(MAP_SHARED)` of V4L2 buffers, `VIDIOC_EXPBUF` dma-bufs, DRM render node | already allowed | |

No DMA-heap, udev socket or other device is involved.

**The patch.**
- Broker (`SandboxBrokerPolicyFactory.cpp`): while building the RDD policy in the parent,
  `AddV4l2Dependencies()` records the device numbers of the M2M `/dev/video*` nodes it admits.
  `AddV4l2RequestMediaDevices()` then opens each `/dev/media*`, reads its topology
  (`MEDIA_IOC_G_TOPOLOGY`), and admits the media device read-write only if one of its
  `MEDIA_INTF_T_V4L_VIDEO` interfaces is one of those M2M nodes. It also admits that node's
  `uevent` file (symlink path and canonical path), read-only. Media devices without an admitted
  M2M node, i.e. cameras, UVC devices, capture cards and ISPs, stay invisible.
- Seccomp (`SandboxFilter.cpp`, RDD policy): allows exactly `MEDIA_IOC_DEVICE_INFO`,
  `MEDIA_IOC_G_TOPOLOGY`, `MEDIA_IOC_REQUEST_ALLOC`, `MEDIA_REQUEST_IOC_QUEUE` and
  `MEDIA_REQUEST_IOC_REINIT`. It does not allow the whole `'|'` type.
- Everything is under `MOZ_ENABLE_V4L2`, which `toolkit/moz.configure` sets for GTK on
  arm/aarch64/riscv64 only.

**Security reasoning.**
- seccomp-bpf sees only the fd number and the ioctl command, not the file behind the fd, so it
  can't limit the media ioctls to media fds by itself. The broker does that part: the only media
  fds RDD can get are the admitted decoder media devices and the request fds allocated from them.
  Type `'|'` commands on any other fd go to drivers that don't implement them (`-ENOTTY`).
- Compared with attachment 9657436, which allows all of type `'|'`, this leaves out
  `MEDIA_IOC_SETUP_LINK` (it changes link state, the only mutating media-controller ioctl) and
  the legacy `ENUM_ENTITIES`/`ENUM_LINKS`, which no VA or FFmpeg path uses.
- The commands that are allowed are read-only queries, plus request allocation and queueing on
  a device the process can already drive through the admitted `/dev/videoN`. The request API
  only batches the controls and buffers that the already-allowed `VIDIOC_*` ioctls can set
  directly, so it adds no new kernel capability over what RDD has today.
- The policy is built in the parent at RDD launch. Devices hot-plugged later aren't admitted,
  which matches how `/dev/video*` is handled today.

**Testing.**
1. Orange Pi 5 (RK3588S), Ubuntu 26.10, kernel 7.3, Mesa panthor, Mozilla's Firefox .deb,
   VA driver `v4l2-request-va-driver`.
2. Without the patch: `about:support` → Media → "Hardware Video Decoding: available"; play
   H.264/HEVC/VP9 4K; `MOZ_LOG=PlatformDecoderModule:5` shows the VA-API init failing in RDD
   (no decoder found), and the decoder IRQ counts in `/proc/interrupts` don't move. Running with
   `MOZ_SANDBOX_LOGGING=1` logs the denied `/dev/media0` open and the `'|'` ioctl.
3. With the patch: "VA-API FFmpeg init successful", the rkvdec IRQs rise, and RDD CPU drops to
   well under one core. `MOZ_SANDBOX_LOGGING=1` shows no denials. A UVC webcam's `/dev/mediaN` is
   still refused (open fails with EACCES in RDD).
4. `./mach gtest 'SandboxBroker*'` and `./mach test security/sandbox` still pass. The new code is
   a no-op on hosts without V4L2 M2M devices.

Test status: the broker helper was compile-checked in isolation on the host. The full Firefox
build and the board run in step 3 are still to be done (test results to be attached to the bug).
