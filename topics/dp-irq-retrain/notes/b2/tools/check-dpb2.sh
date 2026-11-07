#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Mechanical checks for JOB dp-black-2. One line per check (PASS/FAIL/INFO), last line
# "OVERALL PASS|FAIL|INCONCLUSIVE".
#   check-dpb2.sh [workdir]     default ~/orangepi5/work/_out/k15/dp-silent-black/b2
# Blocks run-D1..D7 (7.3.0-16dpb1), arms by the iter.tsv column gate=: 0 = old order (VOP2 DP interface enabled in
# the CRTC enable, like stock), 1 = fix (interface enabled after the DP encoder).
# black = both camera verdicts of an iteration BLACK on DP-1 (DP=BLACK and DP2=BLACK).
# Reference for the rate = gate=0 arm + the stock data of JOB dp-black-1 (2 black of 360 valid: 1/180 stock 15,
# 1/180 15dpirq1, which did not change the rate).
# PASS = every block restored a stock kernel (plain "#N SMP" uname, no test suffix) and released the lock; boot checks clean; >= 1300 rows with >= 600 valid
# camera verdicts per arm; 0 WARNING/BUG/Oops/Call trace lines; no error type in the gate=1 arm that the gate=0 arm
# does not have; 0 "video FIFO overflow" in the gate=1 arm; failed commits gate=1 <= gate=0; and
# gate=1 black < reference rate with one-sided Fisher p < 0.05.
# gate=1 black = 0 but p >= 0.05 -> INCONCLUSIVE (not enough reference blacks). Any gate=1 black at a rate >= the
# reference rate -> FAIL.
O=${1:-~/orangepi5/work/_out/k15/dp-silent-black/b2}
exec python3 -I - "$O" <<'PYEOF'
import glob, math, os, re, sys
O = sys.argv[1]
REF_BLACK, REF_N = 2, 360
BLOCKS = [f"D{i}" for i in range(1, 8)]
fail = 0
def out(st, name, msg):
    global fail
    if st == "FAIL":
        fail += 1
    print(f"{st} {name}: {msg}")

WARN = re.compile(r"WARNING|BUG:|Oops|Call trace")
ERR = re.compile(r"WARNING|BUG:|Oops|Call trace|failed to enable link|link training failed|clock recovery failed|"
                 r"channel equalization failed|Retrain link failed|giving up|POST_BUF_EMPTY|failed to enable video")
rows = []
nwarn = 0
for b in BLOCKS:
    r = f"{O}/run-{b}"
    hl = f"{r}/host.log"
    if not os.path.exists(hl):
        out("FAIL", f"run-{b}", "missing (block not run)")
        continue
    h = open(hl, errors="replace").read()
    un = re.findall(r"uname -v: (.*)", h)
    if not un or not re.match(r"#[0-9]+ SMP ", un[-1]) or "lock released" not in h:
        out("FAIL", f"stock-restored-{b}", f"last uname -v: {un[-1] if un else 'none'}; lock released: {'lock released' in h}")
    else:
        out("PASS", f"stock-restored-{b}", un[-1])
    if re.search(r"STALL|TIMEOUT|FAILED", h):
        out("INFO", f"host-log-{b}", "; ".join(l for l in h.splitlines() if re.search(r"STALL|TIMEOUT|FAILED", l))[:300])
    bt = f"{r}/boot-16dpb1.txt"
    b_txt = open(bt, errors="replace").read() if os.path.exists(bt) else ""
    if re.search(r"^7\.3\.0-opi5 #16dpb1 SMP", b_txt, re.M) and re.search(r"^warn=0$", b_txt, re.M) \
            and re.search(r"^usb_missing=$", b_txt, re.M):
        out("PASS", f"boot-{b}", "#16dpb1 SMP warn=0 usb_missing empty")
    else:
        out("FAIL", f"boot-{b}", f"{bt}: " + " ".join(b_txt.splitlines()[:3])[:200])
    it = f"{r}/out/iter.tsv"
    if os.path.exists(it):
        for line in open(it):
            f = line.rstrip("\n").split("\t")
            if len(f) < 8:
                continue
            d = dict(x.split("=", 1) for x in f[1:] if "=" in x and not x.startswith("dpcd"))
            d["_kmsg"] = f"{r}/out/it/{f[0]}/kmsg.txt"
            rows.append((b, f[0], d, line.rstrip("\n")))
    for lg in glob.glob(f"{r}/out/kmsg-all*.txt"):
        for l in open(lg, errors="replace"):
            if WARN.search(l):
                nwarn += 1

stats = {}
for g in ("0", "1"):
    rs = [x for x in rows if x[2].get("gate") == g]
    valid = [x for x in rs if x[2].get("DP") not in (None, "none", "CAMERR", "NOCAM")]
    black = [x for x in valid if x[2].get("DP") == "BLACK" and x[2].get("DP2") == "BLACK"]
    nongood = [x for x in valid if x[2].get("DP") != "GOOD" and x[2].get("DP2") != "GOOD"]
    hdmi_bad = [x for x in rs if x[2].get("HDMI") != "GOOD"]
    badcommit = [x for x in rs if x[2].get("commit") != "1"]
    ovf_it = [x for x in rs if x[2].get("ovfall", "0") not in ("0", "")]
    ovf_client = [x for x in rs if x[2].get("ovf", "0") not in ("0", "")]
    errtypes, nerr = set(), 0
    for x in rs:
        try:
            for l in open(x[2]["_kmsg"], errors="replace"):
                m = ERR.search(l)
                if m:
                    nerr += 1
                    errtypes.add(m.group(0))
        except OSError:
            pass
    stats[g] = dict(n=len(rs), valid=len(valid), black=black, nongood=nongood, hdmi_bad=len(hdmi_bad),
                    badcommit=len(badcommit), ovf_it=ovf_it, ovf_client=ovf_client, errtypes=errtypes, nerr=nerr)
    name = "gate0(old order)" if g == "0" else "gate1(fix)"
    out("PASS" if len(valid) >= 600 else "FAIL", f"valid-verdicts-{name}", f"{len(valid)} of {len(rs)} rows (need >= 600)")
    out("INFO", f"black-{name}", f"{len(black)} of {len(valid)} valid; persistent non-GOOD {len(nongood)}; "
        f"HDMI non-GOOD {len(hdmi_bad)}; failed commits {len(badcommit)}")
    out("INFO", f"fifo-overflow-{name}", f"iterations with an overflow {len(ovf_it)} (in the client's modeset {len(ovf_client)})")
    out("INFO", f"log-{name}", f"error lines {nerr}, types {sorted(errtypes)}")
    for x in nongood[:20]:
        out("INFO", f"nongood-{name}", f"{x[0]} " + x[3][:400])
    both = [x for x in black if x in ovf_client]
    out("INFO", f"black-with-overflow-{name}", f"{len(both)} of {len(black)} black iterations had an overflow in the client's modeset")

out("PASS" if len(rows) >= 1300 else "FAIL", "iterations", f"{len(rows)} rows (need >= 1300)")
out("PASS" if nwarn == 0 else "FAIL", "kernel-warnings", f"{nwarn} WARNING/BUG/Oops/Call trace lines in kmsg-all*.txt (need 0)")
S0, S1 = stats["0"], stats["1"]
newtypes = sorted(S1["errtypes"] - S0["errtypes"])
out("PASS" if not newtypes else "FAIL", "no-new-errors", f"gate1-only error types: {newtypes or 'none'} (gate0 {sorted(S0['errtypes'])})")
out("PASS" if not S1["ovf_it"] else "FAIL", "fifo-overflow-gate1", f"{len(S1['ovf_it'])} gate=1 iterations with a video FIFO overflow (need 0)")
out("PASS" if S1["badcommit"] <= S0["badcommit"] else "FAIL", "commits", f"failed commits gate1 {S1['badcommit']} vs gate0 {S0['badcommit']}")

def fisher_less(a, n1, c, n2):
    # one-sided P(X <= c), X = gate1 blacks, hypergeometric with the margins of the 2x2 table
    tot, k = n1 + n2, a + c
    den = math.comb(tot, k)
    return sum(math.comb(n2, i) * math.comb(n1, k - i) for i in range(0, c + 1) if 0 <= k - i <= n1) / den
inconclusive = False
rb, rn = len(S0["black"]) + REF_BLACK, S0["valid"] + REF_N
fb, fn = len(S1["black"]), S1["valid"]
if fn:
    p = fisher_less(rb, rn, fb, fn)
    msg = (f"gate1 {fb}/{fn}, reference {rb}/{rn} (gate0 {len(S0['black'])}/{S0['valid']} + dp-black-1 "
           f"{REF_BLACK}/{REF_N}), one-sided Fisher p={p:.4f}")
    if fb / fn < rb / rn and p < 0.05:
        out("PASS", "black-rate", msg + " (need gate1 rate < reference, p < 0.05)")
    elif fb == 0 or fb / fn < rb / rn:
        out("INFO", "black-rate", msg + " (lower but p >= 0.05: INCONCLUSIVE)")
        inconclusive = True
    else:
        out("FAIL", "black-rate", msg + " (gate1 rate >= reference)")
else:
    out("FAIL", "black-rate", "no valid gate1 verdicts")
if fail:
    print("OVERALL FAIL")
elif inconclusive:
    print("OVERALL INCONCLUSIVE")
else:
    print("OVERALL PASS")
PYEOF
