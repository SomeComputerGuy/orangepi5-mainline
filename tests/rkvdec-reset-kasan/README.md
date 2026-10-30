# rkvdec-reset-kasan: Build the KASAN/ODEBUG/lockdep test kernel and the instrumented rockchip-vdec module (fault injection) used for the rkvdec-reset proof

- Runs on: **host**
- How it was run: `bash build-kasan.sh; bash build-mod.sh <worktree> <kernel O dir> <out dir>`
- Notes and detailed results: [`topics/rkvdec-reset/`](../../topics/rkvdec-reset/README.md)
- Reference numbers: [`docs/RESULTS.md`](../../docs/RESULTS.md); how to re-run everything: [`docs/TESTING.md`](../../docs/TESTING.md); clips: [`docs/TEST-MEDIA.md`](../../docs/TEST-MEDIA.md)

These are the scripts exactly as they were run on the test board, except that the lab's own values are now defaults you can override: `OPI5_PI` (board login, default `ubuntu@orangepi5`), `OPI5_PI_IP` / `OPI5_HOST_IP` (board and host addresses, default the `scripts/nat-on.sh` subnet 172.31.55.0/24) and `$HOME` for the board user's home directory. Paths such as `~/demo` or `~/codecsweep` are on the board. Test media is not included (see TEST-MEDIA.md). C files are built on the board with `gcc -O2 -o <name> <name>.c` (plus `-ldrm` for DRM tools: see the file's header).

## Files

### [`build-kasan.sh`](build-kasan.sh)

```
Build the rkvdec-reset test kernel (build-5 config + KASAN/ODEBUG/lockdep) as
debs, in its own output dir so build/linux stays the image build.
Source: work/rkvdec-reset-kbase (v7.3 + patches/linux). Release 7.3.0-opi5-kasan.
```

### [`kasan.config`](kasan.config)


### [`build-mod.sh`](build-mod.sh)

```
build-mod.sh <worktree> <kernel O dir> <out dir> [v4l2]: build + sign rockchip-vdec.ko
(and v4l2-mem2mem.ko with "v4l2") from <worktree> against a configured kernel build.
```

### [`add-debug.py`](add-debug.py)

```
add-debug.py <rkvdec dir>: adds the DEBUG-only (never landed) instrumentation of
the rkvdec-reset test builds: register dumps of the core and its IOMMU at each step
of rkvdec_core_recover(), and fault injection (inject_fault=N: every Nth VDPU381
job gets an unmapped IOVA in one of its address registers).
```
