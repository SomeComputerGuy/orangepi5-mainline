# Test media

The test clips are **not** part of this repository: some licences don't allow redistribution, and
the files are large. This page lists every clip the scripts under [`tests/`](../tests/) use: where
to download it, its size and SHA-256, its licence, where the scripts expect it, and the exact
commands that made the derived encodes. With these you can rebuild the same files byte for byte (the
downloads) or reproduce them with the same encoder settings (the encodes).

The sizes and hashes below were computed with `stat -c %s` and `sha256sum` from the files that
the tests ran on (2026-10-29/30).

Reference results that used these clips are in [`RESULTS.md`](RESULTS.md); how to run the tests is
in [`TESTING.md`](TESTING.md).

## Where the files go

| Location | Contents | Used by |
|---|---|---|
| Board `~/demo/` | UVG YachtRide reference encodes and raw NV12 frames, Big Buck Bunny, plus the encoder test clients `rkvenc-enc` and `v4l2-h264-slenc` and `demo.sh` | `tests/demo`, `tests/codec-sweep`, `tests/rkvdec-ccu`, `tests/vop2-underflow`, `tests/maxout`, `tests/k3-validation` |
| Board `~/codecsweep/work/` | Reference encodes generated **on the board** by `codecsweep.sh` from `~/demo/yacht_2160p.nv12` | `tests/codec-sweep`, `tests/dp-smooth`, `tests/vop2-underflow` |
| Board `~/vp9perf/` | Synthetic `testsrc2`/`mandelbrot` clips generated on the board | `tests/va-driver` (variable `CLIPS`) |
| Board `~/.local/share/fluster/resources/` | Conformance vectors (`fluster download`) | `tests/codec-sweep`, `tests/rkvdec-ccu`, `tests/va-driver` |
| Host, one directory served over HTTP | Jellyfish clips, Big Buck Bunny, Tears of Steel HEVC | `tests/netstress`, `tests/maxout` (through `tests/netstress/rangeserver.py`) |

`~` is the home directory of the board user. The host address that the board fetches from is
configurable: the scripts read `OPI5_HOST_IP` (the default is the host address on the
`scripts/nat-on.sh` subnet, see `scripts/env.sh`) and use port 8099.

The `tests/k3-validation/run-k3.sh` run copied the whole host directory of YachtRide encodes
(the `enc/` directory below) to `~/demo/` on the board with `rsync`, so `~/demo` holds exactly the
files of that directory.

## 1. UVG YachtRide (Ultra Video Group, Tampere University)

Licence: **CC BY-NC 3.0** (Creative Commons Attribution-NonCommercial 3.0 Unported). The
archive's `YachtRide_Copyright.txt` says: "This sequence and all intellectual property rights
therein remain the property of Digiturk. You may use this sequence according to Creative Commons
Attribution-NonCommercial 3.0 Unported (http://creativecommons.org/licenses/by-nc/3.0/deed.en_US)."

Cite: A. Mercat, M. Viitanen, J. Vanne, "UVG dataset: 50/120fps 4K sequences for video codec
analysis and development", ACM MMSys 2020. Dataset page: <https://ultravideo.fi/dataset.html>.

### Download

| File | URL | Size (bytes) | SHA-256 |
|---|---|---|---|
| `YachtRide.7z` | <https://ultravideo.fi/video/YachtRide_3840x2160_120fps_420_8bit_YUV_RAW.7z> | 2873242117 | `f1883db1a72387c58248ef95ae535b7345eb53bf738259780cc516576913115d` |
| `YachtRide_3840x2160.yuv` (in the archive) | - | 7464960000 | `16172bd433cc0e600beb22d70e48519ac8f647fb388067232d199974100f35ca` |
| `YachtRide_Copyright.txt` (in the archive) | - | 249 | `bdbb8a6d1f307df4206ddfbdd19bbfa05ac83c03af89d871ea719b15e6b62938` |

The raw file is 600 frames of 3840x2160 8-bit 4:2:0 (I420) at 120 fps. It was downloaded with

```sh
curl -s -C - --retry 20 --retry-all-errors -o YachtRide.7z \
  https://ultravideo.fi/video/YachtRide_3840x2160_120fps_420_8bit_YUV_RAW.7z
```

and unpacked with py7zr (`7z x YachtRide.7z` gives the same files).

The UVG `Jockey` sequence (`https://ultravideo.fi/video/Jockey_3840x2160_120fps_420_8bit_YUV_RAW.7z`,
3453463918 bytes, SHA-256 `46a8d03f9cfe846d632fbbe503ce3be1d8697be2d332ec206d934153aa92720b`) was
downloaded at the same time, but no published script uses it.

### Derived encodes (board `~/demo/`)

Made on the host from `YachtRide_3840x2160.yuv` with the static FFmpeg 7.0.2 x86_64 binary that the
`imageio-ffmpeg` Python package bundles (libx264, libx265, libvpx, libaom). The encoder logs are
empty because the commands ran with `-loglevel error`; the commands below are the ones that were run.
Common input options:

```sh
I="-f rawvideo -pix_fmt yuv420p -s 3840x2160 -r 120 -i YachtRide_3840x2160.yuv"
```

| File | Command | Size (bytes) | SHA-256 |
|---|---|---|---|
| `yacht_hevc_2160p120.mp4` | `ffmpeg -hide_banner -loglevel error -y $I -c:v libx265 -preset fast -crf 20 -x265-params keyint=120:log-level=error -tag:v hvc1 yacht_hevc_2160p120.mp4` | 48382673 | `8be37d45a8e6d2928244b983ba29a8c15ac36751a2b40729e41efceacd6c2528` |
| `yacht_h264_2160p120.mp4` | `ffmpeg -hide_banner -loglevel error -y $I -c:v libx264 -preset fast -crf 18 -profile:v high -level 5.2 -g 120 yacht_h264_2160p120.mp4` | 83895886 | `e39d0af1e3060c261d550d0c90d035dcfaeb54e22424eba20d00a6ee66d18c32` |
| `yacht_vp9_2160p120.webm` | `ffmpeg -hide_banner -loglevel error -y $I -c:v libvpx-vp9 -deadline realtime -cpu-used 8 -row-mt 1 -threads 16 -tile-columns 2 -b:v 40M -g 120 yacht_vp9_2160p120.webm` | 26053930 | `60b6f12feea2cd6c74cc91b6dde68e181d83a2518eb9744f39a95cb802aaf16d` |
| `yacht_av1_1080p120.mkv` | `ffmpeg -hide_banner -loglevel error -y $I -vf scale=1920:1080 -c:v libaom-av1 -usage realtime -cpu-used 8 -row-mt 1 -threads 8 -b:v 12M -g 120 yacht_av1_1080p120.mkv` | 7142154 | `27898aa021b88e4882c87f306577243a76f75363ddc8d5ebc425a578ffa0cd41` |
| `yacht_h264_1080p120.mp4` | `ffmpeg -hide_banner -loglevel error -y $I -vf scale=1920:1080 -c:v libx264 -preset fast -crf 18 -profile:v main -g 120 yacht_h264_1080p120.mp4` | 25664203 | `cfb886523b3acadc248a32b5d3ed2775dded9b8200da844eb222ddf564b3cac4` |
| `yacht_vp8_1080p120.webm` | `ffmpeg -hide_banner -loglevel error -y $I -vf scale=1920:1080 -c:v libvpx -deadline realtime -cpu-used 8 -threads 8 -b:v 15M -g 120 yacht_vp8_1080p120.webm` | 8738317 | `a2e9fca7b54d84f8f6b6833e9238bfd2cb58eb5388e6605468e90d5089dcbf62` |
| `yacht_mpeg2_1080p120.mpg` | `ffmpeg -hide_banner -loglevel error -y $I -vf scale=1920:1080 -c:v mpeg2video -q:v 3 -g 15 -bf 2 yacht_mpeg2_1080p120.mpg` | 82747392 | `1ffc9ee9b7a1726331cb378d564da0a481822a0d03c7cae9db1d29eb49e58cd9` |
| `yacht_2160p.nv12` (raw, 600 frames) | `ffmpeg -hide_banner -loglevel error -y $I -f rawvideo -pix_fmt nv12 yacht_2160p.nv12` | 7464960000 | `9d559c0f8042a4f604e959375e6aa61ee04508e7c7567e2d213fefcc88fb3b86` |
| `yacht_1080p.nv12` (raw, 600 frames) | `ffmpeg -hide_banner -loglevel error -y $I -vf scale=1920:1080 -f rawvideo -pix_fmt nv12 yacht_1080p.nv12` | 1866240000 | `5aa3293959c4ef6518df395dbaa3a6bde38fa68973863bf112e74d27d380de5e` |

Notes:
- The AV1 encode was first started with `-cpu-used 9` and restarted a minute later with
  `-cpu-used 8`, which replaced the file. The table gives the command that produced the file.
- The FFmpeg MPEG-2 muxer logs "buffer underflow" and "packet too large" warnings for
  `yacht_mpeg2_1080p120.mpg` (the only non-empty encoder log). MPEG-2 has no 120 fps frame-rate
  code, so treat the frame rate in that file's header with care; the tests compare frames by index.
- A rebuilt encode will only match the hashes above with the same FFmpeg and library versions. The
  raw `.nv12` files depend only on FFmpeg's scaler and format conversion.

### Board-generated reference clips (`~/codecsweep/work/`)

`tests/codec-sweep/codecsweep.sh` makes these itself on the first run, with the board's FFmpeg, so
they are not listed with hashes. First 240 frames of `~/demo/yacht_2160p.nv12`, scaled to
640x360, 1280x720, 1920x1080, 2560x1440 and 3840x2160 (`src_<WxH>.nv12`), then encoded per codec,
resolution and frame rate (30, 60, 120; MPEG-2 only 30 and 60) as `ref_<codec>_<WxH>_<fps>.<ext>`:

| Codec | FFmpeg encoder options |
|---|---|
| h264 | `-c:v libx264 -preset veryfast -crf 20 -g 60` |
| h265 | `-c:v libx265 -preset ultrafast -crf 22 -x265-params keyint=60:log-level=error` |
| vp9 | `-c:v libvpx-vp9 -deadline realtime -cpu-used 8 -row-mt 1 -b:v 20M -g 60` |
| av1 | `-c:v libaom-av1 -usage realtime -cpu-used 8 -row-mt 1 -b:v 10M -g 60` |
| vp8 | `-c:v libvpx -deadline realtime -cpu-used 8 -b:v 10M -g 60` |
| mpeg2 | `-c:v mpeg2video -q:v 3 -g 15 -bf 2` |

`tests/dp-smooth` and `tests/vop2-underflow/vm.sh` use `ref_h265_1920x1080_30.mkv`,
`ref_h265_3840x2160_60.mkv` and `ref_h265_3840x2160_30.mkv` from this directory, so run the codec
sweep (at least its decoder part) once before those tests.

## 2. Big Buck Bunny 4K60 (Blender Foundation)

Licence: **CC BY 3.0**, (c) Blender Foundation, blender.org.

| File | URL | Size (bytes) | SHA-256 |
|---|---|---|---|
| `bbb.zip` | <https://download.blender.org/demo/movies/BBB/bbb_sunflower_2160p_60fps_normal.mp4.zip> | 671868845 | `8f1d53cf56a314be08206ae730546ef26db9fd0114b33ff2528f522bc3714d19` |
| `bbb_sunflower_2160p_60fps_normal.mp4` (in the zip; H.264) | - | 673223862 | `35db9a007021f1b0066993e1d2c4448c83a8b279f799c97d33cbba73980a8a36` |
| `bbb_2160p60_hevc.mp4` (HEVC transcode, see below) | - | 794008535 | `b789ece5a11a31093d3334a6174bbd20789f30c1723ff15d64a5a0d733470cb3` |

Downloaded with `curl -s -C - --retry 10 -o bbb.zip <URL>` and unpacked with Python's `zipfile`.
HEVC transcode (same static FFmpeg 7.0.2 as above):

```sh
ffmpeg -hide_banner -loglevel error -y -i bbb_sunflower_2160p_60fps_normal.mp4 \
  -map 0:v:0 -map 0:a:0? -c:v libx265 -preset fast -crf 20 -x265-params log-level=error \
  -tag:v hvc1 -c:a copy bbb_2160p60_hevc.mp4
```

Both MP4 files were copied to `~/demo/` on the board. `bbb_sunflower_2160p_60fps_normal.mp4` is
also served by the host for `tests/netstress` (the HTTP directory holds a link to it).

## 3. Tears of Steel 4K (Blender Foundation)

Licence: **CC BY 3.0**, (c) Blender Foundation, blender.org.

| File | URL | Size (bytes) | SHA-256 |
|---|---|---|---|
| `tos4k.zip` | <https://download.blender.org/demo/movies/ToS/tearsofsteel_4k.mov.zip> | 6737593114 | `9c0b8df301d254e83d0046c530a71438bbfc42d2b7000366edde1596616bad05` |
| `tearsofsteel_4k.mov` (in the zip) | - | 6737592810 | `89b7fd21c7729b7d5071af993939997f847b5af06613a3388ba158dae9e52ab3` |
| `tears_of_steel_2160p_hevc.mp4` (HEVC transcode, served by the host) | - | 1720018875 | `10ff717337f77cbe93575fb6a4bd47a8e9d87dfe185ff7bc55697fc3061dbfb5` |

Transcode (same static FFmpeg 7.0.2):

```sh
ffmpeg -hide_banner -loglevel error -y -i tearsofsteel_4k.mov -vf scale=3840:-2 \
  -c:v libx265 -preset fast -crf 20 -x265-params log-level=error -tag:v hvc1 \
  -c:a aac -b:a 192k tears_of_steel_2160p_hevc.mp4
```

Used by `tests/netstress` (the Tears of Steel + Big Buck Bunny pair) and as the default stream B
of `tests/maxout`. Neither of those has been run with it yet (see RESULTS.md).

## 4. Jellyfish bit-rate test clips (Jellyfin test media)

Downloaded from Jellyfin's archive of the Jellyfish test files. The licence of these clips was not
recorded in our notes: see the source page <https://repo.jellyfin.org/archive/jellyfish/> before
using or redistributing them.

| File | URL | Size (bytes) | SHA-256 |
|---|---|---|---|
| `jellyfish-120-mbps-4k-uhd-h264.mkv` | <https://repo.jellyfin.org/archive/jellyfish/media/jellyfish-120-mbps-4k-uhd-h264.mkv> | 452292468 | `6426932ea89c4c625c7384d4bab98aed1ff9a471f293d5a71571ea13916a2729` |
| `jellyfish-250-mbps-4k-uhd-h264.mkv` | <https://repo.jellyfin.org/archive/jellyfish/media/jellyfish-250-mbps-4k-uhd-h264.mkv> | 938508957 | `369976b0c3807e46590f033b23ca54bdb02e4871e97c3d3012c9e136e8a2f6e1` |
| `jellyfish-400-mbps-4k-uhd-hevc-10bit.mkv` | <https://repo.jellyfin.org/archive/jellyfish/media/jellyfish-400-mbps-4k-uhd-hevc-10bit.mkv> | 1504953150 | `85d774f4dc429911e4ec446eb5bcef5d578611c47070079f38f1dca6de038c88` |

Downloaded with `curl -s -C - --retry 10 -o <file> <URL>`. The HTTP response for the 120 Mbit/s
file reported `content-length: 452292468`, the same as the file used. (The older path
`https://repo.jellyfin.org/jellyfish/media/...` returned 404 when checked.)

These are not copied to the board: they are served by the host and streamed over HTTP.

## 5. Serving the network clips from the host

Put these files in one directory on the host:

```
bbb_sunflower_2160p_60fps_normal.mp4
jellyfish-120-mbps-4k-uhd-h264.mkv
jellyfish-250-mbps-4k-uhd-h264.mkv
jellyfish-400-mbps-4k-uhd-hevc-10bit.mkv
tears_of_steel_2160p_hevc.mp4
```

and serve them with Range support (a plain `python3 -m http.server` doesn't support Range
requests; the first netstress run failed on that with "Internal data stream error"):

```sh
python3 -I tests/netstress/rangeserver.py "$OPI5_HOST_IP" 8099 <media dir>
```

`netstress.sh` skips the Tears of Steel pair if that file isn't there, and the 400 Mbit/s case if
the server doesn't answer `200 OK` for it.

## 6. Synthetic clips for the VA driver and VP9 benchmarks (`~/vp9perf/`)

Generated on the board with the board's FFmpeg (no hashes: they depend on the FFmpeg build). From
`topics/vp9-perf/notes/scripts/gen.sh` plus two lines that were added to it on the board:

```sh
E="-deadline realtime -cpu-used 8 -row-mt 1 -threads 8 -tile-columns 2 -frame-parallel 0 -lag-in-frames 0 -error-resilient 0"
ffmpeg -f lavfi -i testsrc2=size=3840x2160:rate=60 -frames:v 600 -pix_fmt yuv420p -c:v libvpx-vp9 $E -b:v 20M 4k8.webm
ffmpeg -f lavfi -i testsrc2=size=3840x2160:rate=60 -frames:v 600 -pix_fmt yuv420p10le -c:v libvpx-vp9 -profile:v 2 $E -b:v 20M 4k10.webm
ffmpeg -f lavfi -i testsrc2=size=1920x1080:rate=60 -frames:v 1200 -pix_fmt yuv420p -c:v libvpx-vp9 $E -b:v 8M 1080p.webm
ffmpeg -f lavfi -i "mandelbrot=size=3840x2160:rate=60,noise=alls=12:allf=t" -frames:v 300 -pix_fmt yuv420p10le -c:v libvpx-vp9 -profile:v 2 $E -b:v 60M 4k10hb.webm
ffmpeg -f lavfi -i testsrc2=size=3840x2160:rate=60 -frames:v 600 -pix_fmt yuv420p -c:v libx265 -preset ultrafast -x265-params bframes=0:log-level=error -b:v 20M 4k8.hevc.mkv
ffmpeg -f lavfi -i testsrc2=size=3840x2160:rate=60 -frames:v 600 -pix_fmt yuv420p -c:v libx264 -preset ultrafast -bf 0 -b:v 20M 4k8.h264.mkv
```

(`gen.sh` runs each with `nice -n 19 ffmpeg -hide_banner -loglevel error -y` and skips files that
exist.) `tests/va-driver/run-tests.sh` additionally generates its own 10 s `testsrc2` clips in
`./clips/` (1080p H.264/HEVC/VP9, 720p VP8); the commands are in the script.

## 7. Conformance vectors (fluster)

The conformance suites come from [fluster](https://github.com/fluendo/fluster), which downloads
them from their official sources; they keep their own licences. On the board:

```sh
fluster download VP8-TEST-VECTORS VP9-TEST-VECTORS JVT-AVC_V1 JVT-FR-EXT JCT-VC-HEVC_V1 AV1-TEST-VECTORS MPEG2_VIDEO-MAIN
```

They go to `~/.local/share/fluster/resources/<suite>/`, which is where `tests/codec-sweep`
(`run-fluster.sh`, `mpeg2-conf.sh`), `tests/rkvdec-ccu/fluster.sh` and `tests/va-driver` look for
them. `codecsweep.sh` and `run-fluster.sh` call `fluster download` themselves; `mpeg2-conf.sh`
expects `MPEG2_VIDEO-MAIN` to be there already (override with `R=<dir>`).
