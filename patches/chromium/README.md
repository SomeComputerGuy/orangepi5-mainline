# Chromium: VA-API on platform (non-PCI) GPUs

`0001-media-vaapi-Use-platform-DRM-render-nodes-when-there.patch`. It's against Chromium main
(`media/gpu/vaapi/vaapi_wrapper.cc`, fetched 2026-10-30) and it hasn't been sent. It hasn't been
compiled either, because we have no Chromium checkout. The change is 33 added lines in one function.

## Why stock Chrome has no hardware decode on the Orange Pi 5
- `VADisplayStateSingleton::PreSandboxInitialization()` opens the DRM device that libva gets.
  It walks `drmGetDevices2()` and skips every device whose `bustype != DRM_BUS_PCI`. It then
  matches the remaining devices against `gpu_info->active_gpu()` PCI vendor/device IDs.
- On RK3588 the only render node, `renderD128`, belongs to panthor, a **platform** device. The
  board shows `card0 platform panthor`, `card1 platform rockchip-drm` (KMS only, no render node)
  and `renderD128 platform panthor`. The NPU is `/dev/accel/accel0`, not a DRM render node.
- So no VA display is opened, and `VaapiVideoDecoder` is never offered. The only way in is
  `--render-node-override` (or `--hardware-video-device-path`).
- This is not a render-node ordering problem, and it can't be fixed in the kernel, the DT or our
  VA driver: there is no PCI bus to put the GPU on, and the check happens before libva is loaded.
- ANGLE's `GetSystemInfo()` on Linux uses libpci and then falls back to Vulkan. So
  `active_gpu()` holds no PCI IDs that a platform device could match anyway.

## The fix
- If the system has **no PCI GPU with a render node**, use the first `DRM_BUS_PLATFORM` or
  `DRM_BUS_HOST1X` device that has one.
- PCI systems behave exactly as before.
- `LoadDrmFD()` still rejects vgem. Display-only KMS drivers, vkms included, have no render node.

## Other defaults checked (Chromium main, 2026-10-30): none of them block decoding
- `media/base/media_switches.cc:1507`: `kAcceleratedVideoDecodeLinux` ("AcceleratedVideoDecoder")
  is enabled by default when `USE_VAAPI` is set.
- `media/base/media_switches.cc:1515`: `kAcceleratedVideoDecodeLinuxGL` is enabled by default.
  So `--enable-features=AcceleratedVideoDecodeLinuxGL` isn't needed.
- `media/mojo/services/gpu_mojo_media_client_linux.cc:104-112`: VA-API is allowed on the GL
  (`GrContextType::kGL`) path. NV12 zero-copy needs `supports_nv12_gl_native_pixmap` (EGL
  dma-buf import).
- `media/gpu/chromeos/platform_video_frame_utils.cc:210-216`: the GBM device used for frame
  allocation probes `/dev/dri/renderD128` upwards and isn't limited to PCI.
- `gpu/config/software_rendering_list.json`: the only Linux `accelerated_video_decode` entry is
  id 56 (old NVIDIA). No Mali/panthor/Mesa entry applies.
- `vaapi_wrapper.cc:395`: our driver's vendor string maps to `VAImplementation::kOther`. That
  only means the global VA lock is used (`UseGlobalVaapiLock`), and our driver is fine with it.
- GPU sandbox: VA is initialised before the sandbox, and the DRM fd stays open in the singleton.
  The desktop broker (`content/common/gpu_pre_sandbox_hook_linux.cc:454`,
  `AddStandardGpuPermissions`) allows `/dev/dri/card0-9`. All ioctls are allowed. Our driver's
  V4L2 fd pool covers what it opens later (`work/_out/browser-hwdec/RESULTS.md` §3.4).
- `--ozone-platform=wayland` and `--use-gl=angle --use-angle=gles` were added in the earlier
  experiments. They are not needed for VA-API by the code above, but the board test must confirm
  that Chrome 156's defaults (ozone `auto`, ANGLE's default GL backend) give
  `supports_nv12_gl_native_pixmap`.

## A system-level setting in stock Chrome?
**No.** I checked google-chrome-stable 156.0.8078.79 arm64 from dl.google.com:
- `/opt/google/chrome/google-chrome` only sets `CHROME_WRAPPER`, `CHROME_VERSION_EXTRA` and
  `GNOME_DISABLE_CRASH_DIALOG`, then runs `exec -a "$0" chrome "$@"`. It reads no flags file and
  no flags variable.
- No enterprise policy (`/etc/opt/chrome/policies/managed/*.json`) sets command-line switches or
  the VA device. `HardwareAccelerationModeEnabled` is already true by default.
- `chrome://flags` has no render-node entry.

Until this patch is in a Chrome release, a user has two options:
- accept software decoding;
- start Chrome with `--render-node-override=/dev/dri/renderD128` themselves.

The image ships neither a wrapper nor a desktop-file override.

## Test plan (board, once a build with the patch exists, e.g. Chromium from source)
1. Start Chrome with no switches. Check `chrome://gpu` → "Video Acceleration Information": H.264,
   HEVC, VP9 and AV1 decode up to 3840x2160.
2. Play 4K H.264, HEVC, VP9 and AV1. In `chrome://media-internals`, check `kVideoDecoderName:
   VaapiVideoDecoder` and `kIsPlatformVideoDecode: true`. The rkvdec/VPU981 IRQs in
   `/proc/interrupts` must rise.
3. Regression check on an x86 PCI machine (Intel or AMD): the same device is chosen as before. A
   machine with a PCI dGPU and a platform node must still pick the PCI one.
