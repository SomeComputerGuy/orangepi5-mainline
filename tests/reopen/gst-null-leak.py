#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
# Stop a decoder mid-stream N times in one process and count the dma-buf fds left open.
#   gst-null-leak.py N < PIPE    (PIPE as in matrix.sh, "{K}" = frames before EOS)
# Each cycle: new pipeline, play until k (1..6, varies) frames reached the sink, set it to NULL.
# Before the codecs fix (patches/gstreamer/0009) every stop with a frame still waiting for output
# leaked the decoder's 10 CAPTURE dma-bufs and, after ~12, starting failed with ENOMEM.
import gc, json, os, random, sys
sys.argv = [os.path.expanduser('~/reopen/mx.py')] + sys.argv[1:]
exec(open(sys.argv[0]).read().split("\nif __name__ == '__main__':")[0])


def dmabufs():
    n = 0
    for f in os.listdir('/proc/self/fd'):
        try:
            n += 'dmabuf' in os.readlink('/proc/self/fd/' + f)
        except OSError:
            pass
    return n


def allfds():
    return len(os.listdir('/proc/self/fd'))


N = int(sys.argv[1]) if len(sys.argv) > 1 else 500
desc = sys.stdin.read().strip()
rnd = random.Random(11)
fd0 = None
res = {'fds_growth': 0, 'cycles': 0, 'fail_start': 0, 'dmabufs_max': 0, 'dmabufs_end': 0, 'errors': [], 'k_hist': {}}
for i in range(1, N + 1):
    k = rnd.randint(1, 6)
    r = Run(desc.replace('{K}', '100000'), timeout=5)
    r.run(until=lambda r: len(r.times) >= k)
    r.stop()
    res['cycles'] = i
    res['k_hist'][k] = res['k_hist'].get(k, 0) + 1
    if r.errors or len(r.times) < k:
        res['fail_start'] += 1
        if len(res['errors']) < 10:
            res['errors'].append('cycle %d: %d frames, %s' % (i, len(r.times), r.errors[:1]))
    del r
    gc.collect()
    n = dmabufs()
    res['dmabufs_max'] = max(res['dmabufs_max'], n)
    if fd0 is None:
        fd0 = allfds()
    res['fds_growth'] = allfds() - fd0
    if i % 50 == 0:
        sys.stderr.write('cycle %d: %d dma-buf fds open, %d start failures\n' % (i, n, res['fail_start']))
res['dmabufs_end'] = dmabufs()
print(json.dumps(res))
