#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0
"""fmtck.py <outdir> <listfile>    (board, root, gdm stopped)

Per case: OFF, TEST_ONLY, real commit (from all-off) through one long-lived `kmsctl.py batch` child, then read back
what the kernel actually sends (read-only debugfs: dri state connector block, HDMI infoframes/avi, vop2 summary,
scdc_status, dclk rates) and judge the picture by camera.
<listfile>: TSV id, spec (kmsctl head spec WITHOUT pattern), kind, code
  kind: cam    bars pattern with <code>, shared camcheck judge (GOOD, or the same non-GOOD on 3 captures 20 s apart)
        levels levels pattern, LEVELS_N captures measured by levels.py (no verdict here)
        osd    like cam, then CEC <User Control Pressed> display-information and two full-res captures (TV info OSD)
        t      TEST_ONLY only
Output: <outdir>/fmt.tsv (resumable) + <outdir>/c/<id>/ readbacks and frames."""
import json, os, re, select, subprocess, sys, time

D, LST = sys.argv[1], sys.argv[2]
HERE = os.path.dirname(os.path.abspath(__file__))
DBG = "/sys/kernel/debug"
SETTLE = float(os.environ.get("SETTLE", "7"))
SETTLE_FRL = float(os.environ.get("SETTLE_FRL", "10"))
LEVELS_N = int(os.environ.get("LEVELS_N", "3"))
CONN = os.environ.get("CONN", "HDMI-A-1")   # HDMI-A-1 or DP-1
IS_HDMI = CONN.startswith("HDMI")
CEC = ["cec-ctl", "-d", os.environ.get("CEC_DEV", "/dev/cec0")]
os.makedirs(f"{D}/c", exist_ok=True)
COLS = ["seq", "id", "kind", "t_ok", "t_errno", "c_ok", "c_errno", "out_fmt", "out_bpc", "limited", "bcast", "tmds",
        "avi", "busfmt", "frl", "dclk", "cam", "dmesg"]
out = f"{D}/fmt.tsv"
done = set()
if os.path.exists(out):
    done = {l.split("\t")[1] for l in open(out).read().splitlines()[1:] if l.strip()}
else:
    open(out, "w").write("\t".join(COLS) + "\n")
cases = [l.rstrip("\n").split("\t") for l in open(LST) if l.strip() and not l.startswith("#")]
kp = None


def start():
    global kp
    if kp:
        try:
            kp.stdin.write("Q\n")
            kp.stdin.close()
        except (BrokenPipeError, OSError):
            pass
        kp.wait(timeout=30)
    kp = subprocess.Popen([sys.executable, "-I", f"{HERE}/kmsctl.py", "batch"], env=dict(os.environ, KMSCTL_PROBE="1"),
                          stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, bufsize=1)


def send(*f):
    kp.stdin.write("\t".join(f) + "\n")
    kp.stdin.flush()
    r, _, _ = select.select([kp.stdout], [], [], 60)
    if not r:
        return {"ok": False, "errno": -2, "err": "kmsctl reply timeout"}
    return json.loads(kp.stdout.readline())


def rd(p, binary=False):
    try:
        with open(p, "rb" if binary else "r") as f:
            return f.read() if binary else f.read().strip()
    except OSError:
        return b"" if binary else ""


def dri():
    for n in sorted(os.listdir(f"{DBG}/dri")):
        if os.path.isdir(f"{DBG}/dri/{n}/HDMI-A-1"):
            return f"{DBG}/dri/{n}"
    return f"{DBG}/dri/0"


DRI = dri()


def conn_block(state, conn):
    m = re.search(rf"connector\[\d+\]: {re.escape(conn)}\n((?:\t.*\n)*)", state)
    return dict(re.findall(r"\t(\w+)=(.*)", m[1])) if m else {}


def dmesg_n():
    return len(subprocess.run(["dmesg"], capture_output=True, text=True).stdout.splitlines())


BAD = re.compile(r"WARNING|BUG:|Oops|Failed|failed|timed out|error|-22", re.I)


def dmesg_new(n0):
    L = subprocess.run(["dmesg"], capture_output=True, text=True).stdout.splitlines()[n0:]
    return " | ".join(l[l.find("]") + 1:].strip() for l in L if BAD.search(l))[:300]


sys.path.insert(0, HERE)
import camcheck as TMC  # noqa: E402  testmatrix camcheck: find/capture
import camcheck_shared as CC  # noqa: E402  work/_out/tools/camcheck.py: lighting-invariant classifier
CAL_DIR = os.environ.get("CAL_DIR", "/var/tmp/tm/cam2")
CAM = TMC.find()


def cap(prefix):
    return TMC.capture(prefix, CAM)


def judge(d, code):
    cal = json.load(open(f"{CAL_DIR}/calib-{CONN}.json"))
    hist, run, last_amb = [], [], None
    for k in range(8):
        if k:
            time.sleep(CC.SPACING)
        try:
            cap(f"{d}/cam{k}")
            r = CC.classify(cal, CC.load(f"{d}/cam{k}.jpg"), code)
        except Exception as e:  # noqa: BLE001
            hist.append("CAMERR")
            run = []
            continue
        v = r["verdict"]
        hist.append(v)
        if v == "GOOD":
            return "GOOD" + (f"(after {k}: {'/'.join(hist)})" if k else "")
        amb = r.get("ambient")
        if amb is not None and last_amb and abs(amb - last_amb) > CC.LIGHT_JUMP * max(last_amb, 10):
            run = []
        last_amb = amb
        run = run + [v] if run and run[-1] == v else [v]
        if len(run) >= CC.CONFIRM:
            return "FAIL:" + "/".join(hist)
    return "UNSURE:" + "/".join(hist)


def osd(d):
    """TV signal-info banner: RC passthrough display-information, two captures (banner timing differs per TV)"""
    subprocess.run(CEC + ["-t0", "--user-control-pressed", "ui-cmd=display-information"], capture_output=True)
    subprocess.run(CEC + ["-t0", "--user-control-released"], capture_output=True)
    for k, s in enumerate((1.5, 2.5)):
        time.sleep(s)
        try:
            cap(f"{d}/osd{k}")
        except Exception:  # noqa: BLE001
            pass
    subprocess.run(CEC + ["-t0", "--user-control-pressed", "ui-cmd=exit"], capture_output=True)
    subprocess.run(CEC + ["-t0", "--user-control-released"], capture_output=True)
    time.sleep(1.5)


start()
seq = 0
try:
    for c in cases:
        seq += 1
        cid, spec, kind, code = c[0], c[1], c[2], int(c[3]) if len(c) > 3 else 0
        if cid in done:
            continue
        d = f"{D}/c/{cid}"
        os.makedirs(d, exist_ok=True)
        if seq % 20 == 0:
            start()
        pat = "levels" if kind == "levels" else "bars"
        full = spec + f",pattern={pat},code={code}"
        send("OFF", "off")
        n0 = dmesg_n()
        t = send("T", cid, full)
        row = dict.fromkeys(COLS, "")
        row.update(seq=seq, id=cid, kind=kind, t_ok=int(t["ok"]), t_errno=t.get("errno", ""))
        if kind != "t":
            r = send("C", cid, full)
            row.update(c_ok=int(r["ok"]), c_errno=r.get("errno", ""))
            if r["ok"]:
                time.sleep(1.0)
                st = rd(f"{DRI}/state")
                cb = conn_block(st, CONN)
                row.update(out_fmt=cb.get("output_format", ""), out_bpc=cb.get("output_bpc", ""),
                           limited=cb.get("is_limited_range", ""), bcast=cb.get("broadcast_rgb", ""),
                           tmds=cb.get("tmds_char_rate", ""))
                avi = rd(f"{DRI}/{CONN}/infoframes/avi", True) if IS_HDMI else b""
                row["avi"] = avi.hex()
                summ = rd(f"{DRI}/vop2/summary")
                row["busfmt"] = ""
                vpn = "0"
                for blk in re.split(r"(?=Video Port\d)", summ):
                    if f"Connector: {CONN}" in blk:
                        m = re.search(r"bus_format\[(\w+)\].*?output_mode\[(\w+)\]", blk, re.S)
                        row["busfmt"] = f"{m[1]}/{m[2]}" if m else ""
                        vm = re.match(r"Video Port(\d)", blk)
                        vpn = vm[1] if vm else vpn
                scdc = rd(f"{DRI}/{CONN}/scdc_status") if IS_HDMI else ""
                fm = re.search(r"FRL Rate\s*:\s*(.*)", scdc)
                row["frl"] = fm[1].strip() if fm else ""
                row["dclk"] = rd(f"{DBG}/clk/dclk_vop{vpn}/clk_rate")
                with open(f"{d}/readback.txt", "w") as fh:
                    fh.write(f"== state\n{st}\n== vop2 summary\n{summ}\n== scdc\n{scdc}\n")
                    for f in (("avi", "hdmi", "hdr_drm", "spd", "audio") if IS_HDMI else ()):
                        fh.write(f"== if {f}: {rd(f'{DRI}/{CONN}/infoframes/{f}', True).hex()}\n")
                wait = SETTLE_FRL if "Gbit" in row["frl"] else SETTLE
                time.sleep(max(0, wait - 1.0))
                if kind in ("cam", "osd"):
                    row["cam"] = judge(d, code)
                    if kind == "osd":
                        osd(d)
                elif kind == "levels":
                    for k in range(LEVELS_N):
                        try:
                            cap(f"{d}/lev{k}")
                        except Exception:  # noqa: BLE001
                            pass
                        time.sleep(3)
                    row["cam"] = "levels"
        row["dmesg"] = dmesg_new(n0).replace("\t", " ")
        with open(out, "a") as f:
            f.write("\t".join(str(row[k]) for k in COLS) + "\n")
        print(f"{seq}/{len(cases)} {cid} T={row['t_ok']} C={row['c_ok']} {row['out_fmt']}/{row['out_bpc']} "
              f"lim={row['limited']} frl={row['frl']} cam={row['cam']}", flush=True)
finally:
    try:
        send("OFF", "off")
        kp.stdin.write("Q\n")
        kp.stdin.close()
    except (BrokenPipeError, OSError):
        pass
    kp.wait(timeout=30)
