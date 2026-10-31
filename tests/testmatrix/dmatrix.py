#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0
"""Display matrix engine (driven by ../display-matrix.sh; runs as root on the board, gdm stopped).

Every case: commit (kmsctl.py atomic, or modetest for linear formats Python cannot fill), settle, then
record the atomic state, VOP2 summary, HDMI SCDC status, DP DPCD link status + sink CRC, kernel log delta
and, for the connector under the webcam, the camera verdict. Each case is checked against the link budget
from the sink EDID / DPCD and the source limits. Results: <out>/results.tsv (one row per case, appended,
resumable), <out>/summary.txt, <out>/cases.json, <out>/case/<idx>/ (raw evidence).
"""
import argparse, json, os, re, select, signal, subprocess, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import camcheck  # noqa: E402

DBG = "/sys/kernel/debug/dri/0"
SRC_TMDS_MAX = float(os.environ.get("SRC_TMDS_MAX_MHZ", "600")) * 1e6    # RK3588 HDMI 2.0 TMDS
SRC_FRL_MAX = os.environ.get("SRC_FRL_MAX", "10x4")                      # RK3588 HDMI 2.1 TX: 10G x 4 lanes
SRC_DP_MAX_GBPS = float(os.environ.get("SRC_DP_MAX_GBPS", "8.1"))        # dw-dp: HBR3
SETTLE = float(os.environ.get("SETTLE", "4"))
CAM_SETTLE = float(os.environ.get("CAM_SETTLE", "3"))
CAM_CONN = os.environ.get("CAM_CONN", "")
CAM_CALIB_MODE = os.environ.get("CAM_CALIB_MODE", "1920x1080@60")
# Known picture results per monitor: "[MONITOR_GLOB|]MODE[,bpc=N][,cf=NAME]=GOOD|BAD" entries, space separated.
# MONITOR_GLOB matches "VENDOR/PRODUCT/NAME" from the EDID, spaces as '_' (e.g. SAM/1018/LU28R55, YDC/3200/PD22320W,
# TCL/9653/Beyond_TV); no glob = any monitor. The first GOOD entry of the camera monitor is the camera control.
CAM_KNOWN = os.environ.get("CAM_KNOWN", " ".join([
    "*LU28R55|1920x1080@60=GOOD", "*LU28R55|2560x1440@60=GOOD", "*LU28R55|3840x2160@30/297000=GOOD",  # Samsung U28R55 via dock
    "*PD22320W|1920x1080@60=GOOD", "*PD22320W|2560x1440@60=GOOD", "*PD22320W|3840x2160@30/297000=BAD",  # Zerlon via dock
    "*Beyond_TV|1920x1080@60=GOOD", "*Beyond_TV|3840x2160@60/594000=GOOD"]))
LEAVE_OTHERS = False        # set by --conn: outputs outside the run are left alone
CAM_CONTROL_EVERY = int(os.environ.get("CAM_CONTROL_EVERY", "25"))
FRL_CODES = {0: (0, 0), 1: (3, 3), 2: (6, 3), 3: (6, 4), 4: (8, 4), 5: (10, 4), 6: (12, 4)}
RGB_FILL = ("XR24", "AR24", "XB24", "AB24", "XR30", "AR30", "XB30", "AB30", "RG24", "BG24", "RG16", "BG16")
YUV_FMTS = ("NV12", "NV21", "NV16", "NV61", "NV24", "NV42", "NV15", "NV20", "NV30", "YUYV", "YVYU", "UYVY",
            "VYUY", "YU08", "YU10", "Y210", "P010", "P210")
DMESG_BAD = re.compile(r"POST_BUF_EMPTY|underflow|FLT|link train|training fail|AUX|aux|timed out|timeout|"
                       r"fail|error|Oops|BUG:|WARNING:|SError|Internal error", re.I)
# per-connector attribution of kernel messages (vop2 vp0 = HDMI-A-1, vp2 = DP-1 on this board)
CONN_SCOPE = {"HDMI": re.compile(r"hdmi|hdptx|fde80000|vp0\b|video_port0", re.I),
              "DP": re.compile(r"dw-dp|dw_dp|fde50000|usbdp|\bdp\b|drm_dp|vp2\b|video_port2|aux", re.I)}
DMESG_SCOPE = re.compile(r"drm|rockchip|vop|hdmi|dw-dp|dw_dp|\bdp\b|hdptx|phy|display|fde50000|fde80000|"
                         r"Oops|BUG:|WARNING:|SError|Internal error", re.I)


def sh(*a, timeout=30):
    try:
        return subprocess.run(a, capture_output=True, text=True, timeout=timeout).stdout
    except (OSError, subprocess.TimeoutExpired):
        return ""


def rd(path):
    try:
        with open(path, errors="replace") as f:
            return f.read()
    except OSError:
        return ""


# ---------------------------------------------------------------- EDID
def edid_caps(hexstr):
    b = bytes.fromhex(hexstr)
    caps = {"max_tmds": 165e6, "max_frl": 0, "dc30": 0, "dc36": 0, "dc_y444": 0, "dc420_30": 0, "dc420_36": 0,
            "scdc": 0, "hdmi": 0, "y420_vics": [], "y420cmdb": None, "hdr_eotf": 0}
    for blk in range(1, len(b) // 128):
        e = b[blk * 128:(blk + 1) * 128]
        if e[0] != 0x02:
            continue
        dtd = e[2] or 127
        caps["y444"], caps["y422"] = e[3] >> 5 & 1, e[3] >> 4 & 1
        i = 4
        while i < dtd:
            tag, ln = e[i] >> 5, e[i] & 31
            d = e[i + 1:i + 1 + ln]
            if tag == 3 and d[:3] == b"\x03\x0c\x00":                 # HDMI 1.4 VSDB
                caps["hdmi"] = 1
                if ln >= 6:
                    caps["dc30"], caps["dc36"], caps["dc_y444"] = d[5] >> 4 & 1, d[5] >> 5 & 1, d[5] >> 3 & 1
                if ln >= 7 and d[6]:
                    caps["max_tmds"] = max(caps["max_tmds"], d[6] * 5e6)
            elif (tag == 3 and d[:3] == b"\xd8\x5d\xc4") or (tag == 7 and d[:1] == b"\x79"):  # HF-VSDB / HF-SCDB
                o = 3            # d[3] = version (after the OUI, or after ext tag + 2 reserved bytes)
                if len(d) > o + 3:
                    if d[o + 1]:
                        caps["max_tmds"] = max(caps["max_tmds"], d[o + 1] * 5e6)
                    caps["scdc"] = d[o + 2] >> 7 & 1
                    caps["dc420_30"], caps["dc420_36"] = d[o + 3] & 1, d[o + 3] >> 1 & 1
                    caps["max_frl"] = d[o + 3] >> 4                     # Max_FRL_Rate shares the byte
            elif tag == 7 and d[:1] == b"\x0e":                       # YCbCr 4:2:0 video data block (420-only)
                caps["y420_vics"] += [v & 0x7f for v in d[1:]]
            elif tag == 7 and d[:1] == b"\x0f":                       # YCbCr 4:2:0 capability map
                caps["y420cmdb"] = d[1:].hex()
            elif tag == 7 and d[:1] == b"\x06" and ln >= 2:            # HDR static metadata
                caps["hdr_eotf"] = d[1]
            i += 1 + ln
    return caps


def monitor_id(hexstr):
    """'VENDOR/PRODUCT/NAME' from the EDID base block (spaces in the name become '_')"""
    b = bytes.fromhex(hexstr or "")
    if len(b) < 128:
        return "?/?/?"
    v = b[8] << 8 | b[9]
    ven = "".join(chr(((v >> sh_) & 31) + 64) for sh_ in (10, 5, 0))
    name = ""
    for o in (54, 72, 90, 108):
        if b[o:o + 3] == b"\0\0\0" and b[o + 3] == 0xfc:
            name = b[o + 5:o + 18].split(b"\n")[0].decode(errors="replace").strip()
    return f"{ven}/{b[10] | b[11] << 8:04x}/{name}".replace(" ", "_")


# ---------------------------------------------------------------- state readers
def parse_state(txt):
    objs, cur = {}, None
    for line in txt.splitlines():
        m = re.match(r"^(\w+)\[(\d+)\]: (.*)", line)
        if m:
            cur = objs.setdefault(m.group(3).strip(), {"_type": m.group(1), "_id": int(m.group(2))})
            continue
        if cur is not None and line.startswith("\t"):
            t = line.strip()
            if t.startswith("mode:"):
                f = t.split()
                cur["mode"] = {"clock": int(f[3]), "h": [int(x) for x in f[4:8]], "v": [int(x) for x in f[8:12]]}
            elif "=" in t:
                k, _, v = t.partition("=")
                cur.setdefault(k, v)
    return objs


def parse_vop2(txt):
    vps, cur = {}, None
    for line in txt.splitlines():
        m = re.match(r"^Video Port(\d+): (\w+)", line)
        if m:
            cur = vps.setdefault(int(m.group(1)), {"state": m.group(2)})
            continue
        if cur is None:
            continue
        m = re.search(r"Connector: (\S+)", line) or None
        if m:
            cur["connector"] = m.group(1)
        m = re.search(r"bus_format\[\w+\]: (\S+)", line)
        if m:
            cur["bus_format"] = m.group(1)
        m = re.search(r"Display mode: (\S+)", line)
        if m:
            cur["mode"] = m.group(1)
    for v in vps.values():
        bf = v.get("bus_format", "")
        m = re.match(r"[A-Z]+?(\d+)_", bf)
        if m:
            dg = m.group(1)
            v["bpc"] = {"888": 8, "101010": 10, "121212": 12, "161616": 16}.get(dg, int(dg) if len(dg) <= 2 else 0)
            v["fmt"] = ("RGB" if bf.startswith("RGB") else "YUV420" if bf.startswith("UYYVYY")
                        else "YUV422" if bf[:4] in ("UYVY", "YUYV", "VYUY", "YVYU") else "YUV444")
    return vps


def parse_scdc(txt):
    d = {}
    for line in txt.splitlines():
        if ":" in line and not re.match(r"^[0-9a-f]{2} ", line):
            k, _, v = line.partition(":")
            d[k.strip()] = v.strip()
    m = re.search(r"(\d+) Gbit/s x (\d)", d.get("FRL Rate", ""))
    d["_frl"] = (int(m.group(1)), int(m.group(2))) if m else (0, 0)
    d["_errors"] = sum(int(v) for k, v in d.items() if re.search(r"Errors|Corrections", k) and v.isdigit())
    d["_unlocked"] = [k for k, v in d.items() if k.endswith("Locked") and v != "yes"]
    return d


class Aux:
    def __init__(self, conn):
        self.path = ""
        base = f"/sys/class/drm/card0-{conn}"
        cand = [n for n in os.listdir(base) if n.startswith("drm_dp_aux")] if os.path.isdir(base) else []
        if not cand and os.path.isdir("/sys/class/drm_dp_aux_dev"):
            cand = sorted(os.listdir("/sys/class/drm_dp_aux_dev"))
            if len(cand) != 1:
                cand = []
        if cand:
            self.path = "/dev/" + cand[0]

    def rd(self, off, n):
        try:
            fd = os.open(self.path, os.O_RDONLY)
            try:
                return os.pread(fd, n, off)
            finally:
                os.close(fd)
        except OSError:
            return b""

    def wr(self, off, val):
        try:
            fd = os.open(self.path, os.O_WRONLY)
            try:
                os.pwrite(fd, bytes([val]), off)
            finally:
                os.close(fd)
            return True
        except OSError:
            return False

    def snapshot(self):
        r = {k: self.rd(o, n).hex() for k, o, n in (("caps", 0, 16), ("dfp", 0x80, 16), ("link", 0x100, 2),
                                                       ("status", 0x200, 8), ("symerr", 0x210, 8),
                                                       ("testmisc", 0x246, 1), ("pcon", 0x3050, 4))}
        return r

    def crc(self, n=5):
        """sink CRC (DP_TEST_SINK), as in dp-4k30/tools/crc.sh; [] when unsupported"""
        misc = self.rd(0x246, 1)
        if not misc or not misc[0] & 0x20:
            return None
        self.wr(0x270, 1)
        out = []
        try:
            cnt0 = self.rd(0x246, 1)[0] & 0xf
            t = time.time()
            while time.time() - t < 1.5 and (self.rd(0x246, 1)[0] & 0xf) == cnt0:
                time.sleep(0.02)
            for _ in range(n):
                time.sleep(0.1)
                out.append(self.rd(0x240, 6).hex())
        finally:
            self.wr(0x270, 0)
        return out


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
                break
            except OSError:   # EPIPE: overwritten records; keep going
                continue
            pre, _, msg = rec.partition(";")
            out.append((int(pre.split(",")[0]) & 7, msg.split("\n")[0]))
        return out


# ---------------------------------------------------------------- expectations
def timing(m):
    return f"{m['clock']}/{m['hdisplay']}:{m['hsync_start']}:{m['hsync_end']}:{m['htotal']}/" \
           f"{m['vdisplay']}:{m['vsync_start']}:{m['vsync_end']}:{m['vtotal']}/{m['flags']}"


MT_FLAGS = {"phsync": 1, "nhsync": 2, "pvsync": 4, "nvsync": 8, "interlace": 16, "dblscan": 32, "csync": 64}


def modetest_index(conn_id, m):
    """modetest's '#index' for the exact timing (its list can differ in order from ours)"""
    out = sh("modetest", "-M", "rockchip", "-c")
    cur = None
    for line in out.splitlines():
        f = line.split()
        if re.match(r"^\d+\t", line):
            cur = int(f[0])
        elif cur == conn_id and re.match(r"^\s+#\d+ ", line) and len(f) >= 12:
            fl = 0
            mm = re.search(r"flags: ([^;]*);", line)
            for x in (mm.group(1).split(", ") if mm else []):
                fl |= MT_FLAGS.get(x.strip(), 0)
            if [int(x) for x in f[3:12]] == [m["hdisplay"], m["hsync_start"], m["hsync_end"], m["htotal"],
                                             m["vdisplay"], m["vsync_start"], m["vsync_end"], m["vtotal"],
                                             m["clock"]] and fl == m["flags"] & 0x7f:
                return int(f[0][1:])
    return None


def mode_str(m):
    return f"{m['hdisplay']}x{m['vdisplay']}@{m['vrefresh']}/{m['clock']}"


def match_mode(modes, spec):
    """'WxH@R[/clockkHz]' -> mode index or None"""
    m = re.match(r"(\d+)x(\d+)@(\d+)(?:/(\d+))?$", spec)
    if not m:
        return None
    w, h, r, clk = int(m.group(1)), int(m.group(2)), int(m.group(3)), m.group(4)
    for i, md in enumerate(modes):
        if md["hdisplay"] == w and md["vdisplay"] == h and md["vrefresh"] == r and (not clk or md["clock"] == int(clk)):
            return i
    return None


def tmds_expected(clock_khz, bpc, fmt):
    r = clock_khz * 1000.0
    if fmt == "YCbCr 4:2:2" or fmt == "YUV422":
        return r
    if fmt in ("YCbCr 4:2:0", "YUV420"):
        r /= 2
    return r * bpc / 8


def hdmi_feasible(case, mode, caps):
    """True/False when the link budget decides whether (mode, max bpc, color format) is possible; None if unknown"""
    cf, bpc = case.get("cf", "AUTO"), int(case.get("bpc") or 8)
    if cf == "YUV 4:2:0":
        return None                     # depends on the 4:2:0 capability map / VIC; not modelled
    fmts = {"RGB": ["RGB"], "YUV 4:4:4": ["YUV444"], "YUV 4:2:2": ["YUV422"], "AUTO": ["RGB"]}[cf]
    if cf == "YUV 4:4:4" and not caps.get("y444") or cf == "YUV 4:2:2" and not caps.get("y422"):
        return False
    lim = min(SRC_TMDS_MAX, caps["max_tmds"])
    smax = FRL_CODES.get(caps["max_frl"], (0, 0))
    src = tuple(int(x) for x in SRC_FRL_MAX.split("x"))
    frl_cap = min(smax[0], src[0]) * min(smax[1], src[1]) * 1e9 * 16 / 18 * 0.95
    for f in fmts:
        for b in (8, 10, 12):
            if b > bpc or (f != "YUV422" and b == 10 and not caps["dc30"]) or (f != "YUV422" and b == 12 and not caps["dc36"]):
                continue
            if tmds_expected(mode["clock"], 8 if f == "YUV422" else b, f) <= lim:
                return True
            if frl_cap and mode["clock"] * 1000.0 * b * (2 if f == "YUV422" else 3) <= frl_cap:
                return True
    return False


def check_hdmi(case, st, scdc, caps, mode):
    reasons, notes = [], []
    cs = st.get(case["conn"], {})
    bpc, fmt = int(cs.get("output_bpc", "0") or 0), cs.get("output_format", "")
    rate = float(cs.get("tmds_char_rate", "0") or 0)
    req_bpc = int(case.get("bpc") or 8)
    if bpc and bpc > req_bpc:
        reasons.append(f"output_bpc {bpc} > max bpc {req_bpc}")
    if bpc and bpc < req_bpc and case.get("cf") in ("RGB", "YUV 4:4:4"):
        hi = dict(case, bpc=req_bpc)
        if req_bpc == 10 and caps["dc30"] and hdmi_feasible(hi, mode, dict(caps, dc36=0)):
            notes.append(f"output_bpc {bpc} although {req_bpc} fits the link")
    want_fmt = {"RGB": "RGB", "YUV 4:4:4": "YCbCr 4:4:4", "YUV 4:2:2": "YCbCr 4:2:2", "YUV 4:2:0": "YCbCr 4:2:0"}
    if case.get("cf") in want_fmt and fmt and fmt != want_fmt[case["cf"]]:
        reasons.append(f"output_format {fmt} != requested {case['cf']}")
    if rate and bpc:
        exp = tmds_expected(mode["clock"], bpc, fmt)
        if abs(rate - exp) > exp * 0.005:
            reasons.append(f"tmds_char_rate {rate:.0f} != mode/bpc/format {exp:.0f}")
    frl_rate, frl_lanes = scdc.get("_frl", (0, 0))
    if frl_rate:
        smax = FRL_CODES.get(caps["max_frl"], (0, 0))
        src = tuple(int(x) for x in SRC_FRL_MAX.split("x"))
        if (frl_rate, frl_lanes) > smax:
            reasons.append(f"FRL {frl_rate}G x{frl_lanes} > sink Max_FRL_Rate {smax[0]}G x{smax[1]}")
        if frl_rate > src[0] or frl_lanes > src[1]:
            reasons.append(f"FRL {frl_rate}G x{frl_lanes} > source {SRC_FRL_MAX}")
        cap = frl_rate * frl_lanes * 1e9 * 16 / 18                   # 16b/18b; ignores RS/packet overhead
        need = mode["clock"] * 1000.0 * (bpc or 8) * (3 if fmt in ("RGB", "YCbCr 4:4:4", "") else
                                                      2 if fmt == "YCbCr 4:2:2" else 1.5)
        if need > cap:
            reasons.append(f"FRL {frl_rate}Gx{frl_lanes} capacity {cap / 1e9:.2f} < stream {need / 1e9:.2f} Gbit/s")
        notes.append(f"FRL {frl_rate}Gx{frl_lanes}")
    elif rate:
        lim = min(SRC_TMDS_MAX, caps["max_tmds"])
        if rate > lim + 1:
            reasons.append(f"TMDS {rate / 1e6:.2f} MHz > min(source {SRC_TMDS_MAX / 1e6:.0f}, sink {caps['max_tmds'] / 1e6:.0f})")
        scr = scdc.get("Scrambling Enabled", "")
        if rate > 340e6 and scr and scr != "yes":
            reasons.append("TMDS > 340 MHz without scrambling")
        ratio = scdc.get("TMDS Bit Clock Ratio", "")
        if ratio and (rate > 340e6) != (ratio == "1/40"):
            reasons.append(f"TMDS bit clock ratio {ratio} for {rate / 1e6:.0f} MHz")
        notes.append(f"TMDS {rate / 1e6:.2f}MHz")
    if bpc > 8 and fmt == "RGB" and not caps["dc30"]:
        reasons.append("deep colour RGB but sink EDID has no DC_30bit")
    if fmt == "YCbCr 4:2:0" and bpc == 10 and not caps["dc420_30"]:
        reasons.append("10 bpc 4:2:0 but sink has no DC_420_30")
    if scdc.get("_unlocked") and (frl_rate or rate > 340e6):
        reasons.append("SCDC not locked: " + ",".join(scdc["_unlocked"]))
    if scdc.get("_errors"):
        reasons.append(f"SCDC errors {scdc['_errors']}")
    return reasons, notes, {"output_bpc": bpc, "output_format": fmt, "tmds_char_rate": int(rate),
                            "link": notes[0] if notes else ""}


def check_dp(dp, vp, mode):
    reasons, notes = [], []
    link = bytes.fromhex(dp.get("link", "")) or b"\0\0"
    stat = bytes.fromhex(dp.get("status", "")) or b"\0" * 8
    caps = bytes.fromhex(dp.get("caps", "")) or b"\0" * 16
    gbps, lanes = link[0] * 0.27, link[1] & 0x1f
    notes.append(f"DP {gbps:.2f}Gx{lanes}")
    if not lanes:
        reasons.append("DPCD: no link configured")
        return reasons, notes
    for ln in range(lanes):
        if (stat[2 + ln // 2] >> (4 * (ln % 2))) & 7 != 7:
            reasons.append(f"lane {ln} not CR/EQ/SL done ({stat[2:4].hex()})")
            break
    if not stat[4] & 1:
        reasons.append("lanes not interlane-aligned")
    if gbps > min(caps[1] * 0.27, SRC_DP_MAX_GBPS) + 0.01 or lanes > (caps[2] & 0x1f):
        reasons.append(f"link {gbps:.2f}Gx{lanes} > sink caps {caps[1] * 0.27:.2f}Gx{caps[2] & 0x1f}")
    bpc = vp.get("bpc") or 8
    mult = {"RGB": 3, "YUV444": 3, "YUV422": 2, "YUV420": 1.5}.get(vp.get("fmt", "RGB"), 3)
    need, cap = mode["clock"] * 1000.0 * bpc * mult, gbps * 1e9 * lanes * 0.8
    if need > cap:
        reasons.append(f"stream {need / 1e9:.2f} > link {cap / 1e9:.2f} Gbit/s")
    se = bytes.fromhex(dp.get("symerr", ""))
    errs = [(se[2 * i] | (se[2 * i + 1] & 0x7f) << 8) for i in range(lanes)] if len(se) >= 2 * lanes else []
    if any(e for e, v in zip(errs, [se[2 * i + 1] >> 7 for i in range(lanes)]) if v):
        reasons.append(f"DP symbol errors {errs}")
    return reasons, notes


# ---------------------------------------------------------------- case generation
def build_cases(info, groups, only_conn):
    conns = [c for c in info["connectors"] if c["connected"] and (not only_conn or c["name"] in only_conn)]
    planes = info["planes"]
    cases = []

    def crtc_for(c):
        return c["possible_crtcs"][0]

    def primary(crtc):
        return next(p for p in planes if p["type"] == "Primary" and crtc in p["possible_crtcs"])

    def scanout(c, fmt):
        """(plane, fmt) for full-screen pattern cases: the primary plane (AFBC via the GPU when it has no
        linear) if the start-up probe could draw on it, else the first overlay with linear XR24"""
        crtc = crtc_for(c)
        pr = info.get("probe", {}).get(c["name"], {})
        if pr.get(fmt, True):
            return primary(crtc), fmt
        if fmt != "XR24" and pr.get("XR24", True):
            return primary(crtc), "XR24"
        ov = next((p for p in planes if crtc in p["possible_crtcs"] and "0x0" in p["formats"].get("XR24", [])),
                  primary(crtc))
        return ov, "XR24"

    def add(**kw):
        kw.setdefault("pattern", "bars")
        kw["key"] = "/".join(f"{k}={kw[k]}" for k in sorted(kw) if k not in ("modes",))
        cases.append(kw)

    for c in conns:
        crtc = crtc_for(c)
        pp, f8 = scanout(c, "XR24")
        p10, f10 = scanout(c, "XR30")
        pref = next((i for i, m in enumerate(c["modes"]) if m["type"] & 8), 0)
        if "calib" in groups and c["name"] == CAM_CONN:
            ci = match_mode(c["modes"], CAM_CALIB_MODE)
            ci = pref if ci is None else ci
            add(group="calib", conn=c["name"], mode=ci, pattern="white", plane=pp["id"], fmt=f8)
            add(group="calib", conn=c["name"], mode=ci, pattern="black", plane=pp["id"], fmt=f8)
            import fnmatch
            mon = monitor_id(c["edid"])
            print(f"camera monitor {c['name']}: {mon}", flush=True)
            for kn in CAM_KNOWN.split():           # [GLOB|]MODE[,bpc=N][,cf=NAME]=GOOD|BAD  (cf: '_' for ' ')
                glob, _, kn = kn.rpartition("|")
                if glob and not fnmatch.fnmatchcase(mon, glob):
                    continue
                spec, _, want = kn.rpartition("=")
                mspec, *kvs = spec.split(",")
                kw = {k: v.replace("_", " ") for k, v in (x.split("=", 1) for x in kvs)}
                if "bpc" in kw:
                    kw["bpc"] = int(kw["bpc"])
                    kw.setdefault("cf", "AUTO")
                mi = match_mode(c["modes"], mspec)
                if mi is not None:
                    hp, hf = (p10, f10) if kw.get("bpc", 8) > 8 else (pp, f8)
                    add(group="calib", conn=c["name"], mode=mi, plane=hp["id"], fmt=hf, expect=want, **kw)
                else:
                    print(f"CAM_KNOWN {kn}: no such mode on {c['name']}", flush=True)
        if "modes" in groups:
            for i in range(len(c["modes"])):
                add(group="modes", conn=c["name"], mode=i, plane=pp["id"], fmt=f8)
            ov = next((p for p in planes if p["type"] == "Overlay" and crtc in p["possible_crtcs"]
                       and "0x0" in p["formats"].get("XR24", [])), None)
            if ov:   # the same modes through modetest (legacy-free atomic, explicit -P, smpte fill)
                for i in range(len(c["modes"])):
                    add(group="modetest", conn=c["name"], mode=i, plane=ov["id"], fmt="XR24", engine="modetest",
                        pattern="smpte")
        pr = c["props"]
        if "props" in groups and ("max bpc" in pr or "color format" in pr):
            lo, hi = pr.get("max bpc", {}).get("range", [8, 8])
            bpcs = [b for b in (8, 10, 12) if lo <= b <= hi]
            cfs = list(pr.get("color format", {}).get("enums", {"AUTO": 0}))
            idxs = range(len(c["modes"]))
            if os.environ.get("PROPS_MODES", "all") == "unique":
                seen, idxs = set(), []
                for i, m in enumerate(c["modes"]):
                    if (m["hdisplay"], m["vdisplay"], m["vrefresh"]) not in seen:
                        seen.add((m["hdisplay"], m["vdisplay"], m["vrefresh"]))
                        idxs.append(i)
            for i in idxs:
                for b in bpcs:
                    for cf in cfs:
                        if b == 8 and cf == "AUTO":
                            continue           # = the modes group
                        add(group="props", conn=c["name"], mode=i, plane=(p10 if b > 8 else pp)["id"], bpc=b,
                            cf=cf, fmt=f10 if b > 8 else f8)
        if "hdr" in groups and "HDR_OUTPUT_METADATA" in pr:
            hi = pr.get("max bpc", {}).get("range", [8, 8])[1]
            for e in ("pq", "hlg", "none"):
                add(group="hdr", conn=c["name"], mode=pref, plane=p10["id"], bpc=min(hi, 10), cf="AUTO",
                    fmt=f10, hdr=e)
        if "vrr" in groups and rd(f"{DBG}/{c['name']}/vrr_range").strip() not in ("", "Min: 0\nMax: 0"):
            add(group="vrr", conn=c["name"], mode=pref, plane=pp["id"], fmt=f8, vrr=1)
        if "planes" in groups:
            for p in planes:
                if crtc not in p["possible_crtcs"]:
                    continue
                for fmt, mods in p["formats"].items():
                    for mod in mods:
                        m = int(mod, 16)
                        kw = dict(group="planes", conn=c["name"], mode=pref, plane=p["id"], fmt=fmt, mod=mod)
                        if m == 0 and fmt in RGB_FILL:
                            add(**kw)
                        elif m == 0:
                            add(engine="modetest", pattern="smpte", **kw)
                        elif fmt in YUV_FMTS:
                            add(skip="no userspace producer of AFBC YUV (GL cannot render YUV; mainline "
                                     "decoders do not output AFBC)", **kw)
                        else:
                            add(**kw)
    if "dual" in groups and len(conns) >= 2:
        a, b = conns[0], conns[1]

        def pick(c, how):
            ms = c["modes"]
            if how == "pref":
                return next((i for i, m in enumerate(ms) if m["type"] & 8), 0)
            if how == "max":
                return max(range(len(ms)), key=lambda i: ms[i]["clock"])
            return match_mode(ms, how)
        for how in ("pref", "max", "1920x1080@60", "3840x2160@30"):
            ia, ib = pick(a, how), pick(b, how)
            if ia is None or ib is None:
                continue
            for ov in (0, 1):
                add(group="dual", conn=a["name"], mode=ia, conn2=b["name"], mode2=ib, overlays=ov,
                    plane=scanout(a, "XR24")[0]["id"], plane2=scanout(b, "XR24")[0]["id"], fmt=scanout(a, "XR24")[1])
        pa = a["props"]
        if "max bpc" in pa and pa["max bpc"]["range"][1] >= 10:
            add(group="dual", conn=a["name"], mode=pick(a, "pref"), conn2=b["name"], mode2=pick(b, "pref"),
                overlays=0, plane=scanout(a, "XR30")[0]["id"], plane2=scanout(b, "XR30")[0]["id"],
                fmt=scanout(a, "XR30")[1], bpc=10)
    cases.sort(key=lambda c: c["group"] != "calib")     # webcam calibration first (stable sort)
    for i, c in enumerate(cases):
        c["idx"] = i
    return cases


# ---------------------------------------------------------------- runner
class Runner:
    def __init__(self, out, info):
        self.out, self.info = out, info
        self.conns = {c["name"]: c for c in info["connectors"]}
        self.caps = {n: edid_caps(c["edid"]) for n, c in self.conns.items() if c["edid"]}
        self.kmsg = Kmsg()
        self.calib = None
        cp = f"{out}/calib.json"
        if os.path.exists(cp):
            self.calib = json.load(open(cp))
        self.cam_dev = camcheck.find() if CAM_CONN else ""
        cases = info.get("_cases", [])
        cal = [c for c in cases if c["group"] == "calib"]
        self.cal_white = next((c for c in cal if c["pattern"] == "white"), None)
        self.cal_black = next((c for c in cal if c["pattern"] == "black"), None)
        self.control = next((c for c in cal if c.get("expect") == "GOOD"), None)
        self.cam_cases, self.nctl = 0, 0
        self.spans_path = f"{out}/camera-spans.json"
        st = json.load(open(self.spans_path)) if os.path.exists(self.spans_path) else {}
        self.spans = st.get("spans", [])                  # [{start, end, moved_at, restored_at}]
        self.last_good = st.get("last_good", -1)
        self.cam_trusted = not (self.spans and self.spans[-1].get("end") is None)

    # ---- camera control (the camera can be bumped during a long run)
    def log_cam(self, msg):
        line = f"{time.strftime('%F %T')} {msg}"
        print(line, flush=True)
        open(f"{self.out}/camera-events.log", "a").write(line + "\n")

    def save_spans(self):
        json.dump({"spans": self.spans, "last_good": self.last_good}, open(self.spans_path, "w"), indent=1)

    def _show(self, case, tag):
        self.nctl += 1
        row = self.run_case(dict(case, _dir=f"ctl/{self.nctl:04d}-{tag}", _ctl=1))
        open(f"{self.out}/controls.tsv", "a").write(
            f"{time.strftime('%F %T')}\t{tag}\t{row['mode']}\t{row['cam']}\t{row['dmesg']}\t{row['reasons']}\n")
        return row

    def _control_ok(self):
        if not self.control:
            return True
        row = self._show({k: v for k, v in self.control.items() if k != "expect"}, "control")
        return row["cam"].split(":")[0] == "GOOD"

    def _recalibrate(self):
        if not (self.cal_white and self.cal_black):
            return False
        old = self.calib
        self._show(self.cal_white, "white")
        self._show(self.cal_black, "black")
        return self.calib is not old

    def control_check(self, idx):
        """re-show the known-GOOD control; on failure open an UNTRUSTED span (from the last good control),
        try one recalibration, and close the span again if the control then passes. Returns trust."""
        if not (self.cam_dev and self.calib and self.control):
            return self.cam_trusted
        if self._control_ok():
            if not self.cam_trusted:
                self.spans[-1].update(end=idx, restored_at=time.strftime("%F %T"))
                self.log_cam(f"camera control GOOD again at case {idx}: camera verdicts trusted again")
            self.cam_trusted, self.last_good = True, idx
            self.save_spans()
            return True
        if self.cam_trusted:
            self.log_cam(f"CAMERA MOVED: control failed at case {idx}; camera verdicts since case "
                         f"{self.last_good + 1} are UNTRUSTED (non-camera checks continue)")
            self.spans.append({"start": self.last_good + 1, "end": None, "moved_at": time.strftime("%F %T")})
            self.cam_trusted = False
        if self._recalibrate() and self._control_ok():
            self.spans[-1].update(end=idx, restored_at=time.strftime("%F %T"))
            self.log_cam(f"camera recalibrated at case {idx} (box {self.calib['box']}), control GOOD: trusted again")
            self.cam_trusted, self.last_good = True, idx
        self.save_spans()
        return self.cam_trusted

    def overlay_for(self, crtc, used):
        return next((p for p in self.info["planes"] if p["type"] == "Overlay" and crtc in p["possible_crtcs"]
                     and "0x0" in p["formats"].get("XR24", []) and p["id"] not in used), None)

    def start(self, case):
        """commit the case; returns (proc, commit_ok, err, info)"""
        c = self.conns[case["conn"]]
        if case.get("engine") == "modetest":
            crtc = c["possible_crtcs"][0]
            md = c["modes"][case["mode"]]
            m = modetest_index(c["id"], md)
            if m is None:
                return None, False, f"HARNESS: modetest lists no mode with exact timing {timing(md)}", {}
            pr = c["props"]
            reset = []
            for name, val in (("max bpc", 8), ("color format", 0), ("HDR_OUTPUT_METADATA", 0)):
                if name in pr:
                    reset += ["-w", f"{c['id']}:{name}:{val}"]
            cmd = ["modetest", "-M", "rockchip", "-a"] + reset + ["-s", f"{c['id']}@{crtc}:#{m}",
                   "-P", f"{case['plane']}@{crtc}:{md['hdisplay']}x{md['vdisplay']}@{case['fmt']}", "-F", "smpte,smpte"]
            p = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                 text=True)
            time.sleep(2)
            if p.poll() is not None:
                o = p.stdout.read()
                return None, False, (o.strip().splitlines() or ["modetest exited"])[-1][:160], {"cmd": cmd}
            return p, True, "", {"cmd": cmd}
        heads = []

        def head(conn, mode, plane, extra=""):
            s = f"conn={conn},timing={timing(self.conns[conn]['modes'][mode])},plane={plane},fmt={case['fmt']}," \
                f"mod={case.get('mod', 'auto')}," \
                f"pattern={case['pattern']},code={case['idx']}"
            pr = self.conns[conn]["props"]
            if "bpc" in case and "max bpc" in pr:
                s += f",prop:max bpc={case['bpc']}"
            elif "max bpc" in pr:
                s += ",prop:max bpc=8"
            if "color format" in pr:
                s += f",prop:color format={case.get('cf', 'AUTO')}"
            if "hdr" in case:
                s += f",prop:HDR_OUTPUT_METADATA=hdr:{case['hdr']}"
            elif "HDR_OUTPUT_METADATA" in pr:
                s += ",prop:HDR_OUTPUT_METADATA=hdr:none"
            if "vrr" in case:
                s += f",prop:crtc:VRR_ENABLED={case['vrr']}"
            return ["--head", s + extra]
        heads += head(case["conn"], case["mode"], case["plane"])
        if "conn2" in case:
            heads += head(case["conn2"], case["mode2"], case["plane2"])
        if case.get("overlays"):
            used = {case["plane"], case.get("plane2")}
            for cn in (case["conn"], case.get("conn2")):
                if not cn:
                    continue
                ov = self.overlay_for(self.conns[cn]["possible_crtcs"][0], used)
                if ov:
                    used.add(ov["id"])
                    heads += ["--plane", f"conn={cn},plane={ov['id']},fmt=XR24,mod=linear,pattern=bars,"
                                         f"code={case['idx']}"]
        cmd = [sys.executable, "-I", f"{HERE}/kmsctl.py", "show"] + (["--leave-others"] if LEAVE_OTHERS else []) + heads
        p = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        r, _, _ = select.select([p.stdout], [], [], 30)
        line = p.stdout.readline() if r else ""
        try:
            res = json.loads(line)
        except ValueError:
            res = {"ok": False, "err": "kmsctl: no result " + (p.stderr.read()[-200:] if p.poll() is not None else "(hung)")}
        if not res.get("ok"):
            self.stop(p)
            return None, False, res.get("err", "?"), {"cmd": cmd, "res": res}
        return p, True, "", {"cmd": cmd, "res": res}

    @staticmethod
    def stop(p):
        if p is None:
            return
        try:
            p.stdin.close()
        except OSError:
            pass
        try:
            p.wait(5)
        except subprocess.TimeoutExpired:
            p.send_signal(signal.SIGTERM)
            try:
                p.wait(5)
            except subprocess.TimeoutExpired:
                p.kill()

    def run_case(self, case):
        d = f"{self.out}/{case['_dir']}" if "_dir" in case else f"{self.out}/case/{case['idx']:04d}"
        os.makedirs(d, exist_ok=True)
        row = {"idx": case["idx"], "group": case["group"], "conn": case["conn"] + ("+" + case["conn2"] if "conn2" in case else ""),
               "mode": mode_str(self.conns[case["conn"]]["modes"][case["mode"]]) +
               ("+" + mode_str(self.conns[case["conn2"]]["modes"][case["mode2"]]) if "conn2" in case else ""),
               "bpc": case.get("bpc", ""),
               "cf": case.get("cf", ""), "plane": case.get("plane", ""), "fmt": case.get("fmt", ""),
               "mod": case.get("mod", "auto"), "engine": case.get("engine", "kmsctl"), "commit": "", "output": "",
               "link": "", "crc": "", "cam": "", "dmesg": "", "verdict": "", "reasons": "", "notes": ""}
        if case.get("skip"):
            row.update(verdict="SKIP", reasons=case["skip"])
            return row
        self.kmsg.drain()
        p, ok, e, meta = self.start(case)
        json.dump(meta, open(f"{d}/commit.json", "w"))
        reasons, notes = [], []
        if not ok:
            row["commit"] = "REJECT"
            row["reasons"] = e
            if "HARNESS" in e:
                row["verdict"] = "HARNESS-ERROR"
                print(f"!!! HARNESS ERROR (not a DUT result) case {case['idx']}: {e}", flush=True)
                return row
            tool = (e.startswith("setup:") and "ADDFB2" not in e) or \
                re.search(r"(?i)unknown format|unsupported (pixel )?format|invalid format|format not supported", e)
            if tool:
                row["verdict"] = "SKIP-TOOL"
            elif case["group"] == "props":
                c = self.conns[case["conn"]]
                fz = hdmi_feasible(case, c["modes"][case["mode"]], self.caps.get(case["conn"], edid_caps(""))) \
                    if case["conn"].startswith("HDMI") else None
                row["verdict"] = "FAIL" if fz else "REJECT"
                row["notes"] = "link budget allows it" if fz else ("not possible on this link" if fz is False else
                                                                   "feasibility not modelled")
            else:
                row["verdict"] = "REJECT" if case["group"] == "dual" else "FAIL"
            self.log_kmsg(row, reasons, case)
            if reasons:
                row["verdict"] = "FAIL"
                row["reasons"] += "; " + "; ".join(reasons)
            return row
        row["commit"] = "ok"
        try:
            on_cam = CAM_CONN in (case["conn"], case.get("conn2"))
            time.sleep(SETTLE + (CAM_SETTLE if on_cam and self.cam_dev else 0))
            if p.poll() is not None:
                reasons.append(f"{row['engine']} exited early rc={p.returncode}")
            self.collect(case, row, reasons, notes, d)
        finally:
            self.stop(p)
        time.sleep(0.5)
        self.log_kmsg(row, reasons, case)
        cam_fail = any(r.startswith("webcam: picture") for r in reasons)
        if cam_fail and "_ctl" not in case and "expect" not in case:
            # before recording a camera-judged FAIL: is the camera still where it was calibrated?
            if self.control_check(case["idx"]) and self.last_good == case["idx"] and not case.get("_retry") \
                    and self.spans and self.spans[-1].get("end") == case["idx"]:
                return self.run_case(dict(case, _retry=1))     # recalibrated just now: judge this case again
            if not self.cam_trusted or (self.spans and self.spans[-1].get("end") == case["idx"]):
                reasons = [r for r in reasons if not r.startswith("webcam:")]
                row["cam"] = "UNTRUSTED:" + row["cam"]
        row["reasons"] = "; ".join(reasons)
        row["notes"] = "; ".join(notes)
        row["verdict"] = "FAIL" if reasons else "PASS"
        if row["cam"].startswith("UNTRUSTED") and cam_fail and not reasons:
            row["verdict"] = "UNTRUSTED"
        if "expect" in case and "_ctl" not in case:
            got = row["cam"].split(":")[0]
            match = (got == "GOOD") == (case["expect"] == "GOOD")
            row["verdict"] = "CALIB-" + ("MATCH" if match else "MISMATCH")
            if not match and self.calib:
                self.calib["trusted"] = False          # camera verdicts are then recorded but never fail a case
                json.dump(self.calib, open(f"{self.out}/calib.json", "w"))
        return row

    def log_kmsg(self, row, reasons, case=None):
        msgs = self.kmsg.drain()
        mine = {n.split("-")[0].rstrip("e") if not n.startswith("eDP") else "DP"
                for n in (case["conn"], case.get("conn2")) if n} if case else set(CONN_SCOPE)
        mine = {("HDMI" if x.startswith("HDMI") else "DP") for x in mine}

        def ours(m):            # a message naming only another connector's hardware is background
            hits = {k for k, rx in CONN_SCOPE.items() if rx.search(m)}
            return not hits or bool(hits & mine)
        bg = [m for pri, m in msgs if (pri <= 3 or DMESG_BAD.search(m)) and DMESG_SCOPE.search(m) and not ours(m)]
        if bg:
            with open(f"{self.out}/background.log", "a") as f:
                for m in bg:
                    f.write(f"{time.strftime('%F %T')}\tcase {row['idx']} ({row['conn']})\t{m}\n")
        msgs = [(p, m) for p, m in msgs if ours(m)]
        pbe = sum("POST_BUF_EMPTY" in m for _, m in msgs)
        bad = [m for pri, m in msgs if (pri <= 3 or DMESG_BAD.search(m)) and DMESG_SCOPE.search(m)]
        row["dmesg"] = f"pbe={pbe} bad={len(bad)}" + (f" [{bad[0][:100]}]" if bad else "")
        if pbe:
            reasons.append(f"POST_BUF_EMPTY x{pbe}")
        if bad:
            reasons.append(f"kernel: {bad[0][:120]}")

    def collect(self, case, row, reasons, notes, d):
        st_txt = rd(f"{DBG}/state")
        vop_txt = rd(f"{DBG}/vop2/summary")
        open(f"{d}/state.txt", "w").write(st_txt)
        open(f"{d}/vop2.txt", "w").write(vop_txt)
        st, vps = parse_state(st_txt), parse_vop2(vop_txt)
        outs = []
        for cn, mi in ((case["conn"], case["mode"]), (case.get("conn2"), case.get("mode2"))):
            if not cn:
                continue
            c = self.conns[cn]
            mode = c["modes"][mi]
            cst = st.get(cn, {})
            crtc_name = cst.get("crtc", "")
            cr = st.get(crtc_name, {})
            if cr.get("active") != "1":
                reasons.append(f"{cn}: CRTC {crtc_name or '-'} not active")
            elif cr.get("mode", {}).get("clock") != mode["clock"] or cr["mode"]["h"][0] != mode["hdisplay"]:
                reasons.append(f"{cn}: CRTC mode {cr.get('mode')} != requested {mode_str(mode)}")
            vp = next((v for v in vps.values() if v.get("connector") == cn), {})
            if cn.startswith("HDMI"):
                scdc_txt = rd(f"{DBG}/{cn}/scdc_status")
                open(f"{d}/scdc-{cn}.txt", "w").write(scdc_txt)
                scdc = parse_scdc(scdc_txt)
                r, nn, o = check_hdmi(case if cn == case["conn"] else {"conn": cn}, st, scdc,
                                     self.caps.get(cn, edid_caps("")), mode)
                reasons += [f"{cn}: {x}" for x in r]
                notes += [x for x in nn[1:]]
                outs.append(f"{cn}:{o['output_bpc']}b/{o['output_format'] or vp.get('fmt', '')}")
                row["link"] += (" " if row["link"] else "") + (o["link"] or "")
                if "hdr" in case and cn == case["conn"]:
                    try:
                        raw = open(f"{DBG}/{cn}/infoframes/hdr_drm", "rb").read()
                    except OSError:
                        raw = b""
                    open(f"{d}/hdr_drm-{cn}.bin", "wb").write(raw)
                    want = {"pq": 2, "hlg": 3}.get(case["hdr"])
                    got = raw[4] & 7 if len(raw) > 4 and raw[0] == 0x87 else None   # type 0x87, ver, len, csum, EOTF
                    if want is not None and got != want:
                        reasons.append(f"{cn}: DRM (HDR) infoframe EOTF {got} != {want} ({raw[:8].hex()})")
                    if want is None and got:
                        reasons.append(f"{cn}: DRM infoframe still sent after HDR metadata was cleared")
            elif cn.startswith("DP") or cn.startswith("eDP"):
                aux = Aux(cn)
                if not aux.path:
                    notes.append(f"{cn}: no DP AUX device")
                    continue
                snap = aux.snapshot()
                crc = aux.crc()
                snap["crc"] = crc
                json.dump(snap, open(f"{d}/dpcd-{cn}.json", "w"))
                r, n = check_dp(snap, vp, mode)
                reasons += [f"{cn}: {x}" for x in r]
                outs.append(f"{cn}:{vp.get('bpc', '?')}b/{vp.get('fmt', '?')}")
                row["link"] += (" " if row["link"] else "") + " ".join(n)
                if crc is None:
                    row["crc"] = "unsupported"
                elif not crc or len(set(crc)) != 1 or crc[0] == "000000000000":
                    row["crc"] = "unstable:" + ",".join(sorted(set(crc)))
                    reasons.append(f"{cn}: sink CRC not stable/non-zero {sorted(set(crc))}")
                else:
                    row["crc"] = crc[0]
            if cn == CAM_CONN and self.cam_dev:
                self.camera(case, row, reasons, d)
        row["output"] = " ".join(outs)

    def camera(self, case, row, reasons, d):
        try:
            img = camcheck.load(camcheck.capture(f"{d}/cam", self.cam_dev))
        except RuntimeError as e:
            row["cam"] = "ERROR"
            reasons.append(f"webcam: {e}")
            return
        if case["group"] == "calib" and case["pattern"] in ("white", "black"):
            row["cam"] = case["pattern"]
            if case["pattern"] == "white":
                self.white_rgb = f"{d}/cam.rgb"
            if case["pattern"] == "black":
                try:
                    cal = camcheck.calib(self.white_rgb, f"{d}/cam.rgb")   # screen quad + homography
                    json.dump(cal, open(f"{self.out}/calib.json", "w"))
                    self.calib = cal
                    row["cam"] = f"calib box={cal['box']}"
                except (RuntimeError, IndexError, ValueError) as e:
                    reasons.append(f"webcam calibration: {e}")
            return
        if not self.calib:
            row["cam"] = "uncalibrated"
            return
        code = case["idx"] if case["pattern"] == "bars" else None
        r = camcheck.classify(self.calib, img, case["pattern"], code)
        retry = float(os.environ.get("CAM_RETRY", "6"))
        if r["verdict"] != "GOOD" and retry and "_ctl" not in case:
            # some sinks take longer to resync: look again before judging; keep the first frame as cam-first.*
            for ext in ("jpg", "rgb"):
                if os.path.exists(f"{d}/cam.{ext}"):
                    os.replace(f"{d}/cam.{ext}", f"{d}/cam-first.{ext}")
            time.sleep(retry)
            try:
                r2 = camcheck.classify(self.calib, camcheck.load(camcheck.capture(f"{d}/cam", self.cam_dev)),
                                       case["pattern"], code)
                r2["first"] = r["verdict"]
                r = r2
            except RuntimeError:
                pass
        json.dump(r, open(f"{d}/cam.json", "w"))
        row["cam"] = camcheck.cam_summary(r) + (f",first={r['first']}" if r.get("first") else "")
        if "_ctl" in case or "expect" in case:
            return
        if not self.cam_trusted:
            row["cam"] = "UNTRUSTED:" + row["cam"]
        elif r["verdict"] != "GOOD" and self.calib.get("trusted", True):
            reasons.append(f"webcam: picture {r['verdict']}")


COLS = ["idx", "group", "conn", "mode", "bpc", "cf", "plane", "fmt", "mod", "engine", "commit", "output", "link",
        "crc", "cam", "dmesg", "verdict", "reasons", "notes"]


def crc_pass(rows, cases, golden):
    """the same picture (connector, size, pattern, format, output bpc/format) must give the same DP sink CRC,
    whatever the timing, plane or modifier (linear vs AFBC). Reference: golden file, else strict majority."""
    groups = {}
    for r in rows:
        if re.fullmatch(r"[0-9a-f]{12}", r.get("crc", "")) and "+" not in r["conn"]:
            k = "|".join((r["conn"], r["mode"].split("@")[0], cases[int(r["idx"])]["pattern"], r["fmt"], r["output"]))
            groups.setdefault(k, []).append(r)
    out = []
    for k, rs in groups.items():
        cnt = {}
        for r in rs:
            cnt[r["crc"]] = cnt.get(r["crc"], 0) + 1
        ref = golden.get(k)
        if not ref:
            best, n = max(cnt.items(), key=lambda kv: kv[1])
            ref = best if n * 2 > len(rs) else None
            if ref is None and len(cnt) > 1:
                out += [(r["idx"], f"sink CRCs of the same picture disagree with no majority {cnt} ({k})") for r in rs]
        for r in rs:
            if ref and r["crc"] != ref:
                out.append((r["idx"], f"sink CRC {r['crc']} != {ref} of the same picture ({k})"))
        if ref and len(rs) >= 2:
            golden.setdefault(k, ref)
    return out


def probe(info):
    """can kmsctl draw XR24 / XR30 full screen on each connector's primary plane? (TEST_ONLY commits)"""
    out = {}
    for c in info["connectors"]:
        if not c["connected"]:
            continue
        pref = next((i for i, m in enumerate(c["modes"]) if m["type"] & 8), 0)
        out[c["name"]] = {}
        for fmt in ("XR24", "XR30"):
            r = subprocess.run([sys.executable, "-I", f"{HERE}/kmsctl.py", "show", "--test-only", "--head",
                                f"conn={c['name']},mode={pref},fmt={fmt}"], capture_output=True, text=True, timeout=60)
            try:
                ok = json.loads(r.stdout.splitlines()[0]).get("ok", False)
            except (ValueError, IndexError):
                ok = False
            out[c["name"]][fmt] = ok
        print(f"probe {c['name']}: primary plane XR24={out[c['name']]['XR24']} XR30={out[c['name']]['XR30']}", flush=True)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--groups", default="calib,modes,modetest,props,hdr,vrr,planes,dual")
    ap.add_argument("--conn", default="")
    ap.add_argument("--max", type=int, default=0)
    ap.add_argument("--list-only", action="store_true")
    ap.add_argument("--info", help="kmsctl list JSON to use instead of the live device (dry runs)")
    a = ap.parse_args()
    global LEAVE_OTHERS
    LEAVE_OTHERS = bool(a.conn)
    os.makedirs(a.out, exist_ok=True)
    cf = f"{a.out}/cases.json"
    if os.path.exists(cf):
        info, cases = json.load(open(cf))
    else:
        info = json.load(open(a.info)) if a.info else json.loads(subprocess.run(
            [sys.executable, "-I", f"{HERE}/kmsctl.py", "list"], capture_output=True, text=True, check=True).stdout)
        if not a.info:
            info["probe"] = probe(info)
        cases = build_cases(info, a.groups.split(","), [x for x in a.conn.split(",") if x])
        json.dump([info, cases], open(cf, "w"))
    counts = {}
    for c in cases:
        counts[c["group"]] = counts.get(c["group"], 0) + 1
    print(f"{len(cases)} cases: {counts}", flush=True)
    if a.list_only:
        for c in cases:
            print(c["idx"], c["key"])
        return 0
    tsv, prog = f"{a.out}/results.tsv", f"{a.out}/inprogress"
    done = set()
    if os.path.exists(tsv):
        for line in open(tsv).read().splitlines()[1:]:
            done.add(int(line.split("\t")[0]))
    else:
        open(tsv, "w").write("\t".join(COLS) + "\n")
    info["_cases"] = cases
    runner = Runner(a.out, info)
    if CAM_CONN and not runner.cam_dev:
        print(f"WARNING: CAM_CONN={CAM_CONN} but no webcam matching {camcheck.CAM_NAME!r}: no picture checks", flush=True)
    if os.path.exists(prog):
        i = int(rd(prog) or -1)
        if 0 <= i < len(cases) and i not in done:
            c = cases[i]
            row = {k: "" for k in COLS} | {"idx": i, "group": c["group"], "conn": c["conn"], "verdict": "FAIL",
                                           "reasons": "case never finished (board hung or rebooted)"}
            open(tsv, "a").write("\t".join(str(row[k]) for k in COLS) + "\n")
            done.add(i)
    n = 0
    t0 = time.time()
    for c in cases:
        if c["idx"] in done:
            continue
        if a.max and n >= a.max:
            break
        open(prog, "w").write(str(c["idx"]))
        os.sync()
        row = runner.run_case(c)
        if CAM_CONN in (c["conn"], c.get("conn2")) and c["group"] != "calib" and not c.get("skip") \
                and row["commit"] == "ok":
            runner.cam_cases += 1
            if runner.cam_cases % CAM_CONTROL_EVERY == 0:
                runner.control_check(c["idx"])
        line = "\t".join(str(row[k]).replace("\t", " ").replace("\n", " ") for k in COLS)
        with open(tsv, "a") as f:
            f.write(line + "\n")
            f.flush()
            os.fsync(f.fileno())
        n += 1
        print(f"[{c['idx'] + 1}/{len(cases)} {time.time() - t0:.0f}s] {row['verdict']:6s} {row['group']:8s} "
              f"{row['conn']} {row['mode']} {row['bpc']} {row['cf']} p{row['plane']} {row['fmt']} {row['mod']} "
              f"{row['output']} {row['link']} {row['cam']} {row['reasons'][:120]}", flush=True)
    if os.path.exists(prog):
        os.unlink(prog)
    if runner.cam_dev and runner.calib and runner.control:
        runner.control_check(cases[-1]["idx"])          # final control closes or confirms the last span
    summarize(a.out, cases)
    return 0


def summarize(out, cases):
    rows = [dict(zip(COLS, line.split("\t"))) for line in open(f"{out}/results.tsv").read().splitlines()[1:]]
    gp = os.environ.get("CRC_GOLDEN", "")
    golden = json.load(open(gp)) if gp and os.path.exists(gp) else {}
    crc_fail = dict(crc_pass(rows, cases, golden))
    json.dump(golden, open(f"{out}/crc-golden.json", "w"), indent=1)
    sp = f"{out}/camera-spans.json"
    spans = json.load(open(sp)).get("spans", []) if os.path.exists(sp) else []
    last = max((int(r["idx"]) for r in rows), default=0)
    for r in rows:
        i = int(r["idx"])
        if r["cam"] in ("", "-") or r["cam"].startswith("UNTRUSTED") or r["group"] == "calib":
            continue
        if any(s["start"] <= i <= (s["end"] if s["end"] is not None else last) for s in spans):
            r["cam"] = "UNTRUSTED:" + r["cam"]
            rs = [x for x in r["reasons"].split("; ") if x and not x.startswith("webcam:")]
            if r["verdict"] == "FAIL" and not rs:
                r["verdict"] = "UNTRUSTED"
            r["reasons"] = "; ".join(rs)
    for r in rows:
        if r["idx"] in crc_fail and r["verdict"] == "PASS":
            r["verdict"] = "FAIL"
            r["reasons"] = crc_fail[r["idx"]]
    with open(f"{out}/results-final.tsv", "w") as f:
        f.write("\t".join(COLS) + "\n")
        for r in rows:
            f.write("\t".join(r.get(k, "") for k in COLS) + "\n")
    tab = {}
    for r in rows:
        g = tab.setdefault(r["group"], {})
        g[r["verdict"]] = g.get(r["verdict"], 0) + 1
    lines = [f"# display matrix {time.strftime('%F %T')}  kernel {os.uname().release} {os.uname().version}",
             f"cases {len(cases)}, run {len(rows)}"]
    for g, v in tab.items():
        lines.append(f"{g:9s} " + "  ".join(f"{k}={n}" for k, n in sorted(v.items())))
    cal = [r for r in rows if r["verdict"].startswith("CALIB")]
    if cal:
        ok = all(r["verdict"] == "CALIB-MATCH" for r in cal)
        lines.append(f"webcam calibration vs known results: {'OK' if ok else 'MISMATCH - camera verdicts untrusted'}")
        if not ok and os.path.exists(f"{out}/calib.json"):
            c = json.load(open(f"{out}/calib.json"))
            c["trusted"] = False
            json.dump(c, open(f"{out}/calib.json", "w"))
    for s in spans:
        lines.append(f"CAMERA UNTRUSTED cases {s['start']}..{s['end'] if s['end'] is not None else 'end'} "
                     f"(control failed {s['moved_at']}" + (f", restored {s['restored_at']})" if s.get("restored_at") else ", never restored)"))
    bgp = f"{out}/background.log"
    if os.path.exists(bgp):
        bl = open(bgp).read().splitlines()
        cnt = {}
        for x in bl:
            k = re.sub(r"\d+", "N", x.split("\t")[-1])[:90]
            cnt[k] = cnt.get(k, 0) + 1
        lines.append(f"== background kernel messages (other connectors, not case FAILs): {len(bl)}, see background.log")
        lines += [f"{n:5d} x {k}" for k, n in sorted(cnt.items(), key=lambda kv: -kv[1])]
    he = [r for r in rows if r["verdict"] == "HARNESS-ERROR"]
    if he:
        lines.append(f"!!! HARNESS-ERROR rows (harness bug, not DUT): {len(he)}")
        lines += [f"{r['idx']:>5} {r['conn']} {r['mode']}: {r['reasons']}" for r in he]
    lines.append("== FAIL")
    lines += [f"{r['idx']:>5} {r['group']:8s} {r['conn']} {r['mode']} bpc={r['bpc']} cf={r['cf']} p{r['plane']} "
              f"{r['fmt']} {r['mod']} {r['output']} {r['link']} cam={r['cam']}: {r['reasons']}"
              for r in rows if r["verdict"] in ("FAIL", "CALIB-MISMATCH")]
    open(f"{out}/summary.txt", "w").write("\n".join(lines) + "\n")
    print("\n".join(lines))


if __name__ == "__main__":
    sys.exit(main())
