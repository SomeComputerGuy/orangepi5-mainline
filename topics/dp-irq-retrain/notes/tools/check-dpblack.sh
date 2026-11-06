#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Mechanical checks for JOB dp-black-1. Prints one line per check (PASS/FAIL/INFO) and a last line
# "OVERALL PASS|FAIL|INCONCLUSIVE".
#   check-dpblack.sh [workdir]     default ~/orangepi5/work/_out/k15/dp-silent-black
# Baseline blocks run-B1..B3 (stock 15), fix blocks run-F1..F3 (15dpirq1), 60 iterations each.
# black = both camera verdicts of an iteration BLACK on DP-1 (DP=BLACK and DP2=BLACK in iter.tsv).
# PASS = all runs restored + lock released, boot checks clean, >= 170 iterations per kernel with >= 150 valid
# camera verdicts, baseline black > 0, fix black < baseline black with one-sided Fisher p < 0.05, no error type
# in the fix kernel's log that the baseline log does not have, and no more failed commits than the baseline.
# Baseline black = 0 -> INCONCLUSIVE (the bench did not reproduce the bug).
O=${1:-~/orangepi5/work/_out/k15/dp-silent-black}
exec python3 -I - "$O" <<'EOF'
import glob, math, os, re, sys
O = sys.argv[1]
fail = 0
def out(st, name, msg):
    global fail
    if st == "FAIL":
        fail += 1
    print(f"{st} {name}: {msg}")

KER = {"B": ("15", "#15 SMP"), "F": ("15dpirq1", "#15dpirq1 SMP")}
ERR = re.compile(r"WARNING|BUG:|Oops|Call trace|failed to enable link|link training failed|clock recovery failed|"
                 r"channel equalization failed|Retrain link failed|giving up|POST_BUF_EMPTY|failed to enable video")
stats = {}
for k in "BF":
    rows, errtypes, nerr, cnt = [], set(), 0, {}
    for b in (1, 2, 3):
        r = f"{O}/run-{k}{b}"
        hl = f"{r}/host.log"
        if not os.path.exists(hl):
            out("FAIL", f"run-{k}{b}", "missing (block not run)")
            continue
        h = open(hl, errors="replace").read()
        un = re.findall(r"uname -v: (.*)", h)
        if not un or not re.match(r"#15 SMP .*Wed Nov +4 20:25:22", un[-1]) or "lock released" not in h:
            out("FAIL", f"stock-restored-{k}{b}", f"last uname -v: {un[-1] if un else 'none'}; lock released: {'lock released' in h}")
        else:
            out("PASS", f"stock-restored-{k}{b}", un[-1])
        if re.search(r"STALL|TIMEOUT|FAILED", h):
            out("INFO", f"host-log-{k}{b}", "; ".join(l for l in h.splitlines() if re.search(r"STALL|TIMEOUT|FAILED", l))[:300])
        bt = f"{r}/boot-{KER[k][0]}.txt"
        b_txt = open(bt, errors="replace").read() if os.path.exists(bt) else ""
        okb = b_txt.startswith("7.3.0-opi5 " + KER[k][1]) or re.search(r"^7\.3\.0-opi5 " + re.escape(KER[k][1]), b_txt, re.M)
        if okb and re.search(r"^warn=0$", b_txt, re.M) and re.search(r"^usb_missing=$", b_txt, re.M):
            out("PASS", f"boot-{k}{b}", f"{KER[k][1]} warn=0 usb_missing empty")
        else:
            out("FAIL", f"boot-{k}{b}", f"{bt}: " + " ".join(b_txt.splitlines()[:3])[:200])
        it = f"{r}/out/iter.tsv"
        if os.path.exists(it):
            for line in open(it):
                f = line.rstrip("\n").split("\t")
                if len(f) < 6:
                    continue
                d = dict(x.split("=", 1) for x in f[1:] if "=" in x and not x.startswith("dpcd"))
                rows.append((f"{k}{b}", f[0], d, line.rstrip("\n")))
        for lg in glob.glob(f"{r}/out/kmsg-all*.txt"):
            for l in open(lg, errors="replace"):
                m = ERR.search(l)
                if m:
                    nerr += 1
                    errtypes.add(m.group(0))
                for key in ("link lost, resetting the pipeline", "giving up", "Retraining link", "Get hpd irq - short",
                            "OOB HPD event", "new mode:", "link status:"):
                    if key in l:
                        cnt[key] = cnt.get(key, 0) + 1
    valid = [x for x in rows if x[2].get("DP") not in (None, "none", "CAMERR", "NOCAM")]
    black = [x for x in valid if x[2].get("DP") == "BLACK" and x[2].get("DP2") == "BLACK"]
    nongood = [x for x in valid if x[2].get("DP") != "GOOD" and x[2].get("DP2") not in ("GOOD",)]
    badcommit = [x for x in rows if x[2].get("commit") != "1"]
    stats[k] = dict(n=len(rows), valid=len(valid), black=len(black), nongood=len(nongood), errtypes=errtypes,
                    nerr=nerr, cnt=cnt, badcommit=len(badcommit), blackrows=black, nongoodrows=nongood)
    name = "baseline(15)" if k == "B" else "fix(15dpirq1)"
    out("PASS" if len(rows) >= 170 else "FAIL", f"iterations-{name}", f"{len(rows)} rows (need >= 170)")
    out("PASS" if len(valid) >= 150 else "FAIL", f"valid-verdicts-{name}", f"{len(valid)} (need >= 150)")
    out("INFO", f"black-{name}", f"{len(black)} of {len(valid)} valid; persistent non-GOOD {len(nongood)}; failed commits {len(badcommit)}")
    out("INFO", f"log-{name}", f"error lines {nerr}, types {sorted(errtypes)}; " + ", ".join(f"'{a}' {b}" for a, b in sorted(cnt.items())))
    for x in nongood[:20]:
        out("INFO", f"nongood-{name}", f"{x[0]} " + x[3][:400])

B, F = stats["B"], stats["F"]
def fisher_less(a, n1, c, n2):
    # one-sided P(X <= c) for X = fix blacks, hypergeometric with the margins of the 2x2 table
    tot, k = n1 + n2, a + c
    den = math.comb(tot, k)
    return sum(math.comb(n2, i) * math.comb(n1, k - i) for i in range(0, c + 1) if 0 <= k - i <= n1) / den
newtypes = sorted(F["errtypes"] - B["errtypes"])
out("PASS" if not newtypes else "FAIL", "no-new-errors", f"fix-only error types: {newtypes or 'none'} (baseline {sorted(B['errtypes'])})")
out("PASS" if F["badcommit"] <= B["badcommit"] else "FAIL", "commits", f"failed commits fix {F['badcommit']} vs baseline {B['badcommit']}")
inconclusive = False
if B["valid"] and F["valid"]:
    p = fisher_less(B["black"], B["valid"], F["black"], F["valid"])
    msg = f"baseline {B['black']}/{B['valid']}, fix {F['black']}/{F['valid']}, one-sided Fisher p={p:.4f}"
    if B["black"] == 0:
        out("INFO", "black-rate", msg + " (baseline reproduced no black: INCONCLUSIVE)")
        inconclusive = True
    else:
        out("PASS" if F["black"] < B["black"] and p < 0.05 else "FAIL", "black-rate", msg + " (need fix < baseline, p < 0.05)")
else:
    out("FAIL", "black-rate", "no valid verdicts")
if fail:
    print("OVERALL FAIL")
elif inconclusive:
    print("OVERALL INCONCLUSIVE")
else:
    print("OVERALL PASS")
EOF
