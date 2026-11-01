#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0
"""(hdmi-clk variant of hdmi-wedge/repro/seqrun.py: per step also snap.py = DCLK, measured pixel clock, VOP/GRF polarity)
Run a KMS sequence on HDMI-A-1 from ONE DRM master (no fbdev restore between the steps).

  seqrun.py <outdir> STEP [STEP ...]      STEP = name:SPEC (kmsctl head spec without conn=), SPEC "OFF" = all off, "OFF<ms>" = all off for <ms> without capture
After each commit: settle, then camera verdict + SCDC + atomic state + dw-hdmi-qp status registers
(hdmiregs.py) into <outdir>/<NNN-name>/, one summary line per step (also appended to <outdir>/steps.tsv).
Root, gdm stopped. Env: SETTLE (s, default 7), NOCAM=1 to skip the camera.
"""
import json, os, subprocess, sys, time
HERE = os.environ.get("TM", "/var/tmp/testmatrix") + "/lib"
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import camcheck  # noqa: E402
import kmsctl  # noqa: E402

DBG = "/sys/kernel/debug/dri/0"
SETTLE = float(os.environ.get("SETTLE", "7"))
CAL = os.environ.get("CALIB", "/var/tmp/wo/r1/calib.json")


def rd(p):
    try:
        return open(p).read()
    except OSError as e:
        return f"<{e}>"


def regs_unused():
    r = subprocess.run([sys.executable, "-I", "/var/tmp/wedge/hdmiregs.py"], capture_output=True, text=True)
    return r.stdout


def main(a):
    out = a[0]
    os.makedirs(out, exist_ok=True)
    cam = None if os.environ.get("NOCAM") == "1" else camcheck.find()
    cal = json.load(open(CAL)) if cam else None
    sh = kmsctl.Shower()
    sh.info = kmsctl.enumerate_all(sh.fd, probe=True)
    log = open(f"{out}/steps.tsv", "a")
    n0 = len(os.listdir(out))
    devnull = open(os.devnull)
    sys.stdin = devnull                     # run(hold=0) must not block on stdin
    for i, st in enumerate(a[1:]):
        name, spec = st.split(":", 1)
        code = 0x2000 + n0 + i
        d = f"{out}/{n0 + i:03d}-{name}"
        os.makedirs(d, exist_ok=True)
        with open("/dev/kmsg", "w") as f:
            f.write(f"seqrun: step {name} {spec}\n")
        if spec.startswith("DPMSOFF"):            # ACTIVE=0 on the HDMI CRTC only, routing and mode kept
            req = kmsctl.drm.drmModeAtomicAlloc()
            p = kmsctl.props(sh.fd, 83, kmsctl.OBJ_CRTC)
            kmsctl.drm.drmModeAtomicAddProperty(req, 83, p["ACTIVE"]["id"], 0)
            rc = kmsctl.drm.drmModeAtomicCommit(sh.fd, req, kmsctl.ALLOW_MODESET, None)
            time.sleep(int(spec[7:] or "1") / 1000)
            print(f"{name}\t{rc}\tdpms off {spec[7:]} ms", flush=True)
            continue
        off = spec.startswith("OFF")
        heads = [] if off else [kmsctl.parse_spec(f"conn=HDMI-A-1,{spec},pattern=bars,code={code}")]
        try:
            rc = sh.run(heads, [], False, 0)
            err = "" if rc == 0 else "commit failed"
        except (RuntimeError, StopIteration, IndexError, KeyError) as e:
            rc, err = 2, repr(e)
        if off and spec[3:]:                       # OFF<ms>: all off for <ms>, no capture
            time.sleep(int(spec[3:]) / 1000)
            print(f"{name}\t{rc}\toff {spec[3:]} ms", flush=True)
            continue
        time.sleep(SETTLE)
        sn = {} if off else json.loads(subprocess.run([sys.executable, "-I", "/var/tmp/wedge/snap.py", d],
                                                      capture_output=True, text=True).stdout or "{}")
        rg = rd(f"{d}/hdmiregs.txt") if not off else ""
        open(f"{d}/scdc.txt", "w").write(rd(f"{DBG}/HDMI-A-1/scdc_status"))
        open(f"{d}/state.txt", "w").write(rd(f"{DBG}/state"))
        vif = next((l.split()[-1] for l in rg.splitlines() if l.startswith("VIDEO_INTERFACE_STATUS0")), "?")
        verdict = "-"
        if cam:
            r = camcheck.classify(cal, camcheck.load(camcheck.capture(f"{d}/cam", cam)), "bars", code)
            verdict = r["verdict"]
        sk = " ".join(f"{k}={v}" for k, v in sn.items())
        row = f"{name}\t{rc}\t{verdict}\tVIF={vif}\t{sk}\t{spec}\t{err}"
        print(row, flush=True)
        log.write(row + "\n")
        log.flush()


if __name__ == "__main__":
    main(sys.argv[1:])
