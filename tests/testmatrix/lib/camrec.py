#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0
"""Continuous webcam recording for a test run, with per-case markers (GStreamer; pure Python otherwise).

  camrec.py run <dir>             supervisor: one pipeline owns the camera, restarts it when it dies (foreground)
  camrec.py status <dir>          is a recording running and fresh
  camrec.py span <dir> <verdict> <text>   finished case ending now (media-matrix.sh); event <dir> <text>
  camrec.py stop <dir>            stop the supervisor
  camrec.py selftest              marker / SRT / chapter / frame-pick tests (no camera, no GStreamer needed)

Pipeline: v4l2src (MJPEG 1920x1080) ! jpegparse ! videorate 5 fps ! tee
  A: splitmuxsink (matroska, ~30 min segments, MJPEG passthrough)  -> <dir>/run-NNN-SSS.mkv
  B: multifilesink, newest few JPEGs                                -> <dir>/frames/fNNNNN.jpg
camcheck.capture() takes its picture from branch B while the recording is fresh (the camera can only be
opened once). If the frames go stale, camcheck pauses the recorder (<dir>/pause), captures directly and
releases it; the supervisor then restarts the pipeline as new run-NNN files.

Markers use seconds on the concatenated recording (run-*.mkv in order): <dir>/cues.json is the source,
cases.srt, chapters.txt (ffmetadata) and cases.tsv (for tools/make-review-video.sh) are rewritten from it.
Env: CAM_DEV, CAM_NAME (see camcheck), REC_FPS (5), REC_SEGMENT_MIN (30), CAM_CAPS.
"""
import glob, json, os, shutil, signal, subprocess, sys, time

FPS = int(os.environ.get("REC_FPS", "5"))
SEG_MIN = float(os.environ.get("REC_SEGMENT_MIN", "30"))
STALE = 4.0          # seconds without a new frame = pipeline considered dead
KEEP = 6             # frames kept in frames/


def jread(p, default):
    try:
        return json.load(open(p))
    except (OSError, ValueError):
        return default


def jwrite(p, obj):
    with open(p + ".tmp", "w") as f:
        json.dump(obj, f)
    os.replace(p + ".tmp", p)


# ---------------------------------------------------------------- frames (reader side, used by camcheck)
def newest_frames(d):
    return sorted(glob.glob(f"{d}/frames/f*.jpg"))


def fresh(d, max_age=STALE):
    f = newest_frames(d)
    try:
        return bool(f) and time.time() - os.stat(f[-1]).st_mtime < max_age
    except OSError:
        return False


def pick_frame(d, since, timeout=8.0):
    """path of a complete JPEG written after 'since' (and at least 0.3 s ago), or None"""
    end = time.time() + timeout
    while time.time() < end:
        for f in reversed(newest_frames(d)):
            try:
                st = os.stat(f)
                if st.st_mtime < since:
                    break
                if time.time() - st.st_mtime < 0.3:
                    continue
                b = open(f, "rb").read()
            except OSError:
                continue
            if b[:2] == b"\xff\xd8" and b[-2:] == b"\xff\xd9":
                return f
        time.sleep(0.1)
    return None


def pause(d, on):
    p = f"{d}/pause"
    if on:
        open(p, "w").close()
        end = time.time() + 5            # wait for the supervisor to release the camera
        while time.time() < end and os.path.exists(f"{d}/pipeline.pid"):
            time.sleep(0.1)
    elif os.path.exists(p):
        os.unlink(p)


# ---------------------------------------------------------------- supervisor
def _pipeline(d, dev, run):
    caps = os.environ.get("CAM_CAPS", "image/jpeg,width=1920,height=1080")
    has_split = subprocess.run(["gst-inspect-1.0", "splitmuxsink"], capture_output=True).returncode == 0
    if has_split:
        a = (f"splitmuxsink muxer-factory=matroskamux location={d}/run-{run:03d}-%03d.mkv "
             f"max-size-time={int(SEG_MIN * 60e9)}")
    else:
        a = f"matroskamux ! filesink location={d}/run-{run:03d}-000.mkv"
    p = (f"v4l2src device={dev} ! {caps} ! jpegparse ! videorate drop-only=true ! image/jpeg,framerate={FPS}/1 ! "
         f"tee name=t t. ! queue max-size-time=4000000000 ! {a} "
         f"t. ! queue leaky=downstream max-size-buffers=2 ! multifilesink location={d}/frames/f%05d.jpg max-files={KEEP}")
    return ["gst-launch-1.0", "-e", "-q"] + p.split()


def _stop(proc):
    if proc and proc.poll() is None:
        proc.send_signal(signal.SIGINT)          # -e: finalise the mkv
        try:
            proc.wait(10)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait()


def log(d, msg):
    line = f"{time.strftime('%F %T')} camrec: {msg}"
    print(line, flush=True)
    with open(f"{d}/recorder.log", "a") as f:
        f.write(line + "\n")


def run(d):
    import camcheck
    os.makedirs(f"{d}/frames", exist_ok=True)
    open(f"{d}/supervisor.pid", "w").write(str(os.getpid()))
    stopping = []
    signal.signal(signal.SIGTERM, lambda *_: stopping.append(1))
    signal.signal(signal.SIGINT, lambda *_: stopping.append(1))
    runs = jread(f"{d}/rec.json", {"runs": []})
    for r in runs["runs"]:            # a run that never closed (crash / reboot): ends with its last segment
        if r["t1"] is None:
            segs = glob.glob(f"{d}/run-{r['n']:03d}-*.mkv")
            r["t1"] = max([os.stat(x).st_mtime for x in segs] or [r["t0"] or r["start"]])
    jwrite(f"{d}/rec.json", runs)
    proc, n, fails = None, len(glob.glob(f"{d}/run-*-000.mkv")), 0
    while not stopping:
        if proc is None:
            if os.path.exists(f"{d}/pause"):
                time.sleep(0.5)
                continue
            dev = os.environ.get("CAM_DEV") or camcheck.find()
            if not dev:
                if not fails:
                    log(d, f"no webcam matching {camcheck.CAM_NAME!r}, retrying")
                fails += 1
                time.sleep(3)
                continue
            for f in newest_frames(d):
                os.unlink(f)
            n += 1
            proc = subprocess.Popen(_pipeline(d, dev, n), stderr=subprocess.PIPE, text=True)
            open(f"{d}/pipeline.pid", "w").write(str(proc.pid))
            t_start = time.time()
            runs = jread(f"{d}/rec.json", {"runs": []})
            runs["runs"].append({"n": n, "start": t_start, "t0": None, "t1": None})
            jwrite(f"{d}/rec.json", runs)
            log(d, f"pipeline started on {dev}: run-{n:03d}")
            fails = 0
        time.sleep(0.5)
        runs = jread(f"{d}/rec.json", {"runs": []})
        cur = runs["runs"][-1]
        fr = newest_frames(d)
        if fr and cur["t0"] is None:
            cur["t0"] = os.stat(fr[0]).st_mtime
            jwrite(f"{d}/rec.json", runs)
        why = ""
        if proc.poll() is not None:
            why = f"pipeline exited rc={proc.returncode}: {(proc.stderr.read() or '').strip()[-200:]}"
        elif os.path.exists(f"{d}/pause"):
            why = "paused for a direct capture"
        elif fr and time.time() - os.stat(fr[-1]).st_mtime > STALE or (not fr and time.time() - t_start > 15):
            why = "no frames (camera unplugged or USB reset?)"
        if why:
            log(d, why)
            _stop(proc)
            fr = newest_frames(d)
            cur["t1"] = os.stat(fr[-1]).st_mtime if fr and cur["t0"] else cur["t0"]
            jwrite(f"{d}/rec.json", runs)
            proc = None
            if os.path.exists(f"{d}/pipeline.pid"):
                os.unlink(f"{d}/pipeline.pid")
            if "paused" not in why:
                time.sleep(2)
    if proc:
        _stop(proc)
        runs = jread(f"{d}/rec.json", {"runs": []})
        fr = newest_frames(d)
        if runs["runs"] and runs["runs"][-1]["t1"] is None and fr:
            runs["runs"][-1]["t1"] = os.stat(fr[-1]).st_mtime
            jwrite(f"{d}/rec.json", runs)
    for n_ in ("pipeline.pid", "supervisor.pid"):
        if os.path.exists(f"{d}/{n_}"):
            os.unlink(f"{d}/{n_}")


def start_background(d):
    """start the supervisor detached; returns its Popen (harness side)"""
    os.makedirs(d, exist_ok=True)
    for f in ("pause",):
        if os.path.exists(f"{d}/{f}"):
            os.unlink(f"{d}/{f}")
    return subprocess.Popen([sys.executable, "-I", os.path.abspath(__file__), "run", d], start_new_session=True,
                            stdout=open(f"{d}/supervisor.out", "a"), stderr=subprocess.STDOUT)


def stop_background(d):
    try:
        os.kill(int(open(f"{d}/supervisor.pid").read()), signal.SIGTERM)
    except (OSError, ValueError):
        return
    end = time.time() + 15
    while time.time() < end and os.path.exists(f"{d}/supervisor.pid"):
        time.sleep(0.2)


# ---------------------------------------------------------------- markers (harness side)
def srt_time(s):
    ms = int(round(max(s, 0) * 1000))
    return f"{ms // 3600000:02d}:{ms // 60000 % 60:02d}:{ms // 1000 % 60:02d},{ms % 1000:03d}"


class Marks:
    def __init__(self, d):
        self.d = d
        self.cues = jread(f"{d}/cues.json", [])

    def rel(self, now=None):
        """seconds on the concatenated recording at wall-clock 'now'"""
        now = now or time.time()
        base = 0.0
        for r in jread(f"{self.d}/rec.json", {"runs": []})["runs"]:
            if r["t0"] is None:
                continue
            if r["t1"] is None:                 # running (or crashed: treated as running until the next run)
                return base + max(now - r["t0"], 0)
            base += max(r["t1"] - r["t0"], 0)
        return base

    def case_start(self, idx, total, text):
        self.cues.append({"kind": "case", "idx": idx, "start": self.rel(), "end": None,
                          "text": f"case {idx + 1}/{total} {text}", "verdict": ""})
        self.save()

    def case_end(self, idx, text, verdict):
        for c in reversed(self.cues):
            if c["kind"] == "case" and c["idx"] == idx and c["end"] is None:
                c.update(end=self.rel(), text=text, verdict=verdict)
                break
        self.save()

    def span(self, text, verdict):
        """a finished case that has no start hook (media-matrix.sh): runs from the end of the previous one"""
        cs = [c for c in self.cues if c["kind"] == "case" and c["end"] is not None]
        t = self.rel()
        self.cues.append({"kind": "case", "idx": len(cs), "start": cs[-1]["end"] if cs else 0.0, "end": t,
                          "text": text, "verdict": verdict})
        self.save()

    def event(self, text, length=4.0):
        t = self.rel()
        self.cues.append({"kind": "event", "idx": -1, "start": t, "end": t + length, "text": text, "verdict": ""})
        self.save()

    def save(self):
        jwrite(f"{self.d}/cues.json", self.cues)
        write_outputs(self.d, self.cues)


def write_outputs(d, cues):
    cues = sorted(cues, key=lambda c: c["start"])
    ends = []
    for i, c in enumerate(cues):        # unfinished case (crash): until the next cue
        e = c["end"] if c["end"] is not None else (cues[i + 1]["start"] if i + 1 < len(cues) else c["start"] + 5)
        ends.append(max(e, c["start"] + 0.5))
    with open(f"{d}/cases.srt", "w") as f:
        for i, (c, e) in enumerate(zip(cues, ends), 1):
            text = c["text"] + (f"\n=> {c['verdict']}" if c["verdict"] else "")
            f.write(f"{i}\n{srt_time(c['start'])} --> {srt_time(e)}\n{text}\n\n")
    with open(f"{d}/chapters.txt", "w") as f:
        f.write(";FFMETADATA1\n")
        for c, e in zip(cues, ends):
            if c["kind"] == "case":
                t = (c["text"] + (f" {c['verdict']}" if c["verdict"] else "")).replace("\n", " ")
                t = t.replace("=", "-").replace(";", ",").replace("#", "").replace("\\", "/")
                f.write(f"[CHAPTER]\nTIMEBASE=1/1000\nSTART={int(c['start'] * 1000)}\nEND={int(e * 1000)}\ntitle={t}\n")
    with open(f"{d}/cases.tsv", "w") as f:     # idx start end verdict text (one line)
        for c, e in zip(cues, ends):
            if c["kind"] == "case":
                f.write(f"{c['idx']}\t{c['start']:.3f}\t{e:.3f}\t{c['verdict'] or 'UNFINISHED'}\t"
                        f"{c['text'].replace(chr(9), ' ').replace(chr(10), ' | ')}\n")


# ---------------------------------------------------------------- self test
def selftest():
    import tempfile
    bad = 0

    def check(name, ok):
        nonlocal bad
        print(f"{'ok  ' if ok else 'FAIL'} {name}")
        bad += not ok
    d = tempfile.mkdtemp(prefix="camrec-st-")
    os.makedirs(f"{d}/frames")
    now = time.time()
    jwrite(f"{d}/rec.json", {"runs": [{"n": 1, "start": now - 120, "t0": now - 100, "t1": now - 40},
                                      {"n": 2, "start": now - 30, "t0": now - 20, "t1": None}]})
    m = Marks(d)
    r = m.rel(now)
    check("timeline joins runs without the gap (60 + 20 s)", abs(r - 80) < 0.01)
    m.case_start(0, 3, "modes HDMI-A-1")
    m.case_end(0, "case 1/3 modes HDMI-A-1 1920x1080@60 bpc=8 cf=RGB\nplane 44 XR24/0x0", "PASS")
    m.case_start(1, 3, "modes HDMI-A-1")
    m.event("CAMERA MOVED: control failed")
    m.case_end(1, "case 2/3 modes HDMI-A-1 640x480@60", "FAIL")
    m.case_start(2, 3, "crashed one")
    srt = open(f"{d}/cases.srt").read()
    check("srt has 4 cues, indexed from 1", srt.count(" --> ") == 4 and srt.startswith("1\n00:01:"))
    check("srt carries verdict", "=> FAIL" in srt and "=> PASS" in srt)
    ch = open(f"{d}/chapters.txt").read()
    check("chapters ffmetadata", ch.startswith(";FFMETADATA1") and ch.count("[CHAPTER]") == 3)
    tsv = [x.split("\t") for x in open(f"{d}/cases.tsv").read().splitlines()]
    check("cases.tsv: 3 cases, last UNFINISHED", len(tsv) == 3 and tsv[-1][3] == "UNFINISHED" and tsv[1][3] == "FAIL")
    check("srt time format", srt_time(3725.5) == "01:02:05,500")
    open(f"{d}/frames/f00001.jpg", "wb").write(b"\xff\xd8junk\xff\xd9")
    open(f"{d}/frames/f00002.jpg", "wb").write(b"\xff\xd8partial")
    time.sleep(0.4)
    check("pick_frame skips a partial JPEG", pick_frame(d, now, 1).endswith("f00001.jpg"))
    check("pick_frame ignores frames older than 'since'", pick_frame(d, time.time() + 1, 0.5) is None)
    check("fresh() false on old frames", not fresh(d, 0.1))
    shutil.rmtree(d)
    return bad


def main(a):
    if not a:
        sys.exit(__doc__)
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    if a[0] == "run":
        run(a[1])
    elif a[0] == "status":
        print("fresh" if fresh(a[1]) else "stale")
        sys.exit(0 if fresh(a[1]) else 1)
    elif a[0] == "span":
        Marks(a[1]).span(a[3], a[2])
    elif a[0] == "event":
        Marks(a[1]).event(a[2])
    elif a[0] == "stop":
        stop_background(a[1])
    elif a[0] == "selftest":
        sys.exit(selftest())
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main(sys.argv[1:])
