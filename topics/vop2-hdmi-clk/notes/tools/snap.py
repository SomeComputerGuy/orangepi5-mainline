#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0
"""Clock / polarity snapshot of the running HDMI0 output (root). Usage: snap.py <outdir>
Writes clk.txt (clk_summary subset), vblank.json (measured pixel clock), vop.txt (VOP2 SYS + VP0
words of interest from debugfs active_regs), and - only when HDMI0 is enabled - hdmiregs.txt and
GRF VO1_CON0. Prints one summary line."""
import json, mmap, os, re, struct, subprocess, sys

D = "/sys/kernel/debug"


def rd(p):
    try:
        return open(p).read()
    except OSError as e:
        return f"<{e}>"


def hdmi_on():
    clk = rd(f"{D}/clk/clk_summary")
    en = next((int(l.split()[1]) for l in clk.splitlines() if l.split()[:1] == ["dclk_vop0"]), 0)
    st = rd(f"{D}/dri/0/state")
    m = re.search(r"connector\[\d+\]: HDMI-A-1\n\tcrtc=(\S+)", st)
    return en > 0 and m and m[1] != "(null)"


def vopword(regs, addr):
    for l in regs.splitlines():
        m = re.match(r"([0-9a-f]{8}):\s+(.*)", l)
        if m and int(m[1], 16) <= addr < int(m[1], 16) + 16:
            return int(m[2].split()[(addr - int(m[1], 16)) // 4], 16)
    return None


def main(out):
    os.makedirs(out, exist_ok=True)
    clk = rd(f"{D}/clk/clk_summary")
    sel = [l for l in clk.splitlines() if re.search(r"dclk_vop|hdmiphy|pll_v0pll|^\s*(gpll|cpll|v0pll|aupll)\s", l)]
    open(f"{out}/clk.txt", "w").write("\n".join(sel) + "\n")
    dclk0 = next((int(l.split()[4]) for l in sel if l.split()[0] == "dclk_vop0"), 0)
    par = next((l.split()[0] for l in sel if l.split()[0] in ("dclk_vop0_src", "clk_hdmiphy_pixel0")
                and int(l.split()[1]) > 0), "?")
    vb = subprocess.run([sys.executable, "-I", "/var/tmp/wedge/vblank.py", "0", "4"], capture_output=True, text=True)
    open(f"{out}/vblank.json", "w").write(vb.stdout + vb.stderr)
    try:
        v = json.loads(vb.stdout)
    except ValueError:
        v = {}
    regs = rd(f"{D}/dri/0/vop2/active_regs")
    open(f"{out}/vop2_active_regs.txt", "w").write(regs)
    w = {k: vopword(regs, a) for k, a in (("DSP_IF_EN", 0xfdd90028), ("DSP_IF_CTRL", 0xfdd9002c),
                                          ("DSP_IF_POL", 0xfdd90030), ("VP0_CLK_CTRL", 0xfdd90c0c))}
    grf = None
    hr = "HDMI0 off"
    if hdmi_on():
        r = subprocess.run([sys.executable, "-I", "/var/tmp/wedge/hdmiregs.py"], capture_output=True, text=True)
        hr = r.stdout
        fd = os.open("/dev/mem", os.O_RDONLY | os.O_SYNC)
        m = mmap.mmap(fd, 0x1000, mmap.MAP_SHARED, mmap.PROT_READ, offset=0xfd5a8000)
        grf = struct.unpack_from("<I", m, 0)[0]
        m.close()
        os.close(fd)
    open(f"{out}/hdmiregs.txt", "w").write(hr)
    g = lambda n: next((l.split()[-1] for l in hr.splitlines() if l.startswith(n)), "-")
    s = dict(dclk_vop0=dclk0, dclk_parent=par, meas_khz=v.get("measured_pixclk_khz"),
             mode_khz=v.get("mode", {}).get("clock_khz"), err_ppm=v.get("error_ppm"),
             vo1_con0=None if grf is None else f"0x{grf:08x}",
             **{k: (None if x is None else f"0x{x:08x}") for k, x in w.items()},
             LINK_CONFIG0=g("LINK_CONFIG0"), FLT_CONFIG1=g("FLT_CONFIG1"), VIF=g("VIDEO_INTERFACE_STATUS0"),
             MON0=g("VIDEO_MONITOR_STATUS0"), MON3=g("VIDEO_MONITOR_STATUS3"), MON6=g("VIDEO_MONITOR_STATUS6"))
    json.dump(s, open(f"{out}/snap.json", "w"))
    print(json.dumps(s))


if __name__ == "__main__":
    main(sys.argv[1])
