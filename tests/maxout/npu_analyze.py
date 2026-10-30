#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Reads raw RGB frames (W*H*3 bytes each) from stdin (GStreamer fdsink after RGA scaling), runs a
uint8 TFLite model on the NPU via Mesa Teflon, logs per-second rate/latency/top label, and every
N-th frame also runs the same frame on the CPU and records top-1 agreement and max abs diff.
usage: npu_analyze.py MODEL LABELS LOG [--cmp-every 30]
Run with the system python3 (python3-gi not needed) and
PYTHONPATH=~/npu-venv/lib/python3.14/site-packages."""
import sys, time, argparse
import numpy as np
from ai_edge_litert import interpreter as litert

ap = argparse.ArgumentParser()
ap.add_argument("model"); ap.add_argument("labels"); ap.add_argument("log")
ap.add_argument("--cmp-every", type=int, default=30)
ap.add_argument("--fifo", help="read frames from this FIFO, reopening it after each EOF until STOPFILE exists")
ap.add_argument("--stopfile")
ap.add_argument("--delegate", default="/usr/lib/teflon/libteflon.so")
a = ap.parse_args()
labels = [l.strip() for l in open(a.labels)]
npu = litert.Interpreter(model_path=a.model, experimental_delegates=[litert.load_delegate(a.delegate)])
cpu = litert.Interpreter(model_path=a.model, num_threads=2)
for it in (npu, cpu):
    it.allocate_tensors()
inp = npu.get_input_details()[0]; out = npu.get_output_details()[0]
_, H, W, _ = inp["shape"]; fsz = W * H * 3
log = open(a.log, "w", buffering=1)
log.write(f"# model={a.model} input={W}x{H}\n")
n = sec_n = cmp_n = agree = 0; maxdiff = 0; lat = []; t_sec = time.time(); errors = 0
import os
src = open(a.fifo, "rb") if a.fifo else sys.stdin.buffer
reopens = 0
import signal
def _term(*_):
    raise KeyboardInterrupt
signal.signal(signal.SIGTERM, _term)
try:
  while True:
      buf = src.read(fsz)
      if len(buf) < fsz:
          if a.fifo and not os.path.exists(a.stopfile or "/nonexistent"):
              src.close(); src = open(a.fifo, "rb"); reopens += 1
              log.write(f"REOPEN {time.time():.3f} {reopens}\n")
              continue
          break
      x = np.frombuffer(buf, np.uint8).reshape(1, H, W, 3)
      t = time.perf_counter()
      try:
          npu.set_tensor(inp["index"], x); npu.invoke()
      except Exception as e:  # NPU error: count and continue
          errors += 1; log.write(f"ERROR {time.time():.3f} {e}\n"); continue
      lat.append((time.perf_counter() - t) * 1000)
      y = npu.get_tensor(out["index"])[0].copy(); n += 1; sec_n += 1
      if n % a.cmp_every == 0:
          cpu.set_tensor(inp["index"], x); cpu.invoke()
          yc = cpu.get_tensor(out["index"])[0]
          cmp_n += 1; agree += int(np.argmax(y) == np.argmax(yc))
          d = int(np.max(np.abs(y.astype(int) - yc.astype(int)))); maxdiff = max(maxdiff, d)
          log.write(f"CMP {time.time():.3f} npu={labels[int(np.argmax(y))]!r} cpu={labels[int(np.argmax(yc))]!r} maxdiff={d} npu_top2={sorted(y)[-1]},{sorted(y)[-2]} cpu_top2={sorted(yc)[-1]},{sorted(yc)[-2]}\n")
      now = time.time()
      if now - t_sec >= 1.0 and lat:
          top = int(np.argmax(y))
          l = np.array(lat)
          log.write(f"SEC {now:.3f} inf/s={sec_n/(now-t_sec):.1f} lat_mean={l.mean():.2f} lat_max={l.max():.2f} "
                    f"top={labels[top] if top < len(labels) else top}({y[top]})\n")
          sec_n = 0; lat = []; t_sec = now
except KeyboardInterrupt:
    pass
log.write(f"TOTAL inferences={n} errors={errors} reopens={reopens} cpu_compared={cmp_n} top1_agree={agree} maxdiff={maxdiff}\n")
