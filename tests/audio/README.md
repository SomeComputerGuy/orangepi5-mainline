# audio: Audible output checks: HDMI, USB-C DP and the headphone jack, and HDMI audio across FRL/TMDS mode changes

- Runs on: **board** (copy this directory to the board, e.g. with `scp -r`)
- How it was run: `bash listen-test.sh all`
- Notes and detailed results: [`topics/audio/`](../../topics/audio/README.md)
- Reference numbers: [`docs/RESULTS.md`](../../docs/RESULTS.md); how to re-run everything: [`docs/TESTING.md`](../../docs/TESTING.md); clips: [`docs/TEST-MEDIA.md`](../../docs/TEST-MEDIA.md)

These are the scripts exactly as they were run on the test board, except that the lab's own values are now defaults you can override: `OPI5_PI` (board login, default `ubuntu@orangepi5`), `OPI5_PI_IP` / `OPI5_HOST_IP` (board and host addresses, default the `scripts/nat-on.sh` subnet 172.31.55.0/24) and `$HOME` for the board user's home directory. Paths such as `~/demo` or `~/codecsweep` are on the board. Test media is not included (see TEST-MEDIA.md). C files are built on the board with `gcc -O2 -o <name> <name>.c` (plus `-ldrm` for DRM tools: see the file's header).

## Files

### [`listen-test.sh`](listen-test.sh)

```
Orange Pi 5 audible output check, run as the normal (non-root) user.
Usage: listen-test.sh [hdmi|hp|dp|all]   (default: all)
Each output plays: spoken "Front Left"/"Front Right" (speaker-test -t wav),
a 2 s 440 Hz sine via GStreamer alsasink, then 2 s 880 Hz via autoaudiosink
(autoaudiosink only for the default device, so it is played once at the end).
```

### [`modeswitch-listen.sh`](modeswitch-listen.sh)

```
Run as root with nothing holding DRM master. A 440 Hz tone plays on the TV
(HDMI, as the desktop user) for ~30 s while the mode changes:
0 s 4K60 (FRL) -> 6 s 4K120 (FRL) -> 14 s 4K60 -> 20 s 1080p60 (TMDS) -> 26 s 4K60
Ask: does the tone continue cleanly after each screen blink (4 blinks)?
```

### [`seq.sh`](seq.sh)

```
Labelled tones: HDMI (TV) 440 Hz 3 s, 3 s pause, DP (Dell) 880 Hz 3 s.
```
