# queue: Unattended board test queue (CCU verify + fluster, codec-quality fluster, VA driver tests)

- Runs on: **board** (copy this directory to the board, e.g. with `scp -r`)
- How it was run: `nohup bash ~/queue/queue.sh > ~/queue/run.log 2>&1 &`
- Reference numbers: [`docs/RESULTS.md`](../../docs/RESULTS.md); how to re-run everything: [`docs/TESTING.md`](../../docs/TESTING.md); clips: [`docs/TEST-MEDIA.md`](../../docs/TEST-MEDIA.md)

These are the scripts exactly as they were run on the test board, except that the lab's own values are now defaults you can override: `OPI5_PI` (board login, default `ubuntu@orangepi5`), `OPI5_PI_IP` / `OPI5_HOST_IP` (board and host addresses, default the `scripts/nat-on.sh` subnet 172.31.55.0/24) and `$HOME` for the board user's home directory. Paths such as `~/demo` or `~/codecsweep` are on the board. Test media is not included (see TEST-MEDIA.md). C files are built on the board with `gcc -O2 -o <name> <name>.c` (plus `-ldrm` for DRM tools: see the file's header).

## Files

### [`queue.sh`](queue.sh)

```
Unattended board test queue (runs ON the board). Summary: ~/queue/summary.txt
```
