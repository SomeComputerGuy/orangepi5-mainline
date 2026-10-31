# hdmi-10bpc: HDMI 10 bpc over FRL and TMDS: camera-checked modeset cases with SCDC and dynamic debug, and the 1203 A/B (with/without the PHY bpc patch)

- Runs on: **board** (copy this directory to the board, e.g. with `scp -r`)
- How it was run: `sudo bash hdmi-batch.sh`
- Reference numbers: [`docs/RESULTS.md`](../../docs/RESULTS.md); how to re-run everything: [`docs/TESTING.md`](../../docs/TESTING.md); clips: [`docs/TEST-MEDIA.md`](../../docs/TEST-MEDIA.md)

These are the scripts exactly as they were run on the test board, except that the lab's own values are now defaults you can override: `OPI5_PI` (board login, default `ubuntu@orangepi5`), `OPI5_PI_IP` / `OPI5_HOST_IP` (board and host addresses, default the `scripts/nat-on.sh` subnet 172.31.55.0/24) and `$HOME` for the board user's home directory. Paths such as `~/demo` or `~/codecsweep` are on the board. Test media is not included (see TEST-MEDIA.md). C files are built on the board with `gcc -O2 -o <name> <name>.c` (plus `-ldrm` for DRM tools: see the file's header).

## Files

### [`tools/hdmi-batch.sh`](tools/hdmi-batch.sh)

```
HDMI 10 bpc FRL diagnosis batch: run as root on the board; camera aimed at the TV.
```

### [`tools/caseA.sh`](tools/caseA.sh)


### [`tools/ab.sh`](tools/ab.sh)

```
1203 A/B: $1 = off|on. off: move the rockchipdrm drop-in aside; on: put it back. Rebuild initramfs, reboot.
```

### [`RESULTS.md`](RESULTS.md)

```
HDMI-A-1 black at 3840x2160@60 10 bpc RGB (FRL): root cause and fix
```
