#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0
"""GNOME session display check (driven by ../gnome-check.sh, root).

For the running gnome-shell (gdm greeter or a user session): mutter DisplayConfig GetCurrentState +
PowerSaveMode (over the session's own bus, as the session user), then per connected connector the kernel
view (sysfs status/dpms, atomic state: connector -> active CRTC -> plane with a framebuffer) and, for the
connector under the webcam, a picture check (lit, not black). --modes additionally applies every mutter
mode of every monitor (temporary config) and checks each one the same way.
  gnomecheck.py check [--wake] [--modes] [--out DIR] [--calib calib.json]
  gnomecheck.py dbus state|wake|apply <connector> <mode-id>      (internal, runs as the session user)
"""
import json, os, subprocess, sys, time

HERE = os.path.dirname(os.path.abspath(__file__)) if "__file__" in globals() else "/"
sys.path.insert(0, HERE)

BUS, PATH, IFACE = "org.gnome.Mutter.DisplayConfig", "/org/gnome/Mutter/DisplayConfig", "org.gnome.Mutter.DisplayConfig"


# ---------------------------------------------------------------- session side (GLib)
def dbus_main(a):
    from gi.repository import Gio, GLib
    out, c = {}, []

    def call(method, args=None, iface=IFACE):
        return c[0].call_sync(BUS, PATH, iface, method, args, None, 0, 10000, None).unpack()
    try:
        c.append(Gio.bus_get_sync(Gio.BusType.SESSION, None))
        if a[0] == "wake":
            call("Set", GLib.Variant("(ssv)", (IFACE, "PowerSaveMode", GLib.Variant("i", 0))),
                 "org.freedesktop.DBus.Properties")
        out["power_save_mode"] = call("Get", GLib.Variant("(ss)", (IFACE, "PowerSaveMode")),
                                      "org.freedesktop.DBus.Properties")[0]
        serial, monitors, logical, props = call("GetCurrentState")
        out["serial"] = serial
        out["monitors"] = []
        for (conn, vendor, product, sn), modes, mprops in monitors:
            cur = [m for m in modes if m[6].get("is-current")]
            out["monitors"].append({"connector": conn, "vendor": vendor, "product": product,
                                    "current": cur[0][:4] if cur else None,
                                    "modes": [m[:4] for m in modes], "builtin": mprops.get("is-builtin", False)})
        out["logical"] = [{"x": x, "y": y, "scale": s, "transform": t, "primary": p,
                           "connectors": [m[0] for m in mons]} for x, y, s, t, p, mons, _ in logical]
        if a[0] == "apply":
            conn, mid = a[1], a[2]
            lms, x = [], 0
            for lm in out["logical"]:
                mons = []
                w = 0
                for cn in lm["connectors"]:
                    mon = next(m for m in out["monitors"] if m["connector"] == cn)
                    mode = mid if cn == conn else mon["current"][0]
                    w = max(w, next(m[1] for m in mon["modes"] if m[0] == mode))
                    mons.append((cn, mode, {}))
                lms.append((x, 0, 1.0, 0, lm["primary"], mons))
                x += w
            call("ApplyMonitorsConfig", GLib.Variant("(uua(iiduba(ssa{sv}))a{sv})", (serial, 1, lms, {})))
            out["applied"] = [conn, mid]
    except GLib.Error as e:
        out["error"] = e.message
    print(json.dumps(out))


# ---------------------------------------------------------------- root side
def mname(kernel_name):
    """mutter's connector name for a kernel connector (mutter says HDMI-1 for HDMI-A-1)"""
    return kernel_name.replace("HDMI-A-", "HDMI-").replace("HDMI-B-", "HDMI-")



def session():
    """(user, DBUS_SESSION_BUS_ADDRESS, mode) of the first gnome-shell"""
    for pid in sorted(int(p) for p in os.listdir("/proc") if p.isdigit()):
        try:
            cmd = open(f"/proc/{pid}/cmdline", "rb").read().split(b"\0")
            if not cmd[0].endswith(b"gnome-shell"):
                continue
            env = dict(kv.split(b"=", 1) for kv in open(f"/proc/{pid}/environ", "rb").read().split(b"\0") if b"=" in kv)
            uid = os.stat(f"/proc/{pid}").st_uid
        except OSError:
            continue
        import pwd
        return (pwd.getpwuid(uid).pw_name, env.get(b"DBUS_SESSION_BUS_ADDRESS", b"").decode(),
                "gdm" if b"--mode=gdm" in cmd else "user")
    return None


def as_session(sess, *args):
    user, addr, _ = sess
    # the source goes in on stdin: the session user (gdm) usually cannot read the checkout in a home directory
    r = subprocess.run(["runuser", "-u", user, "--", "env", f"DBUS_SESSION_BUS_ADDRESS={addr}", sys.executable,
                        "-I", "-", "dbus", *args], input=open(os.path.abspath(__file__)).read(),
                       capture_output=True, text=True, timeout=60, cwd="/")
    try:
        return json.loads(r.stdout)
    except ValueError:
        return {"error": (r.stderr or r.stdout).strip()[-300:]}


def kernel_view():
    import dmatrix
    st = dmatrix.parse_state(dmatrix.rd(f"{dmatrix.DBG}/state"))
    out = {}
    for d in sorted(os.listdir("/sys/class/drm")):
        if "-" not in d or not os.path.exists(f"/sys/class/drm/{d}/status"):
            continue
        name = d.split("-", 1)[1]
        status = dmatrix.rd(f"/sys/class/drm/{d}/status").strip()
        if status != "connected":
            continue
        cs = st.get(name, {})
        crtc = cs.get("crtc", "(null)")
        cr = st.get(crtc, {})
        planes = [n for n, o in st.items() if o.get("_type") == "plane" and o.get("crtc") == crtc
                  and o.get("fb", "0") not in ("0", "")]
        out[name] = {"dpms": dmatrix.rd(f"/sys/class/drm/{d}/dpms").strip(), "crtc": crtc,
                     "active": cr.get("active") == "1", "mode": cr.get("mode"), "planes": planes,
                     "output_bpc": cs.get("output_bpc"), "output_format": cs.get("output_format")}
    return out


def camera(out, tag, calib):
    import camcheck
    try:
        img = camcheck.load(camcheck.capture(f"{out}/{tag}"))
    except RuntimeError as e:
        return {"verdict": "ERROR", "err": str(e)}
    r = {"jpg": f"{out}/{tag}.jpg"}
    if not calib or "quad" not in calib:
        r.update(verdict="MANUAL")
        return r
    level, tex = camcheck.screen_stats(img, calib)
    th = calib.get("thresholds", camcheck.TH)
    r.update(level=round(level, 3), texture=round(tex, 3),
             verdict="LIT" if level >= th["black_frac"] or tex >= th["texture_min"] else "DARK")
    return r


def check(a):
    out = a[a.index("--out") + 1] if "--out" in a else "/var/tmp/testmatrix/gnome"
    os.makedirs(out, exist_ok=True)
    cp = a[a.index("--calib") + 1] if "--calib" in a else ""
    calib = json.load(open(cp)) if cp and os.path.exists(cp) else None
    cam_conn = os.environ.get("CAM_CONN", "")
    rows, fails = [], []
    sess = session()
    if not sess:
        print("FAIL no gnome-shell running")
        return 1
    print(f"session: user={sess[0]} mode={sess[2]}")
    m = as_session(sess, "wake" if "--wake" in a else "state")
    json.dump(m, open(f"{out}/mutter-state.json", "w"), indent=1)
    if "error" in m:
        fails.append(f"mutter DisplayConfig: {m['error']}")
    if m.get("power_save_mode", 0) != 0:
        fails.append(f"PowerSaveMode={m['power_save_mode']} (outputs blanked; rerun with --wake)")
    time.sleep(2)

    def one(tag, expect_mode=None):
        kv = kernel_view()
        res = []
        for name, k in kv.items():
            mon = next((x for x in m.get("monitors", []) if x["connector"] == mname(name)), None)
            inlog = any(mname(name) in lm["connectors"] for lm in m.get("logical", []))
            why = []
            if "error" not in m:
                if not mon:
                    why.append("not in mutter monitors")
                elif not mon["current"]:
                    why.append("mutter: no current mode")
                if not inlog:
                    why.append("not in a mutter logical monitor")
            if not k["active"]:
                why.append(f"CRTC {k['crtc']} inactive")
            if not k["planes"]:
                why.append("no plane with a framebuffer")
            if k["dpms"] != "On":
                why.append(f"dpms {k['dpms']}")
            if expect_mode and mname(name) == expect_mode[0] and k.get("mode") and \
                    k["mode"]["h"][0] != expect_mode[1]:
                why.append(f"kernel mode {k['mode']} != mutter {expect_mode[1:]}")
            cam = camera(out, f"{tag}-{name}", calib) if name == cam_conn else {}
            if cam.get("verdict") in ("DARK", "ERROR"):
                why.append(f"webcam: {cam['verdict']}")
            res.append((name, k, mon["current"] if mon else None, cam, why))
        return res

    for name, k, cur, cam, why in one("greeter"):
        line = (f"{'FAIL' if why or fails else 'PASS'}\tgreeter\t{name}\tmutter={cur}\tcrtc={k['crtc']} active={k['active']} "
                f"planes={','.join(k['planes'])} bpc={k['output_bpc']} fmt={k['output_format']}\tcam={cam.get('verdict', '-')}"
                f"\t{'; '.join(why + fails)}")
        rows.append(line)
    if "--modes" in a and "error" not in m:
        orig = {x["connector"]: x["current"][0] for x in m["monitors"] if x["current"]}
        for mon in m["monitors"]:
            for mode in mon["modes"]:
                r = as_session(sess, "apply", mon["connector"], mode[0])
                time.sleep(float(os.environ.get("SETTLE", "5")))
                why0 = [f"ApplyMonitorsConfig: {r['error']}"] if "error" in r else []
                for name, k, cur, cam, why in one(f"mode-{mon['connector']}-{mode[0]}", (mon["connector"], mode[1])):
                    if mname(name) != mon["connector"]:
                        continue
                    rows.append(f"{'FAIL' if why or why0 else 'PASS'}\tmode\t{name}\t{mode[0]}\tcrtc={k['crtc']} "
                                f"active={k['active']} bpc={k['output_bpc']} fmt={k['output_format']}\t"
                                f"cam={cam.get('verdict', '-')}\t{'; '.join(why0 + why)}")
                    print(rows[-1], flush=True)
            if mon["connector"] in orig:
                as_session(sess, "apply", mon["connector"], orig[mon["connector"]])
    open(f"{out}/gnome-check.tsv", "w").write("\n".join(rows) + "\n")
    print("\n".join(rows))
    nf = sum(r.startswith("FAIL") for r in rows) + (0 if rows else 1)
    print(f"== {len(rows)} checks, {nf} FAIL" + ("" if rows else " (no connected outputs)"))
    return 1 if nf else 0


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "dbus":  # sys.argv[0] is "-" when fed on stdin
        dbus_main(sys.argv[2:])
    elif len(sys.argv) > 1 and sys.argv[1] == "check":
        sys.exit(check(sys.argv[2:]))
    else:
        sys.exit(__doc__)
