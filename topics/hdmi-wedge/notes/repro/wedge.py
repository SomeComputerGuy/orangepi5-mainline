#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0
"""HDMI wedge replay: run a sequence of KMS heads on HDMI-A-1, camera + SCDC + atomic state after each.

  wedge.py <outdir> calib                 white/black calibration at 1080p60 -> <outdir>/calib.json
  wedge.py <outdir> run STEP [STEP ...]   STEP = name:SPEC  (SPEC = kmsctl --head spec without conn=)
Gdm must be stopped. Run as root. Copy <outdir> to the host afterwards.
"""
import json, os, subprocess, sys, time
HERE = os.environ.get("TM", "/var/tmp/testmatrix") + "/lib"
sys.path.insert(0, HERE)
import camcheck  # noqa: E402

DBG = "/sys/kernel/debug/dri/0"
CONN = os.environ.get("CONN", "HDMI-A-1")
SETTLE = float(os.environ.get("SETTLE", "7"))


def rd(p):
    try:
        return open(p).read()
    except OSError as e:
        return f"<{e}>"


def show(spec):
    cmd = [sys.executable, "-I", f"{HERE}/kmsctl.py", "show", "--head", f"conn={CONN},{spec}"]
    p = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    line = p.stdout.readline()
    try:
        res = json.loads(line)
    except ValueError:
        res = {"ok": False, "err": line + p.stderr.read()[-300:] if p.poll() is not None else line}
    return p, res


def kmsg_mark(tag):
    with open("/dev/kmsg", "w") as f:
        f.write(f"wedge: {tag}\n")


def snap(d, cam, cal, code):
    os.makedirs(d, exist_ok=True)
    open(f"{d}/scdc.txt", "w").write(rd(f"{DBG}/{CONN}/scdc_status"))
    open(f"{d}/state.txt", "w").write(rd(f"{DBG}/state"))
    open(f"{d}/vop2.txt", "w").write(rd(f"{DBG}/vop2/summary"))
    open(f"{d}/vop2regs.txt", "w").write(rd(f"{DBG}/vop2/active_regs"))
    open(f"{d}/clk.txt", "w").write("".join(l for l in rd("/sys/kernel/debug/clk/clk_summary").splitlines(True)
                                            if any(k in l for k in ("hdmi", "hdptx", "dclk", "vop", "aclk_vop", "pll"))))
    if "connector[88]" in rd(f"{DBG}/state") and "crtc=video_port" in rd(f"{DBG}/state").split("connector[88]")[1][:60]:
        r = subprocess.run([sys.executable, "-I", "/var/tmp/wedge/hdmiregs.py"], capture_output=True, text=True)
        open(f"{d}/hdmiregs.txt", "w").write(r.stdout + r.stderr)
    v = {}
    if cam and cal:
        img = camcheck.load(camcheck.capture(f"{d}/cam", cam))
        r = camcheck.classify(cal, img, "bars", code)
        if r["verdict"] != "GOOD":
            time.sleep(6)
            r = camcheck.classify(cal, camcheck.load(camcheck.capture(f"{d}/cam", cam)), "bars", code)
        v = r
    return v


def main(a):
    out = a[0]
    os.makedirs(out, exist_ok=True)
    cam = camcheck.find()
    if a[1] == "calib":
        for pat in ("white", "black"):
            p, r = show(f"timing=148500/1920:2008:2052:2200/1080:1084:1089:1125/1048581,pattern={pat}")
            time.sleep(SETTLE)
            camcheck.capture(f"{out}/calib-{pat}", cam)
            p.stdin.close(); p.wait()
        c = camcheck.calib(f"{out}/calib-white.rgb", f"{out}/calib-black.rgb")
        json.dump(c, open(f"{out}/calib.json", "w"))
        print(json.dumps({k: c[k] for k in c if k in ("box", "trusted")}))
        return
    cal = json.load(open(f"{out}/calib.json")) if os.path.exists(f"{out}/calib.json") else None
    if os.environ.get("PROBE", "1") == "1":   # refresh the connector mode cache once (kmsctl show uses the cached list)
        subprocess.run([sys.executable, "-I", f"{HERE}/kmsctl.py", "list"], stdout=subprocess.DEVNULL)
    log = open(f"{out}/steps.tsv", "a")
    n0 = len(os.listdir(out))
    for i, st in enumerate(a[2:]):
        name, spec = st.split(":", 1)
        code = 0x1000 + n0 + i
        d = f"{out}/{n0 + i:03d}-{name}"
        if os.environ.get("PROBE", "1") == "1":   # fbdev's restore probe prunes modes wider than its fb
            subprocess.run([sys.executable, "-I", f"{HERE}/kmsctl.py", "list"], stdout=subprocess.DEVNULL)
        kmsg_mark(f"step {name} {spec}")
        t = time.time()
        p, res = show(f"{spec},pattern=bars,code={code}")
        time.sleep(SETTLE)
        v = snap(d, cam, cal, code)
        p.stdin.close(); p.wait()
        if os.environ.get("POSTCAP") == "1":      # what the fbdev restore after the client exit shows
            time.sleep(SETTLE)
            snap(d + "/post", None, None, 0)
            if cam:
                camcheck.capture(f"{d}/post/cam", cam)
            v["post"] = {"verdict": "cap"}
        json.dump({"spec": spec, "res": res, "cam": v}, open(f"{d}/step.json", "w"), indent=1)
        sc = rd(f"{d}/scdc.txt").replace("\n", " | ")[:300]
        row = f"{name}\t{res.get('ok')}\t{v.get('verdict', '-')}/{v.get('post', {}).get('verdict', '')}\t{spec}\t{res.get('err', '')}\t{sc}"
        print(row, flush=True)
        log.write(row + "\n"); log.flush()


if __name__ == "__main__":
    main(sys.argv[1:])
