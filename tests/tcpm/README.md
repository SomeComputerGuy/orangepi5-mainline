# tcpm: USB-C dock attach/detach cycles: DP alt-mode discovery outcome, VDM timeouts and USB re-enumeration per cycle

- Runs on: **board** (copy this directory to the board, e.g. with `scp -r`)
- How it was run: `sudo bash discovery-cycle.sh 100 <outdir>`
- Notes and detailed results: [`topics/tcpm/`](../../topics/tcpm/README.md)
- Reference numbers: [`docs/RESULTS.md`](../../docs/RESULTS.md); how to re-run everything: [`docs/TESTING.md`](../../docs/TESTING.md); clips: [`docs/TEST-MEDIA.md`](../../docs/TEST-MEDIA.md)

These are the scripts exactly as they were run on the test board, except that the lab's own values are now defaults you can override: `OPI5_PI` (board login, default `ubuntu@orangepi5`), `OPI5_PI_IP` / `OPI5_HOST_IP` (board and host addresses, default the `scripts/nat-on.sh` subnet 172.31.55.0/24) and `$HOME` for the board user's home directory. Paths such as `~/demo` or `~/codecsweep` are on the board. Test media is not included (see TEST-MEDIA.md). C files are built on the board with `gcc -O2 -o <name> <name>.c` (plus `-ldrm` for DRM tools: see the file's header).

## Files

### [`discovery-cycle.sh`](discovery-cycle.sh)

```
Re-run USB PD attach + VDM discovery N times on the Orange Pi 5 USB-C port by
forcing a port reset through port_type (dual -> sink -> dual) and count how
often DP Alt Mode is discovered and configured.
Usage: sudo discovery-cycle.sh N OUTDIR [late_svids_ms]
late_svids_ms: TEST builds only, sets tcpm test_late_svids_ms (the first
Discover SVIDs after each attach times out after that many ms).
Disruptive: every cycle detaches the dock (USB3 hub, NIC, card reader, DP).
```

### [`install-tcpm.sh`](install-tcpm.sh)

```
Install a tcpm.ko variant as a drop-in and put it in the initramfs.
Usage: sudo install-tcpm.sh /var/tmp/tcpm-test/<stock-test|fixed-test|fixed>/tcpm.ko
sudo install-tcpm.sh --remove     (back to the in-tree tcpm.ko)
Takes effect at the next boot (tcpm can't be reloaded: fusb302 owns the DP HPD bridge).
```
