#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
# analyze-trace.py DIR: per-context breakdown of a trace-sameblock.sh run.
# Per rkvdec job of a context (keyed by its v4l2_m2m_ctx pointer):
#   ready  = both its OUTPUT and CAPTURE buffers queued and its previous job done
#   wait   = device_run - ready        (m2m scheduling / no free core)
#   setup  = hw start (watchdog armed, i.e. registers written) - device_run
#   hw     = job done - hw start       (decode on the core + interrupt + completion)
#   user   = next OUTPUT queued - job done (userspace)
# The steady context is the one with the most jobs. For every gap of the steady context's job
# completions above 2x its median, it prints the breakdown and what the other contexts did then.
import re, sys, statistics as st
from collections import defaultdict

LINE = re.compile(r'^\s*(.+?)-(\d+)\s+\[(\d+)\]\s+\S+\s+([\d.]+): (\w+): (.*)$')
OUT, CAP = 10, 9          # V4L2_BUF_TYPE_VIDEO_OUTPUT_MPLANE / CAPTURE_MPLANE


def kv(s):
    return dict(re.findall(r'(\w+)=(\S+)', s))


def load(path):
    ev = []
    for l in open(path):
        m = LINE.match(l)
        if m:
            comm, pid, cpu, ts, name, rest = m.groups()
            ev.append((float(ts), name, int(cpu), int(pid), comm, kv(rest), rest))
    return ev


def pct(v, p):
    v = sorted(v)
    return v[min(len(v) - 1, int(p / 100 * len(v)))] if v else 0


def main(d):
    ev = load(d + '/trace.txt')
    jobs = defaultdict(list)          # m2m -> [job dict]
    pend_out, pend_cap, last_done = defaultdict(list), defaultdict(list), {}
    cur_run = {}                      # cpu -> job (between run and hwstart)
    other = []                        # (ts, what) for B-side events
    for ts, name, cpu, pid, comm, a, raw in ev:
        m2m = a.get('m2m')
        if name == 'bufq':
            (pend_out if int(a['type'], 0) == OUT else pend_cap)[m2m].append(ts)
        elif name == 'run':
            r = max([pend_out[m2m][0] if pend_out[m2m] else ts,
                     pend_cap[m2m][0] if pend_cap[m2m] else ts, last_done.get(m2m, 0)])
            if pend_out[m2m]:
                pend_out[m2m].pop(0)
            if pend_cap[m2m]:
                pend_cap[m2m].pop(0)
            j = {'ready': min(r, ts), 'run': ts, 'hw': None, 'done': None, 'core': None}
            jobs[m2m].append(j)
            cur_run[cpu] = j
        elif name == 'hwstart' and cpu in cur_run:
            cur_run[cpu]['hw'] = ts
            cur_run[cpu]['core'] = a.get('core')
            del cur_run[cpu]
        elif name == 'done':
            for j in jobs[m2m]:
                if j['done'] is None:
                    j['done'] = ts
                    break
            last_done[m2m] = ts
        elif name in ('open', 'release', 'streamon', 'streamoff', 'createbufs', 'createbufs_ret',
                      'map', 'map_ret', 'unmap', 'unmap_ret'):
            other.append((ts, name, pid))
    if not jobs:
        print('no jobs traced')
        return
    steady = max(jobs, key=lambda k: len(jobs[k]))
    print('contexts: %d, steady %s with %d jobs, %d other jobs' % (
        len(jobs), steady[-6:], len(jobs[steady]), sum(len(v) for k, v in jobs.items() if k != steady)))

    def stats(js, label):
        w = [(j['run'] - j['ready']) * 1e3 for j in js]
        s = [(j['hw'] - j['run']) * 1e3 for j in js if j['hw']]
        h = [(j['done'] - j['hw']) * 1e3 for j in js if j['hw'] and j['done']]
        print('%-8s jobs %5d  wait ms p50 %6.2f p99 %6.2f max %6.2f | setup p50 %5.2f max %5.2f | '
              'hw p50 %6.2f p99 %6.2f max %6.2f' % (label, len(js), pct(w, 50), pct(w, 99), max(w or [0]),
                                                   pct(s, 50), max(s or [0]), pct(h, 50), pct(h, 99), max(h or [0])))
    stats(jobs[steady], 'steady')
    stats([j for k, v in jobs.items() if k != steady for j in v], 'others')
    cores = defaultdict(int)
    for j in jobs[steady]:
        cores[j['core']] += 1
    print('steady jobs per core:', dict(cores))
    done = [j for j in jobs[steady] if j['done']]
    gaps = [(b['done'] - a['done'], a, b) for a, b in zip(done, done[1:])]
    med = st.median(g for g, _, _ in gaps) if gaps else 0
    big = [x for x in gaps if x[0] > 2 * med]
    print('steady completion gaps: median %.1f ms, p99 %.1f, max %.1f, %d above 2x median' % (
        med * 1e3, pct([g for g, _, _ in gaps], 99) * 1e3, max(g for g, _, _ in gaps) * 1e3 if gaps else 0, len(big)))
    for g, a, b in sorted(big, key=lambda x: -x[0])[:15]:
        t0, t1 = a['done'], b['done']
        oth = [j for k, v in jobs.items() if k != steady for j in v if j['run'] < t1 and (j['done'] or t1) > t0]
        evs = defaultdict(int)
        for ts, n, pid in other:
            if t0 <= ts <= t1:
                evs[n] += 1
        unmap_ms = 0
        st_ = {}
        for ts, n, pid in other:
            if t0 <= ts <= t1 and n in ('unmap', 'map'):
                st_[(pid, n)] = ts
            if t0 <= ts <= t1 and n in ('unmap_ret', 'map_ret') and (pid, n[:-4]) in st_:
                unmap_ms += (ts - st_.pop((pid, n[:-4]))) * 1e3
        print('  gap %6.1f ms at %.3f: wait %5.1f setup %4.1f hw %5.1f (core %s) | other ctx jobs overlapping %d '
              '| B events %s | iommu map+unmap %.1f ms' % (
                  g * 1e3, t0, (b['run'] - b['ready']) * 1e3, ((b['hw'] or b['run']) - b['run']) * 1e3,
                  ((b['done'] or 0) - (b['hw'] or b['run'])) * 1e3, (b['core'] or '?')[-4:], len(oth),
                  dict(evs), unmap_ms))


main(sys.argv[1])
