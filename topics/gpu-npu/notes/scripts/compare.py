#!/usr/bin/env python3
"""compare.py CPU.npy NPU.npy -> top-1/top-5 agreement and output diffs."""
import sys

import numpy as np

a = np.load(sys.argv[1]).astype(np.int32)
b = np.load(sys.argv[2]).astype(np.int32)
for i, (x, y) in enumerate(zip(a, b)):
    t1 = int(np.argmax(x)) == int(np.argmax(y))
    t5 = len(set(np.argsort(x)[-5:]) & set(np.argsort(y)[-5:]))
    d = np.abs(x - y)
    print(f"img{i}: top1 cpu={np.argmax(x)} npu={np.argmax(y)} agree={t1} "
          f"top5-overlap={t5}/5 maxabsdiff={d.max()} meanabsdiff={d.mean():.3f}")
