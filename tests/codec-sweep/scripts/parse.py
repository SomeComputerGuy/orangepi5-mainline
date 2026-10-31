#!/usr/bin/env python3
"""Per-frame timeline from trace.sh output (function_graph + irq events).

Single-stream analysis: each rkvdec_device_run is followed by one rkvdec IRQ.
"""
import re, sys, statistics as st

ent = re.compile(r'^\s*([\d.]+) \|\s+(\d+)\)\s+(\S+)\s+\|\s+([+!#*@$ ]?\s*[\d.]+ us)?\s*\|\s+(.*)$')
def parse(path):
    stacks = {}
    ev = []
    for line in open(path):
        if 'irq_handler_entry' in line:
            m = re.match(r'^\s*([\d.]+) \|\s+(\d+)\).*name=(\S+)', line)
            if m: ev.append((float(m.group(1)), 'irq', 0, m.group(3)))
            continue
        if 'rkvirq:' in line:
            m = re.match(r'^\s*([\d.]+) \|.*core=(\S+)', line)
            if m: ev.append((float(m.group(1)), 'hirq', 0, m.group(2).rstrip('*/ ')))
            continue
        if 'rkvwd:' in line:
            m = re.match(r'^\s*([\d.]+) \|\s+(\d+)\)\s+(\S+).*core=(\S+)', line)
            if m: ev.append((float(m.group(1)), 'kick', 0, (m.group(4), m.group(3))))
            continue
        m = ent.match(line)
        if not m: continue
        t, cpu, task, dur, rest = m.groups()
        t = float(t); cpu = int(cpu)
        rest = rest.strip()
        s = stacks.setdefault(cpu, [])
        if rest.endswith('{'):
            name = rest.split()[0].rstrip('()')
            s.append((name, t, task))
        elif rest.startswith('}'):
            if not s: continue
            name, t0, task0 = s.pop()
            d = float(re.findall(r'[\d.]+', dur)[0]) if dur else 0
            ev.append((t0, name, d, task0))
        elif rest.endswith(';'):
            name = rest.split()[0].rstrip('();')
            d = float(re.findall(r'[\d.]+', dur)[0]) if dur else 0
            ev.append((t, name, d, task))
    ev.sort(key=lambda e: e[0])
    return ev

def summ(name, vals):
    if not vals: return
    vals = sorted(vals)
    print(f"  {name:38s} n={len(vals):4d} mean={st.mean(vals):8.1f} med={vals[len(vals)//2]:8.1f} p90={vals[int(len(vals)*.9)]:8.1f} us")

def main(path):
    ev = parse(path)
    runs = [e for e in ev if e[1] == 'rkvdec_device_run']
    irqs = [e for e in ev if e[1] == 'irq']
    hand = [e for e in ev if e[1] == 'rkvdec_irq_handler']
    print(path, f"runs={len(runs)} irqs={len(irqs)} handlers={len(hand)}")
    by = {}
    for e in ev:
        by.setdefault(e[1], []).append(e[2])
    for k in ('rkvdec_device_run', 'rkvdec_vp9_run', 'v4l2_ctrl_request_setup', 'v4l2_vp9_fw_update_probs',
              'rkvdec_memcpy_toio', 'rkvdec_irq_handler', 'rkvdec_vp9_done', 'v4l2_vp9_adapt_coef_probs',
              'v4l2_vp9_adapt_noncoef_probs', 'v4l2_m2m_buf_done_and_job_finish', 'v4l2_s_ext_ctrls',
              'media_request_ioctl'):
        summ(k, by.get(k, []))
    # timeline: per core, kick (watchdog armed just before DEC_E) -> irq -> handler -> next kick
    kicks = [e for e in ev if e[1] == 'kick']
    cores = {}
    for k in kicks:
        cores.setdefault(k[3][0], []).append(k[0])
    # map core ptr -> irq name: first irq after first kick of that core
    names = sorted(set(e[3] for e in irqs))
    irq_by = {n: [e[0] for e in irqs if e[3] == n] for n in names}
    hand_t = [(h[0], h[0] + h[2] * 1e-6) for h in hand]
    tot_hw = {}
    hirq = [e for e in ev if e[1] == 'hirq']
    for ptr, ks in cores.items():
        if hirq:
            # threaded handler entries for this core; use the hard irq that precedes each
            hs = [e[0] for e in hirq if e[3] == ptr]
            ir_all = [e for e in irqs]
            nm = {}
            ir = []
            for t in hs:
                prev = [x for x in ir_all if x[0] <= t and t - x[0] < 0.01]
                if prev:
                    ir.append(prev[-1][0]); nm[prev[-1][3]] = nm.get(prev[-1][3], 0) + 1
            n = max(nm, key=nm.get) if nm else '?'
        else:
            n = None
        if n is None:
          best = None
          for n in names:
              hits = sum(1 for k in ks[:50] if any(0 < t - k < 0.1 for t in irq_by[n][:60]))
              if best is None or hits > best[0]: best = (hits, n)
          n = best[1]
          ir = irq_by[n]
        hw, lat, idle, period = [], [], [], []
        ii = 0
        busy = 0.0
        for a, k in enumerate(ks):
            while ii < len(ir) and ir[ii] < k: ii += 1
            if ii >= len(ir): break
            ti = ir[ii]
            hw.append((ti - k) * 1e6)
            busy += ti - k
            h = next((x for x in hand_t if x[0] >= ti), None)
            if h:
                lat.append((h[0] - ti) * 1e6)
                if a + 1 < len(ks):
                    idle.append((ks[a + 1] - h[1]) * 1e6)
                    period.append((ks[a + 1] - k) * 1e6)
        span = ks[-1] - ks[0] if len(ks) > 1 else 1
        print(f" core {n} ({ptr}): {len(ks)} frames, hw busy {100*busy/span:.0f}% of {span:.2f}s")
        summ('hw (DEC_E -> irq)', hw)
        summ('irq -> threaded handler start', lat)
        summ('core idle (handler end -> next DEC_E)', idle)
        summ('frame period on this core', period)
    who = {}
    for k in kicks:
        t = k[3][1].split('-')[0]
        who[t] = who.get(t, 0) + 1
    print("  frames started from:", who)

for p in sys.argv[1:]:
    main(p); print()
