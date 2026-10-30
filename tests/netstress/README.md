# netstress: Network streaming stress: two 4K HTTP streams decoded and shown on HDMI + DP, plus a 400 Mbit/s HEVC Main10 decode over HTTP

- Runs on: **both** (copy this directory to the board, e.g. with `scp -r`)
- How it was run: `host: python3 -I rangeserver.py $OPI5_HOST_IP 8099 <media dir>; board: bash ~/netstress/netstress.sh http://$OPI5_HOST_IP:8099 30`
- Reference numbers: [`docs/RESULTS.md`](../../docs/RESULTS.md); how to re-run everything: [`docs/TESTING.md`](../../docs/TESTING.md); clips: [`docs/TEST-MEDIA.md`](../../docs/TEST-MEDIA.md)

These are the scripts exactly as they were run on the test board, except that the lab's own values are now defaults you can override: `OPI5_PI` (board login, default `ubuntu@orangepi5`), `OPI5_PI_IP` / `OPI5_HOST_IP` (board and host addresses, default the `scripts/nat-on.sh` subnet 172.31.55.0/24) and `$HOME` for the board user's home directory. Paths such as `~/demo` or `~/codecsweep` are on the board. Test media is not included (see TEST-MEDIA.md). C files are built on the board with `gcc -O2 -o <name> <name>.c` (plus `-ldrm` for DRM tools: see the file's header).

## Files

### [`netstress.sh`](netstress.sh)

```
Runs ON the board: two 4K streams pulled over HTTP at once (the host's web server stands in for
Jellyfin), each decoded on rkvdec and shown full-screen through weston (HDMI + DP), while
measuring per-stream rendered/dropped frames, VOP underflows, NIC throughput/errors, CPU and
softirq load. Then a decode-only pass of the 400 Mbit/s 10-bit HEVC clip over HTTP.
netstress.sh <http base url> [seconds]      report: ~/netstress/report.txt
```

### [`rangeserver.py`](rangeserver.py)

```
Static file server with HTTP Range support (what a Jellyfin server does for direct play),
threaded, for streaming test clips to the board.  rangeserver.py <bind-ip> <port> <dir>
```
