#!/usr/bin/env python3
"""MobileNet classification: CPU (XNNPACK/builtin) vs Mesa Teflon (rocket NPU).

usage: classify.py MODEL LABELS IMAGE [IMAGE...] [--delegate /usr/lib/teflon/libteflon.so]
                   [--runs N] [--threads T] [--save-out FILE.npy]
Prints per-image top-5, mean/min/median latency of invoke(), and
optionally saves raw outputs so CPU and NPU runs can be compared.
"""
import argparse
import statistics
import time

import numpy as np
from PIL import Image
from ai_edge_litert import interpreter as litert


def load_labels(path):
    with open(path) as f:
        return [l.strip() for l in f]


def label_for(labels, idx, nout):
    # Coral labels have "N  name" format with 1001 classes incl. background.
    if idx < len(labels):
        return labels[idx]
    return str(idx)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("model")
    ap.add_argument("labels")
    ap.add_argument("images", nargs="+")
    ap.add_argument("--delegate")
    ap.add_argument("--runs", type=int, default=50)
    ap.add_argument("--threads", type=int, default=4)
    ap.add_argument("--save-out")
    a = ap.parse_args()

    delegates = []
    if a.delegate:
        delegates = [litert.load_delegate(a.delegate)]
    t0 = time.perf_counter()
    it = litert.Interpreter(model_path=a.model, experimental_delegates=delegates,
                            num_threads=a.threads)
    it.allocate_tensors()
    t_setup = time.perf_counter() - t0
    inp = it.get_input_details()[0]
    out = it.get_output_details()[0]
    _, h, w, _ = inp["shape"]
    print(f"model={a.model} delegate={a.delegate} input={inp['shape']} {inp['dtype'].__name__} "
          f"output={out['shape']} {out['dtype'].__name__} setup={t_setup*1000:.1f}ms")
    labels = load_labels(a.labels)

    outs = []
    for path in a.images:
        img = Image.open(path).convert("RGB").resize((w, h), Image.BILINEAR)
        x = np.expand_dims(np.asarray(img, dtype=np.uint8), 0)
        if inp["dtype"] != np.uint8:
            raise SystemExit("expected a uint8 quantized model")
        it.set_tensor(inp["index"], x)
        t = time.perf_counter()
        it.invoke()
        first = (time.perf_counter() - t) * 1000
        times = []
        for _ in range(a.runs):
            t = time.perf_counter()
            it.invoke()
            times.append((time.perf_counter() - t) * 1000)
        y = it.get_tensor(out["index"])[0].copy()
        outs.append(y)
        top = np.argsort(y)[::-1][:5]
        print(f"image={path} first={first:.2f}ms mean={statistics.mean(times):.2f}ms "
              f"median={statistics.median(times):.2f}ms min={min(times):.2f}ms runs={a.runs}")
        for i in top:
            print(f"   {i:4d} {y[i]:3d}  {label_for(labels, i, len(y))}")
    if a.save_out:
        np.save(a.save_out, np.stack(outs))


if __name__ == "__main__":
    main()
