# reopen: Codec reopen matrix: one block streams steadily (per-frame md5 checked) while another opens, streams and closes as fast as it can, for every decoder/encoder/NPU pair; mid-stream NULL dma-buf leak proof; per-job trace analysis

- Runs on: **board** (copy this directory to the board, e.g. with `scp -r`)
- How it was run: `bash matrix.sh (from ~/reopen on the board; see the header for the blocks)`
- Notes and detailed results: [`topics/rkvdec-reset/`](../../topics/rkvdec-reset/README.md)
- Reference numbers: [`docs/RESULTS.md`](../../docs/RESULTS.md); how to re-run everything: [`docs/TESTING.md`](../../docs/TESTING.md); clips: [`docs/TEST-MEDIA.md`](../../docs/TEST-MEDIA.md)

These are the scripts exactly as they were run on the test board, except that the lab's own values are now defaults you can override: `OPI5_PI` (board login, default `ubuntu@orangepi5`), `OPI5_PI_IP` / `OPI5_HOST_IP` (board and host addresses, default the `scripts/nat-on.sh` subnet 172.31.55.0/24) and `$HOME` for the board user's home directory. Paths such as `~/demo` or `~/codecsweep` are on the board. Test media is not included (see TEST-MEDIA.md). C files are built on the board with `gcc -O2 -o <name> <name>.c` (plus `-ldrm` for DRM tools: see the file's header).

## Files

### [`matrix.sh`](matrix.sh)

```
Reopen matrix: block A streams steadily (output checked) while block B cycles
open -> stream K frames -> close as fast as it can, for every pair (A, B), including A == B
(a second context on the same block). Runs ON the board from ~/reopen (mx.py, npu-loop.py,
venc-cycle next to it).

matrix.sh prep                      make the test media and reference checksums (once per boot)
matrix.sh pair A B VARIANT [N]       one pair; VARIANT: normal | kill | abort | restart
matrix.sh chunk NAME "A:B:V[:N] ..."  several pairs, one results table (results/NAME/table.md)
matrix.sh all [N]                    print the chunk plan for every pair (<= 45 min each)

Variants for B: normal = EOS after K frames and close; kill = SIGKILL mid-stream; abort = close
with buffers still queued (decoders: pipeline to NULL mid-stream; encoders: exit with jobs in
flight); restart = STREAMOFF/STREAMON without closing (decoders: flushing seek; encoders: -k).
A must not stall (gap > 2 x period), mismatch its reference, error or make the kernel log a
warning; B must never fail to open or start, and its output must match its reference too.
```

### [`mx.py`](mx.py)

```
Reopen matrix helper: one role per process, results as one JSON line on stdout.
mx.py ref    PIPE OUT.md5                       per-frame md5 list of PIPE run alone
mx.py steady PIPE --ref R --period P --stop F   loop PIPE until file F exists; check md5/gaps
mx.py cycle  PIPE --ref R --frames K --cycles N --variant V [--stop F]
mx.py once   PIPE                                (used by variant kill) prints "F n" per frame
mx.py vref   "VENC ARGS" OUT.ref                 venc-cycle -T solo run: per-frame hashes
mx.py vsteady "VENC ARGS" --ref R --period P --stop F --wrap W   (-r looping encoder, ref[i % W])
mx.py vcycle "VENC ARGS" --ref R --frames K --cycles N --variant normal|abort|kill|restart
mx.py csteady "CMD" --period P --stop F [--md5 FILE]  CMD run back to back (blocks without a
streaming client), run time > 2*P is a stall
mx.py ccycle "CMD" --cycles N [--md5 FILE] [--kill S] CMD per cycle; output file $OUT checked
PIPE is a gst-launch description that ends in "videocodectestsink name=chk" (md5 per frame)
or "fakesink name=chk" (frame timing only). "{K}" in PIPE is replaced by the frame count.
Variants: normal (EOS after K frames, close), nullmid (NULL after k<K frames: buffers still queued),
flush (one pipeline, flushing seek to 0 every K frames: decoder STREAMOFF/STREAMON, no close),
kill (child process SIGKILLed after k<K frames).
```

### [`npu-loop.py`](npu-loop.py)

```
NPU role for the reopen matrix (Mesa Teflon delegate, MobileNet v1 quant).
npu-loop.py steady MODEL --stop F --period P     one interpreter, inference back to back
npu-loop.py cycle  MODEL --cycles N --frames K [--kill]  open delegate, K inferences, close
Every output must be byte-identical to the first NPU output of a fixed input (the NPU is
deterministic); a gap > 2 * P between inferences is a stall. One JSON line on stdout.
```

### [`leak-proof.sh`](leak-proof.sh)

```
500 mid-stream NULLs per decoder (rkvdec H.264 4K, rkvdec HEVC 4K, Hantro H.264 1080p) in one
process each; PASS = 0 start failures and 0 dma-buf fds left open after every cycle.
leak-proof.sh [N=500]     (on the board, from ~/reopen)
```

### [`trace-sameblock.sh`](trace-sameblock.sh)

```
Where does a steady rkvdec context lose time while a second context cycles on rkvdec?
trace-sameblock.sh A B SECS      (block names from matrix.sh; run from ~/reopen on the board)
Traces, for every rkvdec job: the OUTPUT buffer handed to the driver (vb2_buf_queue, i.e. the
request was queued), device_run() (job start: kprobe, ctx pointer), the core's interrupt
(irq_handler_entry), vb2_buf_done of OUTPUT and CAPTURE, and the userspace DQBUF (v4l2_dqbuf),
plus B's open/release/STREAMON/STREAMOFF/CREATE_BUFS and the rk_iommu map/unmap work. Raw
trace -> results/trace-<time>/trace.txt; analyze-trace.py prints the per-context breakdown.
```

### [`analyze-trace.py`](analyze-trace.py)

```
analyze-trace.py DIR: per-context breakdown of a trace-sameblock.sh run.
Per rkvdec job of a context (keyed by its v4l2_m2m_ctx pointer):
ready  = both its OUTPUT and CAPTURE buffers queued and its previous job done
wait   = device_run - ready        (m2m scheduling / no free core)
setup  = hw start (watchdog armed, i.e. registers written) - device_run
hw     = job done - hw start       (decode on the core + interrupt + completion)
user   = next OUTPUT queued - job done (userspace)
The steady context is the one with the most jobs. For every gap of the steady context's job
completions above 2x its median, it prints the breakdown and what the other contexts did then.
```

### [`tools/gst-null-leak.py`](tools/gst-null-leak.py)

```
Stop a decoder mid-stream N times in one process and count the dma-buf fds left open.
gst-null-leak.py N < PIPE    (PIPE as in matrix.sh, "{K}" = frames before EOS)
Each cycle: new pipeline, play until k (1..6, varies) frames reached the sink, set it to NULL.
Before the codecs fix (patches/gstreamer/0009) every stop with a frame still waiting for output
leaked the decoder's 10 CAPTURE dma-bufs and, after ~12, starting failed with ENOMEM.
```

### [`tools/venc-cycle.c`](tools/venc-cycle.c)

```

venc-cycle: rkvenc-enc (maxout/tools) plus the reopen-fix test options:
-r loop the input, -k N STREAMOFF/STREAMON every N frames, -a N exit
with jobs in flight after N frames, -T per-frame completion times.

rkvenc-enc: minimal V4L2 stateless H.264 / HEVC encoder client

Drives the rockchip-venc (VEPU580) driver through the request API using
the H.264 stateless encode uAPI proposed by Paul Kocialkowski
(V4L2_CID_STATELESS_H264_ENCODE_PARAMS) or the proposed HEVC stateless
encode uAPI (V4L2_CID_STATELESS_HEVC_ENCODE_PARAMS, -e hevc). Reads raw
NV12 frames, writes an Annex-B H.264 or H.265 elementary stream.

Build: aarch64-linux-gnu-gcc -O2 -Wall -I<kernel uapi headers> -o rkvenc-enc rkvenc-enc.c

```
