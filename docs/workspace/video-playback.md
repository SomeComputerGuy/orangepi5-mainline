# Video playback on the Orange Pi 5 Ubuntu images

The Orange Pi 5 images are ordinary Ubuntu 26.10 (Desktop or Server) plus the board
enablement: our kernel, rebuilt FFmpeg, mpv, GStreamer and alsa-ucm-conf packages (`+opi5`
versions), and a VA-API driver for the RK3588 video decoders (`v4l2-request-va-driver`).
Install apps the way their vendors document. Nothing board-specific is needed.

The RK3588 decoders handle H.264 and HEVC up to 4K (8-bit), VP9 up to 4K, AV1 up to 4K,
and VP8 and MPEG-2 up to 1080p.

## What works

### Jellyfin Media Player / Jellyfin Desktop
Jellyfin doesn't publish a desktop-client `.deb` for arm64. Its `.deb`s are amd64 only, and
on Linux it otherwise offers only the Flatpak (see below). You can build the `.deb` from
Jellyfin's released source with Jellyfin's own packaging:
```sh
sudo apt install devscripts equivs
tar xzf jellyfin-media-player-1.13.0.tar.gz && cd jellyfin    # source of the v1.13.0 release on GitHub
# Jellyfin's debian/control lists two people in Maintainer, which Ubuntu 26.10's dpkg rejects;
# move the second one to an Uploaders line (the same fix, written for Jellyfin, is patches/jellyfin-desktop/0001 in the build repo)
sed -i 's/^Maintainer: *\(.*>\), \(.*\)$/Maintainer: \1\nUploaders: \2/' debian/control
sudo mk-build-deps -i -r debian/control
dpkg-buildpackage -b -us -uc
sudo apt install ../jellyfin-media-player_*_arm64.deb
```
It uses the system libmpv, so it gets this image's hardware decoding automatically. Its
default "Hardware decoding: Copy" setting (mpv `auto-copy`) and "Enabled" (`auto`) both use
the decoders. You don't need a config file.

### Showtime and other GStreamer players (preinstalled)
These use the hardware decoders through GStreamer's v4l2codecs elements (H.264, HEVC, VP9,
AV1, VP8, MPEG-2). Nothing to set up.

### mpv and other FFmpeg/libmpv apps (`sudo apt install mpv`)
apt installs our mpv build from the image's local package source. `--hwdec=auto` (and
`auto-safe`/`yes`) now include the V4L2 decoders. Ubuntu's `/etc/mpv/mpv.conf` is left
unchanged.

### Firefox (preinstalled, Mozilla's .deb)
The image has Firefox from Mozilla's own repository instead of Ubuntu's Snap, because the Snap
can't use the system's video driver. Firefox updates through apt as Mozilla documents.
Mozilla's Firefox uses the system's FFmpeg for H.264 and HEVC, so install Ubuntu's
additional media formats once: `sudo apt install ubuntu-restricted-addons`.

**Hardware decoding in Firefox isn't available yet.** Firefox's media sandbox blocks the
device access the decoders need. A fix has been written for Mozilla (bug 2080696), but
Firefox doesn't have a setting that grants that access safely. Until a Firefox release
includes the fix, Firefox decodes video in software, which is fine up to 1080p but drops
frames on 4K. Please don't disable Firefox's sandbox to get around this.

### Google Chrome (install it as Google documents)
Download the arm64 `.deb` from google.com/chrome and run
`sudo apt install ./google-chrome-stable_current_arm64.deb`.

**Hardware decoding in Chrome isn't available yet.** Chrome only looks for a video device on
PCI graphics cards, and the board's GPU is not a PCI device. A fix has been written for
Chromium. Until a Chrome release includes it, Chrome decodes in software. If you want, you can
start Chrome yourself with `--render-node-override=/dev/dri/renderD128`. That's an unsupported
command-line switch, and the image doesn't set it.

### Jellyfin in a browser
The Jellyfin web UI works in both browsers. Until the browser fixes above ship, playback is
software-decoded, so 4K is better played in Jellyfin Desktop. Jellyfin may also transcode on
the server if the browser doesn't report support for a codec (HEVC in Chrome needs hardware
decoding).

## What doesn't work: Flatpak and Snap apps

Flatpak and Snap apps (for example the Jellyfin Desktop Flatpak, the Firefox Snap or
Chromium Snap) ship their own FFmpeg and libva runtime. That runtime doesn't contain the
V4L2 request decoders or this VA-API driver, so these apps decode in software. Use the
`.deb` versions instead. There is no supported workaround.

## Upstream status (what has to land before the limits go away)

| Component | What it fixes | Patch | Status |
|---|---|---|---|
| Firefox | lets the media (RDD) sandbox open the V4L2 decoders' media devices and use their request ioctls, so Firefox can hardware-decode | `patches/firefox/0001` (Mozilla bug 2080696) | written, compile-checked only, not sent. Until it ships, Firefox decodes in software |
| Chromium / Chrome | uses a non-PCI (platform) GPU render node for VA-API, so Chrome can hardware-decode | `patches/chromium/0001` | written, not compiled, not sent. Until it ships, Chrome decodes in software |
| mpv | lets `--hwdec=auto` / `auto-copy` use the V4L2 decoders (Jellyfin Media Player asks for these) | `patches/mpv/0003` | in our mpv build (+opi5.2); not sent upstream |
| mpv, FFmpeg | V4L2 request API hardware decoding itself | `patches/mpv/0001-0002` (mpv PR #14690), `patches/ffmpeg/0001-0012` (FFmpeg PR #20847 and our HEVC fix) | in our builds; upstream PRs still open |
| alsa-ucm-conf | sound profiles for the headphone jack/mic, HDMI and DisplayPort | `patches/alsa-ucm-conf/0001` | in our build (+opi5.1); needs a Signed-off-by before sending |
| Jellyfin Media Player | its Debian packaging doesn't build with Ubuntu 26.10's dpkg | `patches/jellyfin-desktop/0001` | written, not sent; Jellyfin also publishes no arm64 .deb |
| VA-API driver (libva-v4l2-request) | browsers' and VA clients' access to the decoders | fork of megi's driver | packaged by us; 10-bit output still to do |

Until these are merged, the image carries them as `+opi5` rebuilds of Ubuntu's packages.

## Limits
- 10-bit HEVC (Main10) and VP9 Profile 2: hardware-decoded in mpv/libmpv apps and GStreamer.
  The VA-API driver doesn't offer them yet (the decoder writes a packed 10-bit format that
  browsers can't take), so in browsers they play in software.
- 8K and VP8/MPEG-2 above 1080p: software (hardware limit).

## Server image
The Server image is Ubuntu Server plus the same kernel and the same package source. Nothing
media-related is preinstalled. `sudo apt install ffmpeg` (or GStreamer) gives our builds,
with `ffmpeg -hwaccel v4l2request` and the v4l2codecs elements.
