#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0
"""Replay the three VOP2 POST_BUF_EMPTY cases of the HDMI display matrix (run 1) and judge them.

  vop2uf.py <outdir>          (root; no compositor may hold the display, see vop2uf-test.sh)

Cases (HDMI-A-1 = VP0, the camera looks at the HDMI screen):
  (i)   3840x2160@120 (1188 MHz) Cluster0 XR24 + Esmart0 (plane 59) XR24 linear, with/without DP-1 on Cluster1
  (ii)  3840x2160@60  RG16 AFBC 16x16|SPARSE|YTR (0x...51) on Cluster planes 35/47/53, and the non-YTR control
  (iii) 3840x2160@120 YCbCr 4:2:0 8 bpc, XR24 linear / AFBC on Cluster0, and 4K60 4:2:0 control
Every case: atomic commit with kmsctl.py (KMSCTL_PROBE=1), settle, snapshot clocks + link state, camera
picture -> camcheck verdict, hold, count POST_BUF_EMPTY in the kernel log. One line per case goes to
<outdir>/summary.txt; details per case in <outdir>/case/<name>/.
Expectations are those of the patched kernel (v2 patches 0001-0003); the same script on the old kernel is
the baseline (its FAILs are then the bugs).
"""
import json, os, re, select, subprocess, sys, time

D = os.path.dirname(os.path.abspath(__file__))
LIB = f"{D}/lib"
sys.path.insert(0, LIB)
import camcheck  # noqa: E402

OUT = sys.argv[1] if len(sys.argv) > 1 else "/var/tmp/vop2uf"
HOLD = float(os.environ.get("HOLD", "10"))
ENV = dict(os.environ, KMSCTL_PROBE="1")
KMS = [sys.executable, "-I", f"{LIB}/kmsctl.py"]
DBG = "/sys/kernel/debug"
HDMI, DP = os.environ.get("HDMI_CONN", "HDMI-A-1"), os.environ.get("DP_CONN", "DP-1")
P_C0, P_C1, P_C2, P_C3, P_E0 = 35, 41, 47, 53, 59      # plane ids of the 7.3 stack (checked below)
YTR_MOD, NOYTR_MOD = 0x0800000000000051, 0x0800000000000041
os.makedirs(f"{OUT}/case", exist_ok=True)
SUMMARY = open(f"{OUT}/summary.txt", "a", buffering=1)


def log(s):
    print(s, flush=True)
    SUMMARY.write(s + "\n")


def rd(p):
    try:
        return open(p).read()
    except OSError:
        return ""


class Kmsg:
    def __init__(self):
        self.fd = os.open("/dev/kmsg", os.O_RDONLY | os.O_NONBLOCK)
        os.lseek(self.fd, 0, os.SEEK_END)

    def drain(self):
        out = []
        while True:
            try:
                rec = os.read(self.fd, 8192).decode(errors="replace")
            except BlockingIOError:
                return out
            except OSError:             # EPIPE: overwritten records, keep reading
                continue
            hdr, _, msg = rec.partition(";")
            out.append(msg.split("\n")[0])


def vop_irqs():
    n = 0
    for line in rd("/proc/interrupts").splitlines():
        if "vop" in line:
            n += sum(int(x) for x in line.split()[1:] if x.isdigit())
    return n


def clk(name):
    return rd(f"{DBG}/clk/{name}/clk_rate").strip() or "?"


def dri_dir():
    for i in range(4):
        if os.path.exists(f"{DBG}/dri/{i}/state") and "rockchip" in rd(f"{DBG}/dri/{i}/name"):
            return f"{DBG}/dri/{i}"
    return f"{DBG}/dri/0"


def link_info(state):
    """the HDMI connector block of the atomic state: FRL/TMDS, bpc, format"""
    blk, keep = [], False
    for line in state.splitlines():
        if line.startswith("connector["):
            keep = HDMI in line
        if keep:
            blk.append(line.strip())
    want = [x for x in blk if re.search(r"frl|tmds|bpc|format|crtc=", x, re.I)]
    return "; ".join(want)[:300]


def timing(m):
    return f"{m['clock']}/{m['hdisplay']}:{m['hsync_start']}:{m['hsync_end']}:{m['htotal']}/" \
           f"{m['vdisplay']}:{m['vsync_start']}:{m['vsync_end']}:{m['vtotal']}/{m['flags']}"


def kms_list():
    r = subprocess.run(KMS + ["list"], capture_output=True, text=True, env=ENV, timeout=60)
    return json.loads(r.stdout)


class Run:
    def __init__(self):
        self.kmsg = Kmsg()
        self.info = kms_list()
        json.dump(self.info, open(f"{OUT}/kms-list.json", "w"))
        self.conns = {c["name"]: c for c in self.info["connectors"]}
        self.hdmi = self.conns[HDMI]
        self.dp = self.conns.get(DP) if self.conns.get(DP, {}).get("connected") else None
        self.dri = dri_dir()
        self.cal = None
        self.code = 1
        self.results = []
        try:
            self.cam = camcheck.find()
        except Exception:                       # noqa: BLE001
            self.cam = None
        pl = {p["id"]: p for p in self.info["planes"]}
        hc = self.hdmi["possible_crtcs"][0]
        problems = []
        if pl.get(P_C0, {}).get("type") != "Primary" or hc not in pl.get(P_C0, {}).get("possible_crtcs", []):
            problems.append(f"plane {P_C0} is not the HDMI primary")
        if pl.get(P_E0, {}).get("formats", {}).get("XR24") != ["0x0"]:
            problems.append(f"plane {P_E0} is not Esmart0 (linear-only XR24)")
        for p in (P_C2, P_C3):
            if "RG16" not in pl.get(p, {}).get("formats", {}):
                problems.append(f"plane {p} has no RG16")
        if problems:
            log("WARNING plane ids differ from the 7.3 stack: " + "; ".join(problems))
        self.cf420 = next((k for k in self.hdmi["props"].get("color format", {}).get("enums", {})
                           if "420" in re.sub(r"\D", "", k)), None)

    def mode(self, conn, w, h, clock=None, hz=None):
        for m in conn["modes"]:
            if m["hdisplay"] == w and m["vdisplay"] == h and (clock is None or m["clock"] == clock) and \
                    (hz is None or m["vrefresh"] == hz) and not m["flags"] & 16:
                return m
        return None

    def dp_head(self):
        if not self.dp:
            return None
        m = self.mode(self.dp, 3840, 2160, hz=30) or next(
            (x for x in self.dp["modes"] if x["type"] & 8), self.dp["modes"][0])
        return f"conn={DP},timing={timing(m)},plane={P_C1},fmt=XR24,mod=linear,pattern=bars,code=4095"

    def head(self, m, plane, fmt="XR24", mod="linear", pattern="bars", props=None):
        s = f"conn={HDMI},timing={timing(m)},plane={plane},fmt={fmt},mod={mod},pattern={pattern},code={self.code}"
        props = {"max bpc": "8", **(props or {})}
        if "AUTO" in self.hdmi["props"].get("color format", {}).get("enums", {}):
            props.setdefault("color format", "AUTO")
        for k, v in props.items():
            if k in self.hdmi["props"]:
                s += f",prop:{k}={v}"
        return s

    def case(self, name, heads, planes=(), expect="clean", test_only=False, mwh=(3840, 2160), note=""):
        """expect: clean (commit ok, no POST_BUF_EMPTY, picture GOOD), reject (commit refused), info"""
        d = f"{OUT}/case/{name}"
        os.makedirs(d, exist_ok=True)
        code = self.code
        self.code += 1
        args = ["show"]
        for h in heads:
            args += ["--head", h]
        for p in planes:
            args += ["--plane", p]
        args += ["--test-only"] if test_only else ["--hold", str(HOLD)]
        json.dump({"cmd": KMS + args, "note": note}, open(f"{d}/cmd.json", "w"), indent=1)
        self.kmsg.drain()
        irq0, t0 = vop_irqs(), time.time()
        p = subprocess.Popen(KMS + args, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                             text=True, env=ENV)
        r, _, _ = select.select([p.stdout], [], [], 90)
        line = p.stdout.readline() if r else ""
        try:
            res = json.loads(line)
        except ValueError:
            res = {"ok": False, "err": (line or "no output").strip()[:200]}
        cam, snap = "-", {}
        if res.get("ok") and not test_only:
            time.sleep(3)
            st = rd(f"{self.dri}/state")
            open(f"{d}/state.txt", "w").write(st)
            open(f"{d}/vop2-summary.txt", "w").write(rd(f"{self.dri}/vop2/summary"))
            snap = {"aclk_vop": clk("aclk_vop"), "dclk_vop0": clk("dclk_vop0"), "dclk_vop2": clk("dclk_vop2"),
                    "link": link_info(st)}
            cam = self.picture(d, code, mwh)
        try:
            p.communicate(timeout=HOLD + 30)
        except subprocess.TimeoutExpired:
            p.kill()
            p.communicate()
        time.sleep(0.5)
        msgs = self.kmsg.drain()
        open(f"{d}/kmsg.txt", "w").write("\n".join(msgs) + "\n")
        pbe = sum("POST_BUF_EMPTY" in m for m in msgs)
        supp = sum(int(x) for x in re.findall(r"(\d+) callbacks suppressed", "\n".join(msgs)))
        bad = [m for m in msgs if re.search(r"POST_BUF_EMPTY|BUS_ERROR|iommu|timeout|WARNING|Oops", m)]
        irqs = vop_irqs() - irq0
        ok = bool(res.get("ok"))
        if expect == "reject":
            verdict = "PASS" if not ok else "FAIL"
        elif expect == "clean":
            good_pic = cam.startswith("GOOD") or cam in ("-", "no-cam") or not self.cal_trusted()
            verdict = "PASS" if ok and pbe == 0 and supp == 0 and good_pic else "FAIL"
        else:
            verdict = "INFO"
        mods = ",".join(f"{h.get('plane')}:{h.get('fmt')}/{h.get('mod')}" for h in res.get("heads", []))
        row = {"case": name, "expect": expect, "verdict": verdict, "commit": "ok" if ok else res.get("err", ""),
               "pbe": pbe, "suppressed": supp, "vop_irqs": irqs, "secs": round(time.time() - t0, 1), "cam": cam,
               "planes": mods, **snap, "first_bad": bad[0][:120] if bad else "", "note": note}
        json.dump(row, open(f"{d}/result.json", "w"), indent=1)
        self.results.append(row)
        log(f"{verdict:5} {name:24} expect={expect:6} commit={row['commit'][:60]!s:12} pbe={pbe} supp={supp} "
            f"irqs={irqs} cam={cam} aclk={snap.get('aclk_vop', '-')} dclk0={snap.get('dclk_vop0', '-')} "
            f"planes={mods} link=[{snap.get('link', '')[:140]}]")
        return row

    def cal_trusted(self):
        return bool(self.cal) and self.cal.get("trusted", True)

    def picture(self, d, code, mwh):
        if not self.cam or not self.cal:
            return "no-cam"
        try:
            img = camcheck.load(camcheck.capture(f"{d}/cam", self.cam))
            r = camcheck.classify(self.cal, img, "bars", code, mwh)
            if not r["verdict"].startswith("GOOD"):          # one retry: TV resync after a mode/format change
                time.sleep(4)
                r = camcheck.classify(self.cal, camcheck.load(camcheck.capture(f"{d}/cam2", self.cam)),
                                      "bars", code, mwh)
            return camcheck.cam_summary(r)
        except Exception as e:                  # noqa: BLE001
            return f"cam-error:{e!r}"[:80]

    def calibrate(self, m):
        if not self.cam:
            log("camera: none found (CAM_NAME=%s) - picture verdicts skipped" % camcheck.CAM_NAME)
            return
        shots = {}
        for pat in ("white", "black"):
            d = f"{OUT}/case/calib-{pat}"
            os.makedirs(d, exist_ok=True)
            p = subprocess.Popen(KMS + ["show", "--head", self.head(m, P_C0, mod="auto", pattern=pat), "--hold", "8"],
                                 stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
                                 env=ENV)
            p.stdout.readline()
            time.sleep(4)
            shots[pat] = camcheck.capture(f"{d}/cam", self.cam)
            p.communicate(timeout=30)
        try:
            self.cal = camcheck.calib(shots["white"], shots["black"])
            json.dump(self.cal, open(f"{OUT}/calib.json", "w"))
            log(f"camera: {self.cam} calibrated")
        except Exception as e:                  # noqa: BLE001
            log(f"camera: calibration failed ({e!r}) - picture verdicts skipped")
            self.cal = None


def main():
    if os.geteuid():
        sys.exit("run as root")
    R = Run()
    m60 = R.mode(R.hdmi, 3840, 2160, clock=594000)
    m120 = R.mode(R.hdmi, 3840, 2160, clock=1188000)
    log(f"# {time.strftime('%F %T')} {os.uname().release} {rd('/proc/version').split('(')[0].strip()} "
        f"rockchipdrm srcversion={rd('/sys/module/rockchipdrm/srcversion').strip()} "
        f"4K60={'yes' if m60 else 'NO'} 4K120={'yes' if m120 else 'NO'} DP={'yes' if R.dp else 'no'} "
        f"420={R.cf420!r}")
    if not m60:
        log("ABORT: HDMI sink has no 3840x2160@60 (594 MHz) mode")
        return 2
    R.calibrate(m60)

    R.case("ctl-4k60-rgb", [R.head(m60, P_C0, mod="auto")])
    if m120:
        R.case("ctl-4k120-rgb", [R.head(m120, P_C0)], note="single full-screen layer at 1188 MHz")

    # (i) two full-screen linear XR24 layers at 4K120, with and without the DP console layer
    if m120:
        ov = [f"conn={HDMI},plane={P_E0},fmt=XR24,mod=linear,pattern=bars,code={R.code}"]
        R.case("i-c0+e0", [R.head(m120, P_C0)], ov, note="HDMI only: C0 and E0 on different AXI ports")
        if R.dp:
            ov = [f"conn={HDMI},plane={P_E0},fmt=XR24,mod=linear,pattern=bars,code={R.code}"]
            R.case("i-c0+e0+dp-test", [R.head(m120, P_C0), R.dp_head()], ov, expect="reject", test_only=True,
                   note="TEST_ONLY of the over-budget state")
            ov = [f"conn={HDMI},plane={P_E0},fmt=XR24,mod=linear,pattern=bars,code={R.code}"]
            R.case("i-c0+e0+dp", [R.head(m120, P_C0), R.dp_head()], ov, expect="reject",
                   note="the matrix case: modetest primary + plane 59 with DP lit; old kernel: POST_BUF_EMPTY")
            R.case("i-e0+dp", [R.head(m120, P_E0), R.dp_head()], note="Esmart0 alone at 4K120 + DP: fits")
        else:
            log("SKIP  i-*+dp: DP-1 not connected (the over-budget case needs the DP layer)")
    else:
        log("SKIP  (i): no 3840x2160@120 (1188 MHz) mode on HDMI")

    # (ii) RGB565 AFBC on the Cluster windows, YTR vs no YTR, at 4K60
    for p in (P_C0, P_C2, P_C3):
        R.case(f"ii-rg16-ytr-p{p}", [R.head(m60, p, fmt="RG16", mod=hex(YTR_MOD))], expect="reject",
               note="old kernel: black + POST_BUF_EMPTY")
        R.case(f"ii-rg16-noytr-p{p}", [R.head(m60, p, fmt="RG16", mod=hex(NOYTR_MOD))])
    R.case("ii-rg16-auto-p35", [R.head(m60, P_C0, fmt="RG16", mod="auto")], note="modifier a client picks")
    R.case("ii-xr24-ytr-p35", [R.head(m60, P_C0, fmt="XR24", mod=hex(YTR_MOD))], note="YTR control, 32 bpp")

    # (iii) YCbCr 4:2:0 output
    if R.cf420:
        cf = {"color format": R.cf420}
        R.case("iii-4k60-420", [R.head(m60, P_C0, props=cf)], note="control (TMDS 297 MHz)")
        if m120:
            R.case("iii-4k120-420-lin", [R.head(m120, P_C0, props=cf)],
                   note="TMDS 594 MHz expected; ACLK must read 750000000")
            R.case("iii-4k120-420-afbc", [R.head(m120, P_C0, mod=hex(YTR_MOD), props=cf)])
    else:
        log("SKIP  (iii): connector has no YCbCr 4:2:0 'color format' value")

    # leave a sane picture behind for fbcon/gdm (kmsctl exits; fbcon restores)
    n = {v: sum(r["verdict"] == v for r in R.results) for v in ("PASS", "FAIL", "INFO")}
    log(f"# done {time.strftime('%F %T')}: PASS {n['PASS']} FAIL {n['FAIL']} INFO {n['INFO']}")
    return 1 if n["FAIL"] else 0


if __name__ == "__main__":
    sys.exit(main())
