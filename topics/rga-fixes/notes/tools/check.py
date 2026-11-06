#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""rga-fu mechanical checks (from rga3-nv15). check.py RUNDIR KREV  (python3 -I). Last line: OVERALL PASS|FAIL.

The run has no stock-15 session (STOCK=0): the stock baseline for the regress phase is the stock session of
the rga3-nv15 run rga1 (same stock 15 kernel and the same regress tools), work/_out/k15/rga3-nv15/run-rga1/out/stock.
"""
import os, re, subprocess, sys

R, KREV = sys.argv[1:3]
QUICK = True   # no stock session in this run; compliance must be clean on its own
T = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(R, 'out')
BASE = os.path.join(T, '..', '..', 'rga3-nv15', 'run-rga1', 'out')   # holds stock/
res = []


def rd(*p):
    try:
        return open(os.path.join(*p), errors='replace').read()
    except OSError:
        return ''


def chk(name, ok, info=''):
    res.append(bool(ok))
    print('PASS' if ok else 'FAIL', name, info)


# 1. stock restored, lock released
host = rd(R, 'host.log')
un = re.findall(r'uname -v: (.*)', host)
chk('stock-restored', un and re.search(r'#15 SMP.*Wed Nov  *4 20:25:22', un[-1]) and 'lock released' in host,
    un[-1] if un else 'no uname -v line')
# 2. boot of the test kernel
b = rd(R, f'boot-{KREV}.txt')
chk(f'boot-{KREV}', re.search(rf'^7\.3\.0-opi5 #{KREV} ', b, re.M) and re.search(r'^warn=0$', b, re.M) and
    re.search(r'^usb_missing=$', b, re.M) and re.search(r'^iommu_err=0$', b, re.M),
    ' '.join(l for l in b.splitlines() if l.startswith(('warn=', 'usb_missing=', 'iommu_err='))))
# 3. RGA3 lists the new formats and controls
info = rd(OUT, 'test', 'info.txt')
m = re.search(r'Card type\s*: rga3(.*?)(Card type|\Z)', info, re.S)
r3 = m.group(1) if m else ''
outq = re.search(r"Type: Video Output Multiplanar(.*?)(Type: Video Capture|User Controls|\Z)", r3, re.S)
capq = re.search(r"Type: Video Capture Multiplanar(.*?)(User Controls|\Z)", r3, re.S)
o, c = (outq.group(1) if outq else ''), (capq.group(1) if capq else '')
F = ('NV15', 'P010', 'NV20')
chk('rga3-formats', all(f"'{x}'" in o and f"'{x}'" in c for x in F),
    ', '.join(f"{x} out {chr(39)+x+chr(39) in o} cap {chr(39)+x+chr(39) in c}" for x in F))
chk('rga3-controls', all(x in r3 for x in ('horizontal_flip', 'vertical_flip', 'rotate')), 'hflip/vflip/rotate listed')
# 4. v4l2-compliance no worse than stock
for n in ('rga2', 'rga3'):
    tot = {}
    for s in ('stock', 'test'):
        t = re.search(r'^Total for .*: (\d+), Succeeded: (\d+), Failed: (\d+), Warnings: (\d+)', rd(BASE if s == 'stock' else OUT, s, f'compliance-{n}.txt'), re.M)
        tot[s] = tuple(map(int, t.groups())) if t else None
    ok = tot['test'] is not None and tot['test'][2] == 0 and (QUICK or (tot['stock'] is not None and tot['test'][2] <= tot['stock'][2]))
    if QUICK:
        ok = ok and tot['test'][0] == tot['test'][1]
    chk(f'compliance-{n}', ok, f"stock {tot['stock']} test {tot['test']} (total, ok, failed, warnings)")
# 5. RGA2 regression (k14/datasheet/d2) on both kernels
for s in ('stock', 'test'):
    d = os.path.join(BASE if s == 'stock' else OUT, s, 'rga2reg')
    if os.path.isdir(d):
        if s == 'test':
            open(os.path.join(d, 'board.txt'), 'w').write(rd(OUT, s, 'rga2reg-board.txt'))
        v = subprocess.run(['python3', '-I', os.path.join(T, '..', '..', '..', 'k14', 'datasheet', 'd2', 'rga2-regress-judge.py'), d],
                           capture_output=True, text=True).stdout
        if s == 'test':
            open(os.path.join(OUT, s, 'rga2reg-verdict.txt'), 'w').write(v)
    else:
        v = ''
    fails = [l for l in v.splitlines() if l.startswith('FAIL')]
    if s == 'test':
        chk('rga2-regress-test', v.rstrip().endswith('OVERALL PASS'), '; '.join(fails) or 'OVERALL PASS' if v else 'not run')
    else:
        print('INFO rga2-regress-stock', v.splitlines()[-1] if v else 'not run')
# 6. RGA3 regression (k12/rga3 board-tests.sh func): same per-case CRC sets and gst md5s as stock
def k12(s):
    f = rd(BASE if s == 'stock' else OUT, s, 'k12func', 'func.txt')
    cases = dict(re.findall(r'^case (\S+) (rc=.*)$', f, re.M))
    gst = dict(re.findall(r'^gst (\S+) (rc=.*)$', f, re.M))
    kern = re.search(r'^kernel rga errors: (\d+) warn (\d+)', f, re.M)
    return f, cases, gst, kern
fs, cs, gs, ks = k12('stock')
ft, ct, gt, kt = k12('test')
def md5(v):
    m = re.search(r'set_md5 (\S+)', v)
    return m.group(1) if m else None
same = [k for k in cs if k in ct and md5(cs[k]) == md5(ct[k]) and 'rc=0' in ct[k] and ' errors 0 ' in ct[k]]
chk('rga3-regress-cases', cs and len(same) == len(cs) == len(ct), f'{len(same)}/{len(cs)} cases same CRC set as stock, rc=0, errors 0')
gsame = [k for k in gs if k in gt and gs[k].split('md5')[-1] == gt[k].split('md5')[-1] and 'rc=0' in gt[k]]
chk('rga3-regress-gst', len(gsame) == len(gs) == len(gt), f'{len(gsame)}/{len(gs)} v4l2convert outputs identical to stock (test has {len(gt)})')
chk('rga3-regress-kernel', kt and kt.groups() == ('0', '0'), f"rga errors/warn {kt.groups() if kt else None} (stock {ks.groups() if ks else None})")
# 7. new-feature cases (judge.py) on the test kernel; stock run listed as INFO baseline
for s in ('test',):
    d = os.path.join(OUT, s)
    if not os.path.exists(os.path.join(d, 'cases.tsv')):
        chk(f'cases-{s}', False, 'no cases.tsv')
        continue
    v = subprocess.run(['python3', '-I', os.path.join(T, 'judge.py'), os.path.join(T, 'cases.txt'),
                        os.path.join(T, '..', 'inputs'), d], capture_output=True, text=True)
    open(os.path.join(d, 'judge.txt'), 'w').write(v.stdout + v.stderr)
    for l in v.stdout.splitlines():
        tag, cid = l.split()[:2]
        if s == 'test' and tag in ('PASS', 'FAIL'):
            chk(f'case {cid}', tag == 'PASS', l.split(None, 2)[2] if len(l.split(None, 2)) > 2 else '')
        else:
            print('INFO', s, l)
    if v.returncode:
        chk(f'judge-{s}', False, v.stderr.strip().splitlines()[-1:])
# 8. kernel log of the test session
pat = re.compile(r'WARNING|BUG:|Oops|Call trace|rk_iommu.*fault|[Pp]age fault|job timed out|error interrupt|'
                 r'Failed to map video buffer|soft reset timed out')
bad = []
for root, _, files in os.walk(os.path.join(OUT, 'test')):
    for f in files:
        if f.startswith('dmesg'):
            bad += [f'{f}: {l}' for l in rd(root, f).splitlines() if pat.search(l)]
chk('dmesg-clean-test', not bad, f'{len(bad)} lines' + (': ' + ' | '.join(bad[:5]) if bad else ''))
print('OVERALL', 'PASS' if all(res) else 'FAIL')
