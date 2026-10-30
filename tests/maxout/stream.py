#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""One looping network stream: HTTP -> demux -> parse -> rkvdec -> waylandsink (fullscreen on OUTPUT),
in ONE pipeline that loops with segment seeks (devices stay open, nothing restarts).
Optional side branches, both behind leaky queues and appsinks, so they can never stall playback:
  --npu MODEL LABELS : videorate -> RGA3 -> RGA2 -> RGB WxH -> appsink -> NPU (Teflon) in a worker thread,
                       every Nth frame also on the CPU (top-1 agreement, max abs diff, top-2 margins)
  --enc "CMD"        : raw NV12 -> appsink -> worker thread writes frames to CMD's stdin (VEPU580 rkvenc-enc);
                       frames are dropped while the encoder is busy; a dead encoder is restarted and counted.
Logs one line per second to LOG: rendered/dropped (fpsdisplaysink), loops, npu inf/s + latency + top label,
encoder frames/s, encoder restarts.
"""
import argparse, os, queue, signal, subprocess, sys, threading, time
import gi
gi.require_version("Gst", "1.0"); gi.require_version("GstApp", "1.0"); gi.require_version("GstVideo", "1.0")
from gi.repository import Gst, GLib, GstVideo

ap = argparse.ArgumentParser()
ap.add_argument("url"); ap.add_argument("output"); ap.add_argument("log")
ap.add_argument("--codec", default="h264"); ap.add_argument("--dec", help="v4l2 stateless decoder element (not needed with --source)")
ap.add_argument("--audio", help="alsasink device for this stream's audio")
ap.add_argument("--npu", nargs=2, metavar=("MODEL", "LABELS"))
ap.add_argument("--rga", nargs=2, metavar=("RGA3", "RGA2"))
ap.add_argument("--npu-fps", type=int, default=15); ap.add_argument("--cmp-every", type=int, default=30)
ap.add_argument("--enc", help="encoder command line reading raw NV12 on stdin")
ap.add_argument("--enc-sock", help="zero-copy: the --enc command listens on this unix socket for dma-buf frames "
                "(maxout/tools/rkvenc-enc -s); frames go RGA (hardware copy) -> dma-buf fd -> VEPU580, no CPU copy")
ap.add_argument("--source", help="GStreamer source description producing raw video (e.g. a camera chain) "
                "instead of the HTTP/demux/decoder chain; no looping")
ap.add_argument("--secs", type=int, default=300)
a = ap.parse_args()
Gst.init(None)
log = open(a.log, "w", buffering=1)
def L(s): log.write(f"{time.time():.3f} {s}\n")

demux = "matroskademux" if a.url.endswith((".mkv", ".webm")) else "qtdemux"
src = f"filesrc location={a.url}" if a.url.startswith("/") else f"souphttpsrc location={a.url}"
head = f"{a.source} ! " if a.source else None
desc = (f"{src} ! queue2 max-size-bytes=67108864 max-size-buffers=0 max-size-time=0 ! "
        f"{demux} name=d d. ! {a.codec}parse ! queue ! {a.dec} ! tee name=t "
        f"t. ! queue ! fpsdisplaysink name=fps text-overlay=false sync=true signal-fps-measurements=true "
        + ("video-sink=fakevideosink " if a.output == "none" else f"video-sink=\"waylandsink fullscreen=true fullscreen-output={a.output}\" "))
if head:   # live source: the fps branch must not wait on the pipeline clock
    desc = head + "tee name=t " + desc[desc.index("t. ! queue ! fpsdisplaysink"):].replace("sync=true", "sync=false", 1)
if a.npu:
    desc += (f"t. ! queue leaky=downstream max-size-buffers=1 ! videorate drop-only=true ! video/x-raw,framerate={a.npu_fps}/1 ! "
             f"{a.rga[0]} ! video/x-raw,format=NV12,width=960,height=540 ! {a.rga[1]} ! "
             f"video/x-raw,format=RGB,width=224,height=224 ! appsink name=npu emit-signals=true max-buffers=1 drop=true sync=false ")
if a.enc:
    # The RGA copies the decoded DMABuf frame into a system-memory NV12 buffer for the appsink. Without it the tee
    # would drop GstVideoMeta (appsink doesn't announce it, and a Python pad probe can't add it: the query isn't
    # writable there) and the v4l2 decoder refuses DMABuf caps without VideoMeta.
    conv = f"{a.rga[0]} ! video/x-raw,format=NV12 ! " if a.rga else ""
    if a.enc_sock:   # the RGA's CAPTURE buffers are exported as dma-bufs and handed to the encoder by fd
        conv = f"{a.rga[0]} capture-io-mode=dmabuf ! video/x-raw,format=NV12 ! "
        if a.source:  # the --source chain ends in its own RGA with capture-io-mode=dmabuf
            conv = ""
    desc += f"t. ! queue leaky=downstream max-size-buffers=2 ! {conv}appsink name=enc emit-signals=true max-buffers=1 drop=true sync=false "
if a.audio:
    desc += f"d. ! queue max-size-time=3000000000 max-size-buffers=0 max-size-bytes=0 ! decodebin ! audioconvert ! audioresample ! alsasink device={a.audio} "
L(f"PIPELINE {desc}")
pipe = Gst.parse_launch(desc)
st = dict(rendered=0, dropped=0, loops=0, npu_n=0, npu_err=0, npu_lat=[], cmp=0, agree=0, maxdiff=0,
          enc_in=0, enc_drop=0, enc_restarts=0, top="")

# fpsdisplaysink's counters restart from 0 after every flush seek (each loop), so accumulate them: a value
# lower than the previous one starts a new loop, and the previous total moves into the base.
cnt = dict(r_base=0, d_base=0, r_last=0, d_last=0)
def on_fps(el, fps, droprate, avg):
    r = el.get_property("frames-rendered"); d = el.get_property("frames-dropped")
    if r < cnt["r_last"] or d < cnt["d_last"]:
        cnt["r_base"] += cnt["r_last"]; cnt["d_base"] += cnt["d_last"]
    cnt["r_last"], cnt["d_last"] = r, d
    st["rendered"] = cnt["r_base"] + r; st["dropped"] = cnt["d_base"] + d
pipe.get_by_name("fps").connect("fps-measurements", on_fps)

# ---- NPU worker
if a.npu:
    import numpy as np
    from ai_edge_litert import interpreter as litert
    labels = [l.strip() for l in open(a.npu[1])]
    npu_it = litert.Interpreter(model_path=a.npu[0], experimental_delegates=[litert.load_delegate("/usr/lib/teflon/libteflon.so")])
    cpu_it = litert.Interpreter(model_path=a.npu[0], num_threads=2)
    for it in (npu_it, cpu_it): it.allocate_tensors()
    ii = npu_it.get_input_details()[0]["index"]; oi = npu_it.get_output_details()[0]["index"]
    nq = queue.Queue(maxsize=1)
    def npu_sample(sink):
        s = sink.emit("pull-sample"); b = s.get_buffer()
        ok, m = b.map(Gst.MapFlags.READ)
        if ok:
            data = bytes(m.data); b.unmap(m)
            if len(data) >= 224 * 224 * 3:
                try: nq.put_nowait(data[:224 * 224 * 3])  # stride 672 = 224*3, tightly packed
                except queue.Full: pass
        return Gst.FlowReturn.OK
    pipe.get_by_name("npu").connect("new-sample", npu_sample)
    def npu_worker():
        while True:
            x = np.frombuffer(nq.get(), np.uint8).reshape(1, 224, 224, 3)
            t = time.perf_counter()
            try:
                npu_it.set_tensor(ii, x); npu_it.invoke()
            except Exception as e:
                st["npu_err"] += 1; L(f"NPUERROR {e}"); continue
            st["npu_lat"].append((time.perf_counter() - t) * 1000)
            y = npu_it.get_tensor(oi)[0].copy(); st["npu_n"] += 1
            st["top"] = f"{labels[int(np.argmax(y))].split(',')[0]}({int(y.max())})"
            if st["npu_n"] % a.cmp_every == 0:
                cpu_it.set_tensor(ii, x); cpu_it.invoke(); yc = cpu_it.get_tensor(oi)[0]
                st["cmp"] += 1; st["agree"] += int(np.argmax(y) == np.argmax(yc))
                d = int(np.max(np.abs(y.astype(int) - yc.astype(int)))); st["maxdiff"] = max(st["maxdiff"], d)
                s2, c2 = np.sort(y)[-2:], np.sort(yc)[-2:]
                L(f"CMP npu={labels[int(np.argmax(y))]!r} cpu={labels[int(np.argmax(yc))]!r} maxdiff={d} "
                  f"npu_top2={s2[1]},{s2[0]} cpu_top2={c2[1]},{c2[0]}")
    threading.Thread(target=npu_worker, daemon=True).start()

# ---- encoder worker
if a.enc and a.enc_sock:
    import socket, struct
    gi.require_version("GstAllocators", "1.0")
    from gi.repository import GstAllocators
    held = {}; hl = threading.Lock(); fid = [0]
    def start_enc():
        try: os.unlink(a.enc_sock)
        except FileNotFoundError: pass
        p = subprocess.Popen(a.enc, shell=True, stdout=open(a.log + ".enc.out", "ab") if "/dev/stdout" not in a.enc else None,
                             stderr=open(a.log + ".enc", "a"))
        for _ in range(100):
            if os.path.exists(a.enc_sock): break
            time.sleep(0.05)
        so = socket.socket(socket.AF_UNIX, socket.SOCK_SEQPACKET); so.connect(a.enc_sock)
        return p, so
    enc = list(start_enc())
    def acks():
        while True:
            try:
                d = enc[1].recv(8)
            except OSError:
                d = b""
            if len(d) < 8:
                time.sleep(0.2); continue
            with hl: held.pop(struct.unpack("=Q", d)[0], None)   # releases the buffer back to the RGA pool
    threading.Thread(target=acks, daemon=True).start()
    def enc_sample(sink):
        smp = sink.emit("pull-sample"); b = smp.get_buffer()
        mem = b.peek_memory(0)
        if not GstAllocators.is_dmabuf_memory(mem):
            st["enc_drop"] += 1; return Gst.FlowReturn.OK
        vm = GstVideo.buffer_get_video_meta(b)
        stride = vm.stride[0] if vm else smp.get_caps().get_structure(0).get_value("width")
        off = mem.offset + (vm.offset[0] if vm else 0)
        with hl:
            if len(held) >= 3:   # encoder busy: drop this frame (never block the playback tee)
                st["enc_drop"] += 1; return Gst.FlowReturn.OK
            fid[0] += 1; held[fid[0]] = smp
        msg = struct.pack("=IIIIQ", 0x4e563132, off, stride, mem.maxsize + mem.offset, fid[0])
        try:
            enc[1].sendmsg([msg], [(socket.SOL_SOCKET, socket.SCM_RIGHTS, struct.pack("i", GstAllocators.dmabuf_memory_get_fd(mem)))])
            st["enc_in"] += 1
        except OSError:
            with hl: held.clear()
            L(f"ENCDIED rc={enc[0].poll()}"); st["enc_restarts"] += 1
            try: enc[:] = start_enc()
            except OSError as e: L(f"ENCRESTART failed {e}")
        return Gst.FlowReturn.OK
    pipe.get_by_name("enc").connect("new-sample", enc_sample)
elif a.enc:
    eq = queue.Queue(maxsize=2); enc = [None]
    def start_enc():
        enc[0] = subprocess.Popen(a.enc, shell=True, stdin=subprocess.PIPE, stdout=open(a.log + ".enc", "a"), stderr=subprocess.STDOUT)
    start_enc()
    def enc_sample(sink):
        s = sink.emit("pull-sample"); b = s.get_buffer()
        vm = GstVideo.buffer_get_video_meta(b)
        ok, m = b.map(Gst.MapFlags.READ)
        if ok:
            mv = memoryview(m.data)
            if vm:   # tightly packed NV12 for the encoder: Y then UV, w bytes per row
                w, h = vm.width, vm.height
                parts = []
                for p, rows in ((0, h), (1, h // 2)):
                    off, st = vm.offset[p], vm.stride[p]
                    if st == w:
                        parts.append(mv[off:off + w * rows])
                    else:
                        parts.extend(mv[off + r * st:off + r * st + w] for r in range(rows))
                data = b"".join(parts)
            else:
                data = bytes(mv)
            del mv; b.unmap(m)
            try: eq.put_nowait(data)
            except queue.Full: st["enc_drop"] += 1
        return Gst.FlowReturn.OK
    encsink = pipe.get_by_name("enc")
    encsink.connect("new-sample", enc_sample)
    def enc_worker():
        while True:
            data = eq.get()
            try:
                enc[0].stdin.write(data); st["enc_in"] += 1
            except (BrokenPipeError, OSError, ValueError):
                L(f"ENCDIED rc={enc[0].poll()}"); st["enc_restarts"] += 1; time.sleep(0.5); start_enc()
    threading.Thread(target=enc_worker, daemon=True).start()

# ---- bus: loop with segment seeks
loop = GLib.MainLoop()
first = [True]
def on_msg(bus, msg):
    t = msg.type
    if t == Gst.MessageType.EOS:  # loop: flush-seek back to the start in the same pipeline (devices stay open)
        st["loops"] += 1
        ok = pipe.seek_simple(Gst.Format.TIME, Gst.SeekFlags.FLUSH | Gst.SeekFlags.KEY_UNIT, 0)
        L(f"LOOP {st['loops']} seek={'ok' if ok else 'FAILED'}")
    elif t == Gst.MessageType.ERROR:
        e, dbg = msg.parse_error(); L(f"ERROR {e.message} {dbg}"); loop.quit()
    elif t == Gst.MessageType.WARNING:
        e, dbg = msg.parse_warning(); L(f"WARNING {e.message}")
    return True
bus = pipe.get_bus(); bus.add_signal_watch(); bus.connect("message", on_msg)

t0 = time.time(); last = dict(r=0, n=0, e=0)
def tick():
    lat = st["npu_lat"]; st["npu_lat"] = []
    L(f"SEC rendered={st['rendered']} dropped={st['dropped']} fps={st['rendered']-last['r']} loops={st['loops']} "
      f"npu_inf/s={st['npu_n']-last['n']} npu_lat={(sum(lat)/len(lat) if lat else 0):.1f} npu_top={st['top']} "
      f"npu_err={st['npu_err']} cmp={st['agree']}/{st['cmp']} maxdiff={st['maxdiff']} "
      f"enc_fps={st['enc_in']-last['e']} enc_drop={st['enc_drop']} enc_restarts={st['enc_restarts']}")
    last.update(r=st["rendered"], n=st["npu_n"], e=st["enc_in"])
    if time.time() - t0 >= a.secs: loop.quit(); return False
    return True
GLib.timeout_add(1000, tick)
signal.signal(signal.SIGTERM, lambda *_: GLib.idle_add(loop.quit)); signal.signal(signal.SIGINT, lambda *_: GLib.idle_add(loop.quit))
pipe.set_state(Gst.State.PLAYING)
loop.run()
tick()
L(f"TOTAL rendered={st['rendered']} dropped={st['dropped']} loops={st['loops']} npu={st['npu_n']} npu_err={st['npu_err']} "
  f"cmp={st['agree']}/{st['cmp']} maxdiff={st['maxdiff']} enc_frames={st['enc_in']} enc_drop={st['enc_drop']} enc_restarts={st['enc_restarts']}")
pipe.set_state(Gst.State.NULL)
if a.enc and enc[0]:
    try: enc[0].stdin.close(); enc[0].wait(5)
    except Exception: enc[0].kill()
os._exit(0)
