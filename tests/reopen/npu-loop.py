#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
# NPU role for the reopen matrix (Mesa Teflon delegate, MobileNet v1 quant).
#   npu-loop.py steady MODEL --stop F --period P     one interpreter, inference back to back
#   npu-loop.py cycle  MODEL --cycles N --frames K [--kill]  open delegate, K inferences, close
# Every output must be byte-identical to the first NPU output of a fixed input (the NPU is
# deterministic); a gap > 2 * P between inferences is a stall. One JSON line on stdout.
import json, os, random, signal, subprocess, sys, time, hashlib
import numpy as np
from ai_edge_litert import interpreter as litert

DELEGATE = '/usr/lib/teflon/libteflon.so'


def arg(n, d=None, conv=str):
    return conv(sys.argv[sys.argv.index(n) + 1]) if n in sys.argv else d


def make(model):
    it = litert.Interpreter(model_path=model, experimental_delegates=[litert.load_delegate(DELEGATE)])
    it.allocate_tensors()
    i = it.get_input_details()[0]
    rng = np.random.default_rng(7)
    x = rng.integers(0, 256, size=i['shape'], dtype=np.uint8)
    return it, i, it.get_output_details()[0], x


def infer(it, i, o, x):
    it.set_tensor(i['index'], x)
    it.invoke()
    return hashlib.md5(it.get_tensor(o['index']).tobytes()).hexdigest()


def ref_path(model):
    return '/tmp/npu-ref.%s.md5' % os.path.basename(model)


def main():
    role, model = sys.argv[1], sys.argv[2]
    if role == 'ref':
        it, i, o, x = make(model)
        h = infer(it, i, o, x)
        open(ref_path(model), 'w').write(h + '\n')
        print(json.dumps({'role': 'npuref', 'md5': h}))
        return
    ref = open(ref_path(model)).read().strip()
    if role == 'steady':
        stop, period = arg('--stop'), arg('--period', 0.05, float)
        res = {'role': 'npusteady', 'runs': 1, 'frames': 0, 'bad_md5': 0, 'stalls': 0, 'max_gap_ms': 0, 'errors': []}
        it, i, o, x = make(model)
        last = time.monotonic()
        while not os.path.exists(stop):
            h = infer(it, i, o, x)
            now = time.monotonic()
            g = now - last
            last = now
            res['frames'] += 1
            res['max_gap_ms'] = max(res['max_gap_ms'], int(g * 1000))
            if g > 2 * period and res['frames'] > 1:
                res['stalls'] += 1
                if len(res['errors']) < 10:
                    res['errors'].append('%.0f ms between inferences %d and %d' % (g * 1000, res['frames'] - 1, res['frames']))
            if h != ref:
                res['bad_md5'] += 1
        print(json.dumps(res))
    elif role == 'once':
        it, i, o, x = make(model)
        while True:
            infer(it, i, o, x)
            sys.stdout.write('F\n')
            sys.stdout.flush()
    elif role == 'cycle':
        N, K, kill = arg('--cycles', 200, int), arg('--frames', 10, int), '--kill' in sys.argv
        res = {'role': 'npucycle', 'variant': 'kill' if kill else 'normal', 'cycles': 0, 'fail_open': 0,
               'fail_start': 0, 'bad_md5': 0, 'errors': [], 'start_ms_max': 0}
        rnd = random.Random(5)
        for c in range(1, N + 1):
            res['cycles'] = c
            t = time.monotonic()
            if kill:
                p = subprocess.Popen([sys.executable, __file__, 'once', model], stdout=subprocess.PIPE,
                                     stderr=subprocess.DEVNULL, text=True)
                k, got = rnd.randint(1, K), 0
                for line in p.stdout:
                    got += 1
                    if got >= k or time.monotonic() - t > 20:
                        break
                p.send_signal(signal.SIGKILL)
                p.wait()
                if got < k:
                    res['fail_start'] += 1
                    res['errors'].append('cycle %d: %d inferences before the kill, wanted %d' % (c, got, k))
                continue
            try:
                it, i, o, x = make(model)
            except Exception as e:
                res['fail_open'] += 1
                res['errors'].append('cycle %d: %s' % (c, e))
                continue
            for _ in range(K):
                if infer(it, i, o, x) != ref:
                    res['bad_md5'] += 1
            res['start_ms_max'] = max(res['start_ms_max'], int((time.monotonic() - t) * 1000))
            del it
        res['errors'] = res['errors'][:20]
        print(json.dumps(res))


main()
