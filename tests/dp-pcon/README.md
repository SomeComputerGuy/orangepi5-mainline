# dp-pcon: USB-C DP through a DP->HDMI dock: sink CRC through the PCON, PCON control (DPCD 0x3050-0x3052), reduced-blanking EDID override, camera-checked mode batches (results for patches 1204-1206)

- Runs on: **board** (copy this directory to the board, e.g. with `scp -r`)
- How it was run: `sudo bash zerlon-batch.sh`
- Reference numbers: [`docs/RESULTS.md`](../../docs/RESULTS.md); how to re-run everything: [`docs/TESTING.md`](../../docs/TESTING.md); clips: [`docs/TEST-MEDIA.md`](../../docs/TEST-MEDIA.md)

These are the scripts exactly as they were run on the test board, except that the lab's own values are now defaults you can override: `OPI5_PI` (board login, default `ubuntu@orangepi5`), `OPI5_PI_IP` / `OPI5_HOST_IP` (board and host addresses, default the `scripts/nat-on.sh` subnet 172.31.55.0/24) and `$HOME` for the board user's home directory. Paths such as `~/demo` or `~/codecsweep` are on the board. Test media is not included (see TEST-MEDIA.md). C files are built on the board with `gcc -O2 -o <name> <name>.c` (plus `-ldrm` for DRM tools: see the file's header).

## Files

### [`crc.sh`](crc.sh)

```
Read DP sink CRCs (DPCD 0x240-0x245) N times while TEST_SINK_START is set.
```

### [`modeset.sh`](modeset.sh)

```
usage: modeset.sh <mode> <secs> [crc]: show modetest pattern on DP-1 and sample sink CRC
```

### [`edid-add-rb.py`](edid-add-rb.py)

```
Replace the first (preferred) DTD of an EDID base block with
3840x2160@30 CVT-RB (262.75 MHz, h 3840/3888/3920/4000 v 2160/2163/2168/2191 +h -v).
```

### [`zerlon-batch.sh`](zerlon-batch.sh)

```
Zerlon on the dock, camera aimed at it. Copy crc.sh and zerlon-rb4k30.edid to /tmp on the board,
then run: echo <pw> | sudo -S bash /tmp/zerlon-batch.sh   (about 75 s with gdm stopped)
```

### [`zerlon-scramble.sh`](zerlon-scramble.sh)


### [`RESULTS.md`](RESULTS.md)

```
DP-1 4K30 (297 MHz) through the USB-C dock / DP->HDMI PCON: results
```
