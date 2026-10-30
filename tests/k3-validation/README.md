# k3-validation: The host-driven unattended install + validation run used for kernel build 3 (reference; adapt the paths)

- Runs on: **host**
- How it was run: `nohup tests/k3-validation/run-k3.sh > run.log 2>&1 &`
- Reference numbers: [`docs/RESULTS.md`](../../docs/RESULTS.md); how to re-run everything: [`docs/TESTING.md`](../../docs/TESTING.md); clips: [`docs/TEST-MEDIA.md`](../../docs/TEST-MEDIA.md)

These are the scripts exactly as they were run on the test board, except that the lab's own values are now defaults you can override: `OPI5_PI` (board login, default `ubuntu@orangepi5`), `OPI5_PI_IP` / `OPI5_HOST_IP` (board and host addresses, default the `scripts/nat-on.sh` subnet 172.31.55.0/24) and `$HOME` for the board user's home directory. Paths such as `~/demo` or `~/codecsweep` are on the board. Test media is not included (see TEST-MEDIA.md). C files are built on the board with `gcc -O2 -o <name> <name>.c` (plus `-ldrm` for DRM tools: see the file's header).

## Files

### [`run-k3.sh`](run-k3.sh)

```
Unattended: install kernel build 3 (7.3.0-3, patches/linux 292-patch stack) on the Orange Pi 5,
reboot, then validate every video block and write REPORT.md. Runs on the HOST; needs no human.
nohup ~/orangepi5/work/_out/k3-validation/run-k3.sh > ~/orangepi5/work/_out/k3-validation/run.log 2>&1 &
```
