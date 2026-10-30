# demo: Live decode / encode-and-play demo of every video block

- Runs on: **board** (copy this directory to the board, e.g. with `scp -r`)
- How it was run: `bash ~/demo/demo.sh list`
- Reference numbers: [`docs/RESULTS.md`](../../docs/RESULTS.md); how to re-run everything: [`docs/TESTING.md`](../../docs/TESTING.md); clips: [`docs/TEST-MEDIA.md`](../../docs/TEST-MEDIA.md)

These are the scripts exactly as they were run on the test board, except that the lab's own values are now defaults you can override: `OPI5_PI` (board login, default `ubuntu@orangepi5`), `OPI5_PI_IP` / `OPI5_HOST_IP` (board and host addresses, default the `scripts/nat-on.sh` subnet 172.31.55.0/24) and `$HOME` for the board user's home directory. Paths such as `~/demo` or `~/codecsweep` are on the board. Test media is not included (see TEST-MEDIA.md). C files are built on the board with `gcc -O2 -o <name> <name>.c` (plus `-ldrm` for DRM tools: see the file's header).

## Files

### [`demo.sh`](demo.sh)

```
Live decode / encode->playback demo on the Orange Pi 5 (runs on the board).
demo.sh <step>      steps: list | dec-hevc | dec-vp9 | dec-h264 | dec-av1 | g1-h264 | g1-vp8 |
g1-mpeg2 | enc-hevc | enc-h264 | enc-vepu2 | jpeg | dual
Clips live in ~/demo (reference encodes of UVG "YachtRide" 3840x2160@120, CC BY-NC 3.0,
Ultra Video Group, Tampere University).
```
