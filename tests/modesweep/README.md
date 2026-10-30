# modesweep: Display mode sweep: every mode on every connector, with and without a full-screen NV12 overlay, every plane format; counts VOP2 underflows

- Runs on: **board** (copy this directory to the board, e.g. with `scp -r`)
- How it was run: `nohup sudo bash ~/modesweep/modesweep.sh > ~/modesweep/run.log 2>&1 &`
- Notes and detailed results: [`topics/vop2-underflow-int/`](../../topics/vop2-underflow-int/README.md)
- Reference numbers: [`docs/RESULTS.md`](../../docs/RESULTS.md); how to re-run everything: [`docs/TESTING.md`](../../docs/TESTING.md); clips: [`docs/TEST-MEDIA.md`](../../docs/TEST-MEDIA.md)

These are the scripts exactly as they were run on the test board, except that the lab's own values are now defaults you can override: `OPI5_PI` (board login, default `ubuntu@orangepi5`), `OPI5_PI_IP` / `OPI5_HOST_IP` (board and host addresses, default the `scripts/nat-on.sh` subnet 172.31.55.0/24) and `$HOME` for the board user's home directory. Paths such as `~/demo` or `~/codecsweep` are on the board. Test media is not included (see TEST-MEDIA.md). C files are built on the board with `gcc -O2 -o <name> <name>.c` (plus `-ldrm` for DRM tools: see the file's header).

## Files

### [`modesweep.sh`](modesweep.sh)

```
Runs ON the board, unattended: every mode on every connected connector (pattern only, then with a
full-screen NV12 overlay plane), then every format on every plane at each connector's preferred
mode. Counts POST_BUF_EMPTY (VOP underflow) and failures per test. Report: ~/modesweep/report.txt
nohup sudo bash ~/modesweep/modesweep.sh > ~/modesweep/run.log 2>&1 &
```

### [`dpslow.sh`](dpslow.sh)

```
Runs ON the board, unattended: the DP-only, slow variant of modesweep.sh. Every mode on the
DP connector (pattern only, then with a full-screen NV12 overlay plane), 12 s per mode instead
of 4 s. Counts POST_BUF_EMPTY (VOP underflow) and failures per test.
Report: ~/modesweep/report-dp-slow.txt
nohup sudo bash ~/modesweep/dpslow.sh > ~/modesweep/run-dp-slow.log 2>&1 &
```
