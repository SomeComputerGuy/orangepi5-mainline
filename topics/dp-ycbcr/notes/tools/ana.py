#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0
"""host: ana.py <kms-list.json> <run dir> -> table.tsv + summary on stdout

Per case: request (mode, color format, max bpc) vs model (hmodel.expect) vs what the kernel sent (state
output_format/bpc/is_limited_range, AVI InfoFrame Y/C/EC/Q/YQ/VIC, VOP2 bus format, FRL) and camera verdict."""
import json, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import hmodel

lst = json.load(open(sys.argv[1]))
R = sys.argv[2]
hc = next(c for c in lst["connectors"] if c["name"] == "HDMI-A-1")
BCAST = "Broadcast RGB" in hc["props"]     # kernel with the limited range RGB fix
CF = {"AUTO": "AUTO", "RGB": "RGB", "444": "YUV 4:4:4", "422": "YUV 4:2:2", "420": "YUV 4:2:0"}
Y = {0: "RGB", 1: "422", 2: "444", 3: "420"}
FMT = {"RGB": "RGB", "YUV 4:4:4": "444", "YUV 4:2:2": "422", "YUV 4:2:0": "420"}
def avi(h):
    if not h or len(h) < 16:
        return None
    b = bytes.fromhex(h)
    pb = b[3:]           # pb[0] = checksum, pb[1..] = PB1..
    if b[0] != 0x82:
        return None
    pb1, pb2, pb3, pb4, pb5 = pb[1], pb[2], pb[3], pb[4], pb[5]
    return dict(y=Y.get(pb1 >> 5 & 3, "?"), c=pb2 >> 6, ec=pb3 >> 4 & 7, q=pb3 >> 2 & 3, vic=pb4, yq=pb5 >> 6,
                ver=b[1], cksum_ok=sum(b[:3] + pb[:b[2] + 1]) % 256 == 0)


QN = {0: "D", 1: "L", 2: "F", 3: "R"}
rows = []
L = open(f"{R}/fmt.tsv").read().splitlines()
hd = L[0].split("\t")
for l in L[1:]:
    r = dict(zip(hd, l.split("\t")))
    cid = r["id"]
    i, b, cf = cid[1:].split("_")[:3]
    m = hc["modes"][int(i)]
    e = hmodel.expect(m, CF[cf], int(b))
    a = avi(r.get("avi", ""))
    issues = []
    acc = r["c_ok"] == "1" if r["kind"] != "t" else r["t_ok"] == "1"
    if bool(e) != acc:
        issues.append(f"accept:{'kernel' if acc else 'model'}")
    if r["kind"] != "t" and r["t_ok"] != r["c_ok"]:
        issues.append("T!=C")
    act_fmt = FMT.get(r.get("out_fmt", ""), r.get("out_fmt", ""))
    if e and r.get("c_ok") == "1":
        if act_fmt != e["fmt"]:
            issues.append(f"fmt {act_fmt}!={e['fmt']}")
        if r["out_bpc"] != str(e["bpc"]):
            issues.append(f"bpc {r['out_bpc']}!={e['bpc']}")
        if a:
            if a["y"] != act_fmt:
                issues.append(f"AVI Y={a['y']}")
            if a["vic"] != (e["vic"] if e["vic"] not in (93, 94, 95, 98, 99, 100) else 0) and a["vic"] != e["vic"]:
                issues.append(f"AVI VIC={a['vic']} exp {e['vic']}")
            if act_fmt == "RGB":
                if QN[a["q"]] != e["q"]:
                    issues.append(f"AVI Q={QN[a['q']]} exp {e['q']}")
                if a["c"] != 0:
                    issues.append(f"AVI C={a['c']}")
            else:
                if a["yq"] != 0 and a["yq"] != 1:   # 0 = limited, 1 = full
                    issues.append(f"AVI YQ={a['yq']}")
                # C=0 (no data): the sink assumes BT.601 for SD and BT.709 for HD formats; the VOP2 R2Y is BT.709
                if a["c"] == 0 and e["c"] == 1 and "color_space[0]" in open(f"{R}/c/{cid}/readback.txt").read():
                    issues.append("SD YCbCr: AVI C=0 (sink assumes BT.601), VOP2 encodes BT.709")
                elif a["c"] not in (0, 2):
                    issues.append(f"AVI C={a['c']}")
            if not a["cksum_ok"]:
                issues.append("AVI checksum")
        elif r["kind"] != "t":
            issues.append("no AVI")
        lim = r.get("limited") == "y"
        if act_fmt == "RGB" and lim and not BCAST:
            issues.append("RGB limited signalled, VOP2 sends full range")
        if e["frl"] != ("Gbit" in r.get("frl", "")):
            issues.append(f"FRL={r.get('frl')} exp {'FRL' if e['frl'] else 'TMDS'}")
    cam = r.get("cam", "")
    if cam.startswith("FAIL") or cam.startswith("UNSURE"):
        issues.append("CAM " + cam[:40])
    rows.append(dict(id=cid, mode=f"{m['name']}@{m['vrefresh']}", clk=m["clock"], req=f"{cf}/{b}",
                     model=f"{e['fmt']}/{e['bpc']}/{'FRL' if e['frl'] else 'TMDS'}/Q{e['q']}" if e else "REFUSE",
                     actual=f"{act_fmt}/{r.get('out_bpc', '')}/{r.get('frl', '')}/lim={r.get('limited', '')}" if r.get("c_ok") == "1" else
                     ("ACCEPT(T)" if r["t_ok"] == "1" else f"REFUSE({r.get('c_errno') or r.get('t_errno')})"),
                     avi=(f"Y={a['y']} C={a['c']} EC={a['ec']} Q={QN[a['q']]} YQ={a['yq']} VIC={a['vic']}" if a else ""),
                     bus=r.get("busfmt", ""), cam=cam[:60], issues="; ".join(issues)))
with open(f"{R}/table.tsv", "w") as f:
    f.write("\t".join(rows[0].keys()) + "\n")
    for x in rows:
        f.write("\t".join(str(v) for v in x.values()) + "\n")
n = len(rows)
bad = [x for x in rows if x["issues"]]
print(f"{n} cases, {len(bad)} with issues")
from collections import Counter
cnt = Counter()
for x in bad:
    for s in x["issues"].split("; "):
        cnt[s.split(" exp")[0][:50]] += 1
for k, v in cnt.most_common():
    print(f"  {v:4d}  {k}")
