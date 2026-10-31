#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0
"""Minimal atomic KMS client (ctypes on libdrm, libgbm, libEGL, libGLESv2; no compiler needed).

  kmsctl.py list                       JSON: connectors (modes, props, EDID), crtcs, planes (format x modifier)
  kmsctl.py show --head SPEC [--head SPEC] [--test-only] [--hold SECS]
      SPEC = conn=<id|name>,mode=<index>|timing=CLOCK/hd:hss:hse:ht/vd:vss:vse:vt/FLAGS[,crtc=<id>][,plane=<id>][,fmt=XR24][,mod=linear|auto|0x...]
             [,pattern=bars|white|black|grey][,code=<n>][,prop:<name>=<value>]... [,prop:crtc:<name>=<v>]
             prop value hdr:pq|hlg|sdr|none builds an HDR_OUTPUT_METADATA blob
      Extra planes:  --plane conn=<name>,plane=<id>,fmt=NV12,mod=linear[,x=..,y=..,w=..,h=..]
  After the commit it prints one JSON line ({"ok":..}) and keeps the state until SIGTERM/stdin EOF or --hold.
Linear buffers are dumb buffers filled from Python; non-linear (AFBC) buffers are allocated with GBM and
drawn by the GPU (EGLImage + FBO + scissored clears). Every head disables all planes and CRTCs it does not use.
"""
import ctypes as C, ctypes.util, json, mmap, os, select, signal, struct, sys, time

u8, u16, u32, u64, i32 = C.c_uint8, C.c_uint16, C.c_uint32, C.c_uint64, C.c_int
P = C.POINTER


class ModeInfo(C.Structure):
    _fields_ = [("clock", u32), ("hdisplay", u16), ("hsync_start", u16), ("hsync_end", u16), ("htotal", u16),
                ("hskew", u16), ("vdisplay", u16), ("vsync_start", u16), ("vsync_end", u16), ("vtotal", u16),
                ("vscan", u16), ("vrefresh", u32), ("flags", u32), ("type", u32), ("name", C.c_char * 32)]


class Res(C.Structure):
    _fields_ = [("count_fbs", i32), ("fbs", P(u32)), ("count_crtcs", i32), ("crtcs", P(u32)),
                ("count_connectors", i32), ("connectors", P(u32)), ("count_encoders", i32), ("encoders", P(u32)),
                ("min_width", u32), ("max_width", u32), ("min_height", u32), ("max_height", u32)]


class Connector(C.Structure):
    _fields_ = [("connector_id", u32), ("encoder_id", u32), ("connector_type", u32), ("connector_type_id", u32),
                ("connection", i32), ("mmWidth", u32), ("mmHeight", u32), ("subpixel", i32),
                ("count_modes", i32), ("modes", P(ModeInfo)), ("count_props", i32), ("props", P(u32)),
                ("prop_values", P(u64)), ("count_encoders", i32), ("encoders", P(u32))]


class Encoder(C.Structure):
    _fields_ = [("encoder_id", u32), ("encoder_type", u32), ("crtc_id", u32), ("possible_crtcs", u32),
                ("possible_clones", u32)]


class PlaneRes(C.Structure):
    _fields_ = [("count_planes", u32), ("planes", P(u32))]


class Plane(C.Structure):
    _fields_ = [("count_formats", u32), ("formats", P(u32)), ("plane_id", u32), ("crtc_id", u32), ("fb_id", u32),
                ("crtc_x", u32), ("crtc_y", u32), ("x", u32), ("y", u32), ("possible_crtcs", u32), ("gamma_size", u32)]


class ObjProps(C.Structure):
    _fields_ = [("count_props", u32), ("props", P(u32)), ("prop_values", P(u64))]


class PropEnum(C.Structure):
    _fields_ = [("value", u64), ("name", C.c_char * 32)]


class Prop(C.Structure):
    _fields_ = [("prop_id", u32), ("flags", u32), ("name", C.c_char * 32), ("count_values", i32), ("values", P(u64)),
                ("count_enums", i32), ("enums", P(PropEnum)), ("count_blobs", i32), ("blob_ids", P(u32))]


class Blob(C.Structure):
    _fields_ = [("id", u32), ("length", u32), ("data", C.c_void_p)]


def lib(name, ver):
    return C.CDLL(f"lib{name}.so.{ver}", use_errno=True)


drm = lib("drm", 2)
for fn, res, args in [
        ("drmModeGetResources", P(Res), [i32]), ("drmModeGetConnector", P(Connector), [i32, u32]),
        ("drmModeGetConnectorCurrent", P(Connector), [i32, u32]),
        ("drmModeGetEncoder", P(Encoder), [i32, u32]), ("drmModeGetPlaneResources", P(PlaneRes), [i32]),
        ("drmModeGetPlane", P(Plane), [i32, u32]), ("drmModeObjectGetProperties", P(ObjProps), [i32, u32, u32]),
        ("drmModeGetProperty", P(Prop), [i32, u32]), ("drmModeGetPropertyBlob", P(Blob), [i32, u32]),
        ("drmSetClientCap", i32, [i32, u64, u64]), ("drmModeAtomicAlloc", C.c_void_p, []),
        ("drmModeAtomicAddProperty", i32, [C.c_void_p, u32, u32, u64]),
        ("drmModeAtomicCommit", i32, [i32, C.c_void_p, u32, C.c_void_p]),
        ("drmModeCreatePropertyBlob", i32, [i32, C.c_void_p, C.c_size_t, P(u32)]),
        ("drmModeCreateDumbBuffer", i32, [i32, u32, u32, u32, u32, P(u32), P(u32), P(u64)]),
        ("drmModeMapDumbBuffer", i32, [i32, u32, P(u64)]),
        ("drmModeAddFB2WithModifiers", i32, [i32, u32, u32, u32, P(u32), P(u32), P(u32), P(u64), P(u32), u32]),
        ("drmPrimeFDToHandle", i32, [i32, i32, P(u32)])]:
    f = getattr(drm, fn)
    f.restype, f.argtypes = res, args

OBJ_CRTC, OBJ_CONNECTOR, OBJ_PLANE = 0xcccccccc, 0xc0c0c0c0, 0xeeeeeeee
TEST_ONLY, ALLOW_MODESET = 0x100, 0x400
AFBC = 0x08 << 56   # DRM_FORMAT_MOD_ARM_AFBC(0): vendor ARM (0x08), type AFBC (0)
CONN_TYPES = {10: "DP", 11: "HDMI-A", 12: "HDMI-B", 14: "eDP", 3: "DVI-I", 2: "DVI-D", 15: "Virtual", 18: "Writeback"}


def fourcc(s):
    s = (s + "    ")[:4]
    return ord(s[0]) | ord(s[1]) << 8 | ord(s[2]) << 16 | ord(s[3]) << 24


def fcc_str(v):
    return "".join(chr((v >> (8 * i)) & 0xff) for i in range(4)).strip()


def err(rc):
    e = -rc if rc < 0 and rc != -1 else C.get_errno()
    return f"{os.strerror(e)} ({e})" if e else f"rc={rc}"


def open_card():
    for n in sorted(os.listdir("/dev/dri")):
        if not n.startswith("card"):
            continue
        fd = os.open(f"/dev/dri/{n}", os.O_RDWR | os.O_CLOEXEC)
        r = drm.drmModeGetResources(fd)
        if r and r[0].count_connectors > 0:
            drm.drmSetClientCap(fd, 2, 1)  # universal planes
            drm.drmSetClientCap(fd, 3, 1)  # atomic
            return fd, n
        os.close(fd)
    sys.exit("no KMS device with connectors")


def props(fd, oid, otype):
    """name -> dict(id, value, flags, enums{name:value}, range)"""
    out = {}
    op = drm.drmModeObjectGetProperties(fd, oid, otype)
    if not op:
        return out
    for i in range(op[0].count_props):
        p = drm.drmModeGetProperty(fd, op[0].props[i])
        if not p:
            continue
        p = p[0]
        d = {"id": p.prop_id, "value": op[0].prop_values[i], "flags": p.flags}
        if p.count_enums:
            d["enums"] = {p.enums[j].name.decode(): p.enums[j].value for j in range(p.count_enums)}
        if p.flags & 2 and p.count_values == 2:  # DRM_MODE_PROP_RANGE
            d["range"] = [p.values[0], p.values[1]]
        out[p.name.decode()] = d
    return out


def blob(fd, bid):
    if not bid:
        return b""
    b = drm.drmModeGetPropertyBlob(fd, bid)
    return C.string_at(b[0].data, b[0].length) if b else b""


def in_formats(data):
    """IN_FORMATS blob -> {fourcc: [modifier, ...]}"""
    if len(data) < 24:
        return {}
    _v, _f, nf, foff, nm, moff = struct.unpack_from("<6I", data)
    fmts = struct.unpack_from(f"<{nf}I", data, foff)
    out = {fcc_str(f): [] for f in fmts}
    for i in range(nm):
        bits, off, _pad, mod = struct.unpack_from("<QIIQ", data, moff + 24 * i)
        for b in range(64):
            if bits >> b & 1 and off + b < nf:
                out[fcc_str(fmts[off + b])].append(mod)
    return out


def mode_dict(m):
    return {k: getattr(m, k) for k, _ in ModeInfo._fields_ if k != "name"} | {"name": m.name.decode(errors="replace")}


RAW_MODES = {}


def enumerate_all(fd, probe=True):
    """probe=False uses the cached connector state (no DDC/EDID re-read, no hotplug side effects)."""
    r = drm.drmModeGetResources(fd)[0]
    getc = drm.drmModeGetConnector if probe else drm.drmModeGetConnectorCurrent
    crtcs = [r.crtcs[i] for i in range(r.count_crtcs)]
    out = {"crtcs": crtcs, "connectors": [], "planes": []}
    for i in range(r.count_connectors):
        c = getc(fd, r.connectors[i])[0]
        RAW_MODES[c.connector_id] = [ModeInfo.from_buffer_copy(c.modes[j]) for j in range(c.count_modes)]
        name = f"{CONN_TYPES.get(c.connector_type, 'Unknown')}-{c.connector_type_id}"
        pc = 0
        for j in range(c.count_encoders):
            e = drm.drmModeGetEncoder(fd, c.encoders[j])
            if e:
                pc |= e[0].possible_crtcs
        pr = props(fd, c.connector_id, OBJ_CONNECTOR)
        out["connectors"].append({
            "id": c.connector_id, "name": name, "connected": c.connection == 1,
            "possible_crtcs": [crtcs[b] for b in range(len(crtcs)) if pc >> b & 1],
            "modes": [mode_dict(c.modes[j]) for j in range(c.count_modes)],
            "edid": blob(fd, pr.get("EDID", {}).get("value", 0)).hex(),
            "props": {k: {kk: vv for kk, vv in v.items() if kk != "flags"} for k, v in pr.items() if k != "EDID"}})
    pres = drm.drmModeGetPlaneResources(fd)[0]
    for i in range(pres.count_planes):
        p = drm.drmModeGetPlane(fd, pres.planes[i])[0]
        pr = props(fd, p.plane_id, OBJ_PLANE)
        fm = in_formats(blob(fd, pr.get("IN_FORMATS", {}).get("value", 0))) or \
            {fcc_str(p.formats[j]): [0] for j in range(p.count_formats)}
        typ = {v: k for k, v in pr.get("type", {}).get("enums", {}).items()}.get(pr.get("type", {}).get("value"), "?")
        out["planes"].append({"id": p.plane_id, "type": typ,
                              "possible_crtcs": [crtcs[b] for b in range(len(crtcs)) if p.possible_crtcs >> b & 1],
                              "formats": {f: [hex(m) for m in ms] for f, ms in fm.items()},
                              "zpos": pr.get("zpos", {}).get("value"), "crtc_id": p.crtc_id})
    return out


# ---------------------------------------------------------------- patterns
PAL = {"W": (1, 1, 1), "Y": (1, 1, 0), "C": (0, 1, 1), "G": (0, 1, 0), "M": (1, 0, 1), "R": (1, 0, 0),
       "B": (0, 0, 1), "K": (0, 0, 0), "g": (.5, .5, .5)}
BARS = "WYCGMRBK"


def code_bits(code):
    code &= 0xfff
    return [(code >> i) & 1 for i in range(12)] + [((code * 7 + 3) >> i) & 1 for i in range(4)]


def pattern_rects(name, w, h, code=0):
    """[(x0, y0, x1, y1, (r, g, b))] in pixels, covering the frame. Layout shared with camcheck.py."""
    if name in ("white", "black", "grey"):
        return [(0, 0, w, h, PAL[{"white": "W", "black": "K", "grey": "g"}[name]])]
    rects = []
    y1, y2 = int(h * .55), int(h * .70)
    for i, c in enumerate(BARS):                       # 8 full-saturation colour bars
        rects.append((w * i // 8, 0, w * (i + 1) // 8, y1, PAL[c]))
    for i in range(16):                                # 16 black/white stripes (scramble/shift detector)
        rects.append((w * i // 16, y1, w * (i + 1) // 16, y2, PAL["W" if i % 2 == 0 else "K"]))
    bits = code_bits(code)                             # 2 x 8 cells: case id (12 bit) + check (4 bit)
    ym = (y2 + h) // 2
    for i, b in enumerate(bits):
        r, col = divmod(i, 8)
        rects.append((w * col // 8, y2 if r == 0 else ym, w * (col + 1) // 8, ym if r == 0 else h,
                      PAL["W" if b else "K"]))
    return rects


# pixel packers for dumb buffers: fmt -> (bpp, function(r, g, b in 0..1) -> bytes)
def _p32(order, bits):
    m = (1 << bits) - 1

    def f(r, g, b):
        c = {"r": round(r * m), "g": round(g * m), "b": round(b * m)}
        v = (c[order[0]] << (2 * bits)) | (c[order[1]] << bits) | c[order[2]]
        if bits == 8:
            v |= 0xff << 24
        else:
            v |= 3 << 30
        return struct.pack("<I", v)
    return f


def _p565(order):
    def f(r, g, b):
        hi, lo = (r, b) if order == "r" else (b, r)
        return struct.pack("<H", round(hi * 31) << 11 | round(g * 63) << 5 | round(lo * 31))
    return f


PACK = {"XR24": (32, _p32("rgb", 8)), "AR24": (32, _p32("rgb", 8)), "XB24": (32, _p32("bgr", 8)),
        "AB24": (32, _p32("bgr", 8)), "XR30": (32, _p32("rgb", 10)), "AR30": (32, _p32("rgb", 10)),
        "XB30": (32, _p32("bgr", 10)), "AB30": (32, _p32("bgr", 10)),
        "RG24": (24, lambda r, g, b: bytes((round(b * 255), round(g * 255), round(r * 255)))),
        "BG24": (24, lambda r, g, b: bytes((round(r * 255), round(g * 255), round(b * 255)))),
        "RG16": (16, _p565("r")), "BG16": (16, _p565("b"))}


def fill_dumb(mm, pitch, w, h, fmt, rects):
    bpp, pk = PACK[fmt]
    bands = sorted({r[1] for r in rects} | {r[3] for r in rects})
    for y0, y1 in zip(bands, bands[1:]):
        row = bytearray(pitch)
        for x0, ry0, x1, ry1, rgb in rects:
            if ry0 <= y0 and ry1 >= y1:
                px = pk(*rgb)
                row[x0 * bpp // 8:x1 * bpp // 8] = px * (x1 - x0)
        row = bytes(row[:pitch])
        mm[y0 * pitch:y1 * pitch] = row * (y1 - y0)


# ---------------------------------------------------------------- GBM + EGL (non-linear modifiers)
class Gpu:
    def __init__(self, fd):
        self.gbm = lib("gbm", 1)
        self.gbm.gbm_create_device.restype = C.c_void_p
        self.gbm.gbm_create_device.argtypes = [i32]
        for fn, res, args in [("gbm_bo_get_modifier", u64, [C.c_void_p]), ("gbm_bo_get_plane_count", i32, [C.c_void_p]),
                              ("gbm_bo_get_handle_for_plane", u64, [C.c_void_p, i32]),
                              ("gbm_bo_get_stride_for_plane", u32, [C.c_void_p, i32]),
                              ("gbm_bo_get_offset", u32, [C.c_void_p, i32]), ("gbm_bo_get_fd", i32, [C.c_void_p])]:
            f = getattr(self.gbm, fn)
            f.restype, f.argtypes = res, args
        self.dev = self.gbm.gbm_create_device(fd)
        if not self.dev:
            raise RuntimeError("gbm_create_device failed")
        self.egl, self.gl = lib("EGL", 1), lib("GLESv2", 2)
        e = self.egl
        e.eglGetProcAddress.restype, e.eglGetProcAddress.argtypes = C.c_void_p, [C.c_char_p]
        e.eglGetPlatformDisplay.restype = C.c_void_p
        e.eglGetPlatformDisplay.argtypes = [u32, C.c_void_p, C.c_void_p]
        e.eglInitialize.argtypes = [C.c_void_p, P(i32), P(i32)]
        e.eglCreateContext.restype = C.c_void_p
        e.eglCreateContext.argtypes = [C.c_void_p, C.c_void_p, C.c_void_p, P(i32)]
        e.eglMakeCurrent.argtypes = [C.c_void_p, C.c_void_p, C.c_void_p, C.c_void_p]
        self.dpy = e.eglGetPlatformDisplay(0x31D7, self.dev, None)  # EGL_PLATFORM_GBM_KHR
        if not self.dpy or not e.eglInitialize(self.dpy, None, None):
            raise RuntimeError("eglInitialize failed")
        e.eglBindAPI(0x30A0)
        ctx = e.eglCreateContext(self.dpy, None, None, (i32 * 3)(0x3098, 2, 0x3038))
        if not ctx or not e.eglMakeCurrent(self.dpy, None, None, ctx):
            raise RuntimeError("EGL surfaceless context failed")
        self.mkimg = C.CFUNCTYPE(C.c_void_p, C.c_void_p, C.c_void_p, u32, C.c_void_p, P(i32))(
            e.eglGetProcAddress(b"eglCreateImageKHR"))
        self.rbstorage = C.CFUNCTYPE(None, u32, C.c_void_p)(
            e.eglGetProcAddress(b"glEGLImageTargetRenderbufferStorageOES"))
        for fn in ("glClearColor",):
            getattr(self.gl, fn).argtypes = [C.c_float] * 4

    def bo(self, w, h, fmt, mod):
        mods = (u64 * 1)(mod)
        g = self.gbm
        bo = None
        if hasattr(g, "gbm_bo_create_with_modifiers2"):
            g.gbm_bo_create_with_modifiers2.restype = C.c_void_p
            g.gbm_bo_create_with_modifiers2.argtypes = [C.c_void_p, u32, u32, u32, P(u64), u32, u32]
            bo = g.gbm_bo_create_with_modifiers2(self.dev, w, h, fourcc(fmt), mods, 1, 1 | 4)  # SCANOUT|RENDERING
        if not bo:
            g.gbm_bo_create_with_modifiers.restype = C.c_void_p
            g.gbm_bo_create_with_modifiers.argtypes = [C.c_void_p, u32, u32, u32, P(u64), u32]
            bo = g.gbm_bo_create_with_modifiers(self.dev, w, h, fourcc(fmt), mods, 1)
        if not bo:
            raise RuntimeError(f"GBM cannot allocate {fmt} modifier {mod:#x}")
        got = g.gbm_bo_get_modifier(bo)
        if got != mod:
            raise RuntimeError(f"GBM returned modifier {got:#x}, wanted {mod:#x}")
        n = g.gbm_bo_get_plane_count(bo)
        planes = [(g.gbm_bo_get_handle_for_plane(bo, i) & 0xffffffff, g.gbm_bo_get_stride_for_plane(bo, i),
                   g.gbm_bo_get_offset(bo, i)) for i in range(n)]
        return bo, planes

    def draw(self, bo, w, h, fmt, mod, planes, rects):
        dfd = self.gbm.gbm_bo_get_fd(bo)
        a = [0x3057, w, 0x3056, h, 0x3271, fourcc(fmt), 0x3272, dfd, 0x3273, planes[0][2], 0x3274, planes[0][1],
             0x3443, mod & 0xffffffff, 0x3444, mod >> 32, 0x3038]
        a = [x - (1 << 32) if x >= 1 << 31 else x for x in a]
        img = self.mkimg(self.dpy, None, 0x3270, None, (i32 * len(a))(*a))
        os.close(dfd)
        if not img:
            raise RuntimeError(f"eglCreateImage failed for {fmt} {mod:#x}")
        gl = self.gl
        rb, fb = u32(), u32()
        gl.glGenRenderbuffers(1, C.byref(rb))
        gl.glBindRenderbuffer(0x8D41, rb)
        self.rbstorage(0x8D41, img)
        gl.glGenFramebuffers(1, C.byref(fb))
        gl.glBindFramebuffer(0x8D40, fb)
        gl.glFramebufferRenderbuffer(0x8D40, 0x8CE0, 0x8D41, rb)
        st = gl.glCheckFramebufferStatus(0x8D40)
        if st != 0x8CD5:
            raise RuntimeError(f"GPU cannot render to {fmt} {mod:#x} (FBO status {st:#x})")
        gl.glViewport(0, 0, w, h)
        gl.glEnable(0x0C11)
        for x0, y0, x1, y1, rgb in rects:
            # FBO on an imported buffer: GL row 0 is the buffer's first row, which scans out at the top
            gl.glScissor(x0, y0, x1 - x0, y1 - y0)
            gl.glClearColor(*rgb, 1.0)
            gl.glClear(0x4000)
        gl.glFinish()


# ---------------------------------------------------------------- show
def parse_spec(s):
    d = {"props": {}}
    for kv in s.split(","):
        k, _, v = kv.partition("=")
        if k.startswith("prop:"):
            d["props"][k[5:]] = v
        else:
            d[k] = v
    return d


class Shower:
    def __init__(self):
        self.fd, self.card = open_card()
        self.info = enumerate_all(self.fd, probe=False)
        self.gpu = None
        self.keep = []
        self.leave_others = False

    @staticmethod
    def mode_index(c, timing):
        """exact match of 'CLOCK/hd,hss,hse,ht/vd,vss,vse,vt/FLAGS' in the connector's current mode list"""
        clk, hs, vs, fl = timing.split("/")
        want = (int(clk), tuple(int(x) for x in hs.split(":")), tuple(int(x) for x in vs.split(":")), int(fl))
        for i, m in enumerate(RAW_MODES[c["id"]]):
            if (m.clock, (m.hdisplay, m.hsync_start, m.hsync_end, m.htotal),
                    (m.vdisplay, m.vsync_start, m.vsync_end, m.vtotal), m.flags) == want:
                return i
        raise RuntimeError(f"HARNESS: no mode with exact timing {timing} on {c['name']}")

    def conn(self, ref):
        for c in self.info["connectors"]:
            if str(c["id"]) == ref or c["name"] == ref:
                return c
        raise RuntimeError(f"no connector {ref}")

    def fb(self, w, h, fmt, mod, rects):
        h_, p_, o_, m_ = (u32 * 4)(), (u32 * 4)(), (u32 * 4)(), (u64 * 4)()
        if mod == 0:
            if fmt not in PACK:
                raise RuntimeError(f"no Python filler for linear {fmt} (use modetest)")
            bpp = PACK[fmt][0]
            hd, pitch, size, off = u32(), u32(), u64(), u64()
            rc = drm.drmModeCreateDumbBuffer(self.fd, w, h, bpp, 0, C.byref(hd), C.byref(pitch), C.byref(size))
            if rc:
                raise RuntimeError("CREATE_DUMB: " + err(rc))
            drm.drmModeMapDumbBuffer(self.fd, hd, C.byref(off))
            mm = mmap.mmap(self.fd, size.value, mmap.MAP_SHARED, mmap.PROT_WRITE | mmap.PROT_READ, offset=off.value)
            fill_dumb(mm, pitch.value, w, h, fmt, rects)
            self.keep.append(mm)
            planes = [(hd.value, pitch.value, 0)]
        else:
            if self.gpu is None:
                self.gpu = Gpu(self.fd)
            bo, planes = self.gpu.bo(w, h, fmt, mod)
            self.keep.append(bo)
            self.gpu.draw(bo, w, h, fmt, mod, planes, rects)
        for i, (hh, pp, oo) in enumerate(planes):
            h_[i], p_[i], o_[i], m_[i] = hh, pp, oo, mod
        fid = u32()
        rc = drm.drmModeAddFB2WithModifiers(self.fd, w, h, fourcc(fmt), h_, p_, o_, m_, C.byref(fid),
                                            2 if mod else 0)
        if rc:
            raise RuntimeError(f"ADDFB2 {fmt} {mod:#x}: " + err(rc))
        return fid.value

    def pick_mod(self, plane, fmt, mod):
        mods = [int(m, 16) for m in plane["formats"].get(fmt, [])]
        if not mods:
            raise RuntimeError(f"plane {plane['id']} has no format {fmt}")
        if mod in ("auto", None):   # linear, else the AFBC flavour compositors (mutter/panfrost) use first
            for want in (0, AFBC | 0x51, AFBC | 0x41, AFBC | 0x11, AFBC | 0x01):
                if want in mods:
                    return want
            return mods[0]
        m = 0 if mod == "linear" else int(mod, 0)
        if m not in mods:
            raise RuntimeError(f"plane {plane['id']} does not list {fmt} {m:#x}")
        return m

    def run(self, heads, extra, test_only, hold):
        req = drm.drmModeAtomicAlloc()
        used_crtcs, used_planes, used_conns, desc = set(), set(), set(), []

        def add(obj, otype, name, val):
            p = props(self.fd, obj, otype)
            if name not in p:
                raise RuntimeError(f"object {obj} has no property {name}")
            pr = p[name]
            if isinstance(val, str):
                if "enums" in pr:
                    if val not in pr["enums"]:
                        raise RuntimeError(f"{name}: no enum {val!r} (have {list(pr['enums'])})")
                    val = pr["enums"][val]
                else:
                    val = int(val, 0)
            drm.drmModeAtomicAddProperty(req, obj, pr["id"], val)

        planes = {p["id"]: p for p in self.info["planes"]}
        crtc_of = {}
        for h in heads:
            c = self.conn(h["conn"])
            if "timing" in h:
                h["mode"] = self.mode_index(c, h["timing"])
            m = c["modes"][int(h.get("mode", 0))]
            crtc = int(h["crtc"]) if "crtc" in h else next(x for x in c["possible_crtcs"] if x not in used_crtcs)
            used_crtcs.add(crtc)
            used_conns.add(c["id"])
            crtc_of[c["name"]] = crtc
            mi = RAW_MODES[c["id"]][int(h.get("mode", 0))]
            bid = u32()
            drm.drmModeCreatePropertyBlob(self.fd, C.byref(mi), C.sizeof(mi), C.byref(bid))
            add(crtc, OBJ_CRTC, "MODE_ID", bid.value)
            add(crtc, OBJ_CRTC, "ACTIVE", 1)
            add(c["id"], OBJ_CONNECTOR, "CRTC_ID", crtc)
            for k, v in h["props"].items():
                if k.startswith("crtc:"):
                    add(crtc, OBJ_CRTC, k[5:], v)
                elif v.startswith("hdr:"):
                    add(c["id"], OBJ_CONNECTOR, k, self.hdr_blob(v[4:]))
                else:
                    add(c["id"], OBJ_CONNECTOR, k, v)
            pid = int(h["plane"]) if "plane" in h else next(
                p["id"] for p in self.info["planes"] if p["type"] == "Primary" and crtc in p["possible_crtcs"])
            w, hh = m["hdisplay"], m["vdisplay"]
            fmt = h.get("fmt", "XR24")
            mod = self.pick_mod(planes[pid], fmt, h.get("mod"))
            fid = self.fb(w, hh, fmt, mod, pattern_rects(h.get("pattern", "bars"), w, hh, int(h.get("code", 0))))
            self.plane(add, pid, crtc, fid, 0, 0, w, hh, w, hh)
            used_planes.add(pid)
            desc.append({"conn": c["name"], "crtc": crtc, "plane": pid, "fmt": fmt, "mod": hex(mod), "mode": m})
        for e in extra:
            crtc = crtc_of[self.conn(e["conn"])["name"]]
            pid = int(e["plane"])
            m = next(d["mode"] for d in desc if d["crtc"] == crtc)
            w, hh = int(e.get("w", m["hdisplay"])), int(e.get("h", m["vdisplay"]))
            fmt = e.get("fmt", "XR24")
            mod = self.pick_mod(planes[pid], fmt, e.get("mod"))
            fid = self.fb(w, hh, fmt, mod, pattern_rects(e.get("pattern", "bars"), w, hh, int(e.get("code", 0))))
            self.plane(add, pid, crtc, fid, int(e.get("x", 0)), int(e.get("y", 0)), w, hh, w, hh)
            used_planes.add(pid)
            desc.append({"plane": pid, "crtc": crtc, "fmt": fmt, "mod": hex(mod), "w": w, "h": hh})
        # everything not in this case is switched off; with --leave-others only what is on the case's CRTCs
        # (other outputs keep running untouched, e.g. DP stays as fbcon left it during an HDMI-only run)
        for p in self.info["planes"]:
            if p["id"] not in used_planes and (not self.leave_others or p["crtc_id"] in used_crtcs or not p["crtc_id"]):
                add(p["id"], OBJ_PLANE, "FB_ID", 0)
                add(p["id"], OBJ_PLANE, "CRTC_ID", 0)
        for c in self.info["connectors"]:
            if c["id"] not in used_conns and not self.leave_others and "CRTC_ID" in props(self.fd, c["id"], OBJ_CONNECTOR):
                add(c["id"], OBJ_CONNECTOR, "CRTC_ID", 0)
        for crtc in self.info["crtcs"]:
            if crtc not in used_crtcs and not self.leave_others:
                add(crtc, OBJ_CRTC, "ACTIVE", 0)
                add(crtc, OBJ_CRTC, "MODE_ID", 0)
        rc = drm.drmModeAtomicCommit(self.fd, req, ALLOW_MODESET | (TEST_ONLY if test_only else 0), None)
        print(json.dumps({"ok": rc == 0, "err": "" if rc == 0 else err(rc), "test_only": test_only, "heads": desc}),
              flush=True)
        if rc or test_only:
            return 1 if rc else 0
        signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
        end = time.time() + hold if hold else None
        while end is None or time.time() < end:
            r, _, _ = select.select([sys.stdin], [], [], 0.5)
            if r and not sys.stdin.buffer.read1(4096):
                break
        return 0

    def hdr_blob(self, eotf):
        """struct hdr_output_metadata, static metadata type 1, BT.2020 primaries, D65, 1000/0.005 nits"""
        if eotf == "none":
            return 0
        e = {"sdr": 0, "hdr": 1, "pq": 2, "hlg": 3}[eotf]
        prim = [(35400, 14600), (8500, 39850), (6550, 2300)]  # G, B, R in 0.00002 units (CTA-861 order)
        data = struct.pack("<IBB6H2H4H", 0, e, 0, *[v for p in prim for v in p], 15635, 16450, 1000, 50, 1000, 400)
        data += b"\0" * (32 - len(data))
        bid = u32()
        rc = drm.drmModeCreatePropertyBlob(self.fd, data, len(data), C.byref(bid))
        if rc:
            raise RuntimeError("HDR blob: " + err(rc))
        return bid.value

    @staticmethod
    def plane(add, pid, crtc, fid, x, y, w, h, sw, sh):
        for k, v in (("FB_ID", fid), ("CRTC_ID", crtc), ("CRTC_X", x), ("CRTC_Y", y), ("CRTC_W", w), ("CRTC_H", h),
                     ("SRC_X", 0), ("SRC_Y", 0), ("SRC_W", sw << 16), ("SRC_H", sh << 16)):
            add(pid, OBJ_PLANE, k, v)


def main(argv):
    if not argv or argv[0] not in ("list", "show"):
        sys.exit(__doc__)
    if argv[0] == "list":
        fd, card = open_card()
        print(json.dumps(enumerate_all(fd) | {"card": card}))
        return 0
    heads, extra, test_only, hold, leave = [], [], False, 0, False
    it = iter(argv[1:])
    for a in it:
        if a == "--head":
            heads.append(parse_spec(next(it)))
        elif a == "--plane":
            extra.append(parse_spec(next(it)))
        elif a == "--leave-others":
            leave = True
        elif a == "--test-only":
            test_only = True
        elif a == "--hold":
            hold = float(next(it))
        else:
            sys.exit(f"unknown argument {a}")
    try:
        sh_ = Shower()
        sh_.leave_others = leave
        return sh_.run(heads, extra, test_only, hold)
    except (RuntimeError, StopIteration, IndexError, KeyError) as e:
        print(json.dumps({"ok": False, "err": f"setup: {e!r}", "test_only": test_only}), flush=True)
        return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
