#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
# Reopen matrix helper: one role per process, results as one JSON line on stdout.
#   mx.py ref    PIPE OUT.md5                       per-frame md5 list of PIPE run alone
#   mx.py steady PIPE --ref R --period P --stop F   loop PIPE until file F exists; check md5/gaps
#   mx.py cycle  PIPE --ref R --frames K --cycles N --variant V [--stop F]
#   mx.py once   PIPE                                (used by variant kill) prints "F n" per frame
#   mx.py vref   "VENC ARGS" OUT.ref                 venc-cycle -T solo run: per-frame hashes
#   mx.py vsteady "VENC ARGS" --ref R --period P --stop F --wrap W   (-r looping encoder, ref[i % W])
#   mx.py vcycle "VENC ARGS" --ref R --frames K --cycles N --variant normal|abort|kill|restart
#   mx.py csteady "CMD" --period P --stop F [--md5 FILE]  CMD run back to back (blocks without a
#                                                       streaming client), run time > 2*P is a stall
#   mx.py ccycle "CMD" --cycles N [--md5 FILE] [--kill S] CMD per cycle; output file $OUT checked
# PIPE is a gst-launch description that ends in "videocodectestsink name=chk" (md5 per frame)
# or "fakesink name=chk" (frame timing only). "{K}" in PIPE is replaced by the frame count.
# Variants: normal (EOS after K frames, close), nullmid (NULL after k<K frames: buffers still queued),
# flush (one pipeline, flushing seek to 0 every K frames: decoder STREAMOFF/STREAMON, no close),
# kill (child process SIGKILLed after k<K frames).
import json, os, random, signal, subprocess, sys, time
import gi
gi.require_version('Gst', '1.0')
gi.require_version('GstVideo', '1.0')
from gi.repository import Gst, GLib, GstVideo
import zlib

Gst.init(None)
T0 = time.monotonic()


def arg(name, default=None, conv=str):
    if name in sys.argv:
        return conv(sys.argv[sys.argv.index(name) + 1])
    return default


class Run:
    """One pipeline instance: frame times, md5s, errors."""

    def __init__(self, desc, timeout=10.0):
        self.desc = desc
        self.p = Gst.parse_launch(desc)
        self.times, self.md5, self.errors = [], [], []
        self.eos = False
        self.timeout = timeout
        self.vinfo = None
        self.crc = False
        chk = self.p.get_by_name('chk')
        self.crc = chk.get_factory().get_name() == 'fakesink'
        self.pad = chk.get_static_pad('sink')
        self.probe_id = self.pad.add_probe(Gst.PadProbeType.BUFFER, self._probe)
        bus = self.p.get_bus()
        bus.add_signal_watch()
        self.bus_id = bus.connect('message', self._msg)
        self.loop = GLib.MainLoop()

    def _probe(self, pad, info):
        self.times.append(time.monotonic())
        if self.crc:
            h = self._crc(pad, info.get_buffer())
            if h:
                self.md5.append(h)
        return Gst.PadProbeReturn.OK

    def _crc(self, pad, buf):
        # CRC32 of the visible pixels of every plane (strides/padding excluded).
        if self.vinfo is None:
            caps = pad.get_current_caps()
            if not caps.get_structure(0).get_name() == 'video/x-raw':
                self.crc = False
                return None
            self.vinfo = GstVideo.VideoInfo.new_from_caps(caps)
        vi = self.vinfo
        meta = GstVideo.buffer_get_video_meta(buf)
        ok, m = buf.map(Gst.MapFlags.READ)
        if not ok:
            return 'unmappable'
        try:
            data, c = m.data, 0
            for p in range(vi.finfo.n_planes):
                off = meta.offset[p] if meta else vi.offset[p]
                stride = meta.stride[p] if meta else vi.stride[p]
                h = vi.height if p == 0 else (vi.height + 1) // 2
                rowbytes = vi.width if vi.finfo.format in (GstVideo.VideoFormat.NV12,) else stride
                for y in range(h):
                    c = zlib.crc32(data[off + y * stride: off + y * stride + rowbytes], c)
            return '%08x' % c
        finally:
            buf.unmap(m)

    def _msg(self, bus, m):
        t = m.type
        if t == Gst.MessageType.ELEMENT:
            s = m.get_structure()
            if s and s.get_name() == 'conformance/checksum':
                self.md5.append(s.get_string('checksum'))
        elif t == Gst.MessageType.EOS:
            self.eos = True
            self.loop.quit()
        elif t == Gst.MessageType.ERROR:
            e, dbg = m.parse_error()
            self.errors.append('%s: %s' % (m.src.get_name(), e.message))
            self.loop.quit()
        elif t == Gst.MessageType.WARNING:
            e, dbg = m.parse_warning()
            self.errors.append('warning %s: %s' % (m.src.get_name(), e.message))

    def run(self, until=None, max_s=None):
        """Play until EOS/error, or until until() is true (checked every 20 ms)."""
        t_start = time.monotonic()
        if self.p.set_state(Gst.State.PLAYING) == Gst.StateChangeReturn.FAILURE:
            self.errors.append('set_state PLAYING failed')
            return
        self.first = None

        def tick():
            now = time.monotonic()
            if not self.times and now - t_start > self.timeout:
                self.errors.append('no frame %.1f s after start (start failure/hang)' % self.timeout)
                self.loop.quit()
                return False
            if self.times and now - self.times[-1] > self.timeout:
                self.errors.append('no frame for %.1f s after frame %d (stall)' % (self.timeout, len(self.times)))
                self.loop.quit()
                return False
            if until and until(self):
                self.loop.quit()
                return False
            if max_s and now - t_start > max_s:
                self.loop.quit()
                return False
            return True
        GLib.timeout_add(20, tick)
        self.loop.run()
        self.start_lat = (self.times[0] - t_start) if self.times else None

    def stop(self):
        t = time.monotonic()
        self.p.set_state(Gst.State.NULL)
        self.close_s = time.monotonic() - t
        # Break the Python <-> GObject reference cycles (probe and bus handler hold this
        # object), so the pipeline and its elements are finalized now.
        bus = self.p.get_bus()
        bus.remove_signal_watch()
        bus.disconnect(self.bus_id)
        self.pad.remove_probe(self.probe_id)
        self.pad = None
        self.p = None
        self.loop = None


def load_ref(path):
    if not path or not os.path.exists(path):
        return None
    return [l.strip() for l in open(path) if l.strip() and not l.startswith('#')]


def ref_frames(path):
    for l in open(path):
        if l.startswith('#frames '):
            return int(l.split()[1])
    return None


def out(d):
    print(json.dumps(d), flush=True)


def role_ref(desc, path, ka):
    r = Run(desc.replace('{K}', str(ka)), timeout=20)
    r.run()
    r.stop()
    with open(path, 'w') as f:
        f.write('\n'.join(r.md5) + '\n#frames %d\n' % len(r.times))
    out({'role': 'ref', 'frames': len(r.times), 'md5': len(r.md5), 'errors': r.errors})


def role_steady(desc, ref, period, stop, ka):
    """Loop desc (restart at EOS) until the stop file appears. A gap > 2*period inside a run is a stall."""
    refl = load_ref(ref)
    res = {'role': 'steady', 'runs': 0, 'frames': 0, 'bad_md5': 0, 'stalls': 0, 'max_gap_ms': 0,
           'errors': [], 'restart_ms_max': 0}
    while not os.path.exists(stop):
        t = time.monotonic()
        r = Run(desc.replace('{K}', str(ka)), timeout=max(10 * period, 3.0))
        r.run(until=lambda r: os.path.exists(stop))
        r.stop()
        res['runs'] += 1
        res['frames'] += len(r.times)
        if r.times:
            res['restart_ms_max'] = max(res['restart_ms_max'], int((r.times[0] - t) * 1000))
        gaps = [b - a for a, b in zip(r.times, r.times[1:])]
        for i, g in enumerate(gaps):
            if g > 2 * period:
                res['stalls'] += 1
                if res['stalls'] <= 5:
                    res['errors'].append('run %d: %.0f ms gap after frame %d at t=%.1f' %
                                         (res['runs'], g * 1000, i + 1, r.times[i] - T0))
        if gaps:
            res['max_gap_ms'] = max(res['max_gap_ms'], int(max(gaps) * 1000))
        # videocodectestsink posts the md5 of the whole run at EOS: complete runs are checked.
        if refl is not None and r.eos:
            if r.md5 != refl:
                res['bad_md5'] += 1
                res['errors'].append('run %d: stream md5 %s, reference %s' % (res['runs'], r.md5, refl))
            if len(r.times) != ref_frames(ref):
                res['errors'].append('run %d: %d frames, reference has %d' % (res['runs'], len(r.times), ref_frames(ref)))
        res['checked_runs'] = res.get('checked_runs', 0) + (1 if r.eos else 0)
        res['errors'] += ['run %d: %s' % (res['runs'], e) for e in r.errors]
        sys.stderr.write('steady run %d: %d frames, max gap %.0f ms, %s\n' % (
            res['runs'], len(r.times), max(gaps) * 1000 if gaps else 0, r.errors or 'ok'))
    out(res)


def role_once(desc):
    r = Run(desc, timeout=10)

    def note(r):
        sys.stdout.write('F %d\n' % len(r.times))
        sys.stdout.flush()
        return False
    r.run(until=note)
    r.stop()
    sys.stdout.write('DONE %d %s\n' % (len(r.times), r.errors))


def role_cycle(desc, ref, K, N, variant, stop):
    refl = load_ref(ref)
    res = {'role': 'cycle', 'variant': variant, 'cycles': 0, 'fail_open': 0, 'fail_start': 0,
           'bad_md5': 0, 'short': 0, 'errors': [], 'start_ms_max': 0, 'close_ms_max': 0}
    rnd = random.Random(1234)

    def fail(i, kind, msg):
        res[kind] += 1
        if len(res['errors']) < 20:
            res['errors'].append('cycle %d: %s' % (i, msg))
        sys.stderr.write('cycle %d: %s: %s\n' % (i, kind, msg))

    if variant == 'flush':
        # One pipeline: N flushing seeks back to the start, K frames apart.
        r = Run(desc.replace('{K}', '-1'), timeout=10)
        state = {'next': K, 'seeks': 0, 'base': 0}

        def until(r):
            if len(r.times) >= state['next']:
                if state['seeks'] >= N:
                    return True
                state['seeks'] += 1
                if not r.p.seek_simple(Gst.Format.TIME, Gst.SeekFlags.FLUSH | Gst.SeekFlags.ACCURATE, 0):
                    fail(state['seeks'], 'fail_start', 'flushing seek refused')
                state['next'] = len(r.times) + K
            return False
        r.run(until=until)
        r.stop()
        res['cycles'] = state['seeks']
        for e in r.errors:
            fail(state['seeks'], 'fail_start', e)
        # (videocodectestsink has no per-frame md5: segments are checked by frame count only)
        if r.times and len(r.times) < N * K:
            fail(N, 'short', '%d frames over %d segments of %d' % (len(r.times), N, K))
        out(res)
        return

    for i in range(1, N + 1):
        if stop and os.path.exists(stop):
            break
        res['cycles'] = i
        if variant == 'kill':
            k = rnd.randint(1, max(1, K - 1))
            c = subprocess.Popen([sys.executable, __file__, 'once', desc.replace('{K}', '-1')],
                                 stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
            t = time.monotonic()
            got = 0
            for line in c.stdout:
                if line.startswith('F '):
                    got = int(line.split()[1])
                    if got >= k:
                        break
                if time.monotonic() - t > 10:
                    break
            os.kill(c.pid, signal.SIGKILL)
            c.wait()
            if got < k:
                fail(i, 'fail_start', 'child decoded %d frames, wanted %d before SIGKILL' % (got, k))
            continue
        try:
            r = Run(desc.replace('{K}', str(K)), timeout=5)
        except GLib.Error as e:
            fail(i, 'fail_open', str(e))
            continue
        if variant == 'nullmid':
            k = rnd.randint(1, max(1, K - 1))
            r.run(until=lambda r: len(r.times) >= k)
        else:
            r.run()
        r.stop()
        res['close_ms_max'] = max(res['close_ms_max'], int(r.close_s * 1000))
        if r.start_lat is not None:
            res['start_ms_max'] = max(res['start_ms_max'], int(r.start_lat * 1000))
        if r.errors:
            fail(i, 'fail_start', '; '.join(r.errors))
            continue
        if variant == 'normal':
            want = ref_frames(ref) if ref else K
            if len(r.times) != want:
                fail(i, 'short', '%d frames, wanted %d' % (len(r.times), want))
            if refl and r.md5 != refl:
                fail(i, 'bad_md5', 'stream md5 %s, reference %s' % (r.md5, refl))
    out(res)


# ---- encoder client (tools/venc-cycle -T prints "F idx time bytes hash" per frame on stderr)
def venc_frames(text):
    fr = []
    for l in text.splitlines():
        if l.startswith('F '):
            f = l.split()
            fr.append((int(f[1]), float(f[2]), int(f[3]), f[4]))
    return fr


def role_vref(args, path):
    c = subprocess.run(args + ' -T', shell=True, capture_output=True, text=True, timeout=1800)
    fr = venc_frames(c.stderr)
    with open(path, 'w') as f:
        f.write('\n'.join(h for _, _, _, h in fr) + '\n')
    out({'role': 'vref', 'frames': len(fr), 'rc': c.returncode,
         'tail': c.stderr.strip().splitlines()[-3:]})


def role_vsteady(args, ref, period, stop, wrap):
    refl = load_ref(ref)
    res = {'role': 'vsteady', 'runs': 0, 'frames': 0, 'bad_hash': 0, 'stalls': 0, 'max_gap_ms': 0,
           'errors': [], 'restart_ms_max': 0}
    while not os.path.exists(stop):
        t = time.monotonic()
        c = subprocess.Popen(args + ' -T -r', shell=True, stderr=subprocess.PIPE, text=True,
                             start_new_session=True)
        fr, last, other = [], time.monotonic(), []
        import selectors
        sel = selectors.DefaultSelector()
        sel.register(c.stderr, selectors.EVENT_READ)
        buf = ''
        while True:
            if os.path.exists(stop):
                # SIGTERM: background jobs of a non-interactive shell ignore SIGINT.
                os.killpg(c.pid, signal.SIGTERM)
                break
            if sel.select(timeout=0.05):
                line = c.stderr.readline()
                if not line:
                    break
                if line.startswith('F '):
                    f = line.split()
                    fr.append((int(f[1]), float(f[2]), int(f[3]), f[4]))	# CLOCK_MONOTONIC
                    last = time.monotonic()
                elif not line.startswith(('using', 'raw', 'encoded', 'feedback', 'stream rest')):
                    other.append(line.strip())
            if time.monotonic() - last > max(20 * period, 5):
                res['errors'].append('run %d: no frame for %.0f s after frame %d (stall)' %
                                     (res['runs'] + 1, time.monotonic() - last, len(fr)))
                res['stalls'] += 1
                os.killpg(c.pid, signal.SIGKILL)
                break
        try:
            rest, _ = c.communicate(timeout=10)	# drain stderr so the client can exit
        except subprocess.TimeoutExpired:
            os.killpg(c.pid, signal.SIGKILL)
            rest, _ = c.communicate()
            res['errors'].append('run %d: encoder did not exit on SIGTERM' % (res['runs'] + 1))
        for line in (rest or '').splitlines():
            if line.startswith('F '):
                f = line.split()
                fr.append((int(f[1]), float(f[2]), int(f[3]), f[4]))	# CLOCK_MONOTONIC
        res['runs'] += 1
        res['frames'] += len(fr)
        if fr:
            res['restart_ms_max'] = max(res['restart_ms_max'], int((fr[0][1] - t) * 1000))
        gaps = [b[1] - a[1] for a, b in zip(fr, fr[1:])]
        for i, g in enumerate(gaps):
            if g > 2 * period:
                res['stalls'] += 1
                if res['stalls'] <= 5:
                    res['errors'].append('run %d: %.0f ms gap after frame %d' % (res['runs'], g * 1000, i))
        if gaps:
            res['max_gap_ms'] = max(res['max_gap_ms'], int(max(gaps) * 1000))
        if refl:
            badl = [i for i, _, _, h in fr if h != refl[i % wrap]]
            bad = len(badl)
            if bad:
                res['bad_hash'] += bad
                res['errors'].append('run %d: %d/%d coded frames differ from the reference: %s' %
                                     (res['runs'], bad, len(fr), ','.join(map(str, badl[:40]))))
        if other:
            res['errors'] += ['run %d: %s' % (res['runs'], o) for o in other[:5]]
    out(res)


def role_vcycle(args, ref, K, N, variant, stop):
    refl = load_ref(ref)
    res = {'role': 'vcycle', 'variant': variant, 'cycles': 0, 'fail_open': 0, 'fail_start': 0,
           'bad_hash': 0, 'short': 0, 'errors': [], 'start_ms_max': 0, 'run_ms_max': 0}
    rnd = random.Random(4321)

    def fail(i, kind, msg):
        res[kind] += 1
        if len(res['errors']) < 20:
            res['errors'].append('cycle %d: %s' % (i, msg))
        sys.stderr.write('cycle %d: %s: %s\n' % (i, kind, msg))
    if variant == 'restart':     # one process: STREAMOFF/STREAMON every K frames, N times
        t = time.monotonic()
        try:
            c = subprocess.run(args + ' -T -r -n %d -k %d' % (K * (N + 1), K), shell=True,
                               capture_output=True, text=True, timeout=60 + K * N)
        except subprocess.TimeoutExpired:
            fail(0, 'fail_start', 'timed out (hang)')
            out(res)
            return
        fr = venc_frames(c.stderr)
        res['cycles'] = N
        if c.returncode or len(fr) != K * (N + 1):
            fail(0, 'fail_start', 'rc %d, %d/%d frames: %s' % (c.returncode, len(fr), K * (N + 1),
                                                             c.stderr.strip().splitlines()[-2:]))
        if refl:
            bad = sum(1 for i, _, _, h in fr if h != refl[i % len(refl)])
            if bad:
                fail(0, 'bad_hash', '%d/%d frames differ (STREAMOFF/STREAMON must not change the output)' % (bad, len(fr)))
        out(res)
        return
    for i in range(1, N + 1):
        if stop and os.path.exists(stop):
            break
        res['cycles'] = i
        t = time.monotonic()
        if variant == 'kill':
            k = rnd.randint(1, max(1, K - 1))
            c = subprocess.Popen(args + ' -T', shell=True, stderr=subprocess.PIPE, text=True,
                                 start_new_session=True)
            got = 0
            for line in c.stderr:
                if line.startswith('F '):
                    got += 1
                    if got >= k:
                        break
                if time.monotonic() - t > 10:
                    break
            os.killpg(c.pid, signal.SIGKILL)
            c.wait()
            if got < k:
                fail(i, 'fail_start', 'encoded %d frames, wanted %d before SIGKILL' % (got, k))
            continue
        extra = ' -n %d' % K
        if variant == 'abort':
            extra = ' -n %d -a %d -j 3' % (K, rnd.randint(1, max(1, K - 2)))
        try:
            c = subprocess.run(args + ' -T' + extra, shell=True, capture_output=True, text=True, timeout=30)
        except subprocess.TimeoutExpired:
            fail(i, 'fail_start', 'timed out after 30 s (hang)')
            continue
        res['run_ms_max'] = max(res['run_ms_max'], int((time.monotonic() - t) * 1000))
        fr = venc_frames(c.stderr)
        if fr:
            res['start_ms_max'] = max(res['start_ms_max'], int((fr[0][1] - t) * 1000))
        want_rc = 3 if variant == 'abort' else 0
        if c.returncode != want_rc:
            kind = 'fail_open' if not fr else 'fail_start'
            fail(i, kind, 'rc %d: %s' % (c.returncode, ' | '.join(c.stderr.strip().splitlines()[-2:])))
            continue
        if variant == 'normal' and len(fr) != K:
            fail(i, 'short', '%d frames, wanted %d' % (len(fr), K))
        if refl:
            bad = sum(1 for j, _, _, h in fr if h != refl[j])
            if bad:
                fail(i, 'bad_hash', '%d/%d frames differ' % (bad, len(fr)))
    out(res)


# ---- generic commands (IEP2 iep-test, NPU, GPU, ...): $OUT in CMD is replaced by an output path
def run_cmd(cmd, outp, timeout):
    t = time.monotonic()
    try:
        c = subprocess.run(cmd.replace('$OUT', outp), shell=True, capture_output=True, text=True,
                           timeout=timeout)
        rc, err = c.returncode, (c.stdout + c.stderr).strip().splitlines()[-2:]
    except subprocess.TimeoutExpired:
        rc, err = 'timeout', ['timed out after %d s (hang)' % timeout]
    return rc, err, time.monotonic() - t


def md5_of(p):
    import hashlib
    h = hashlib.md5()
    with open(p, 'rb') as f:
        for b in iter(lambda: f.read(1 << 20), b''):
            h.update(b)
    return h.hexdigest()


def role_csteady(cmd, period, stop, md5f):
    ref = open(md5f).read().split()[0] if md5f and os.path.exists(md5f) else None
    res = {'role': 'csteady', 'runs': 0, 'bad_md5': 0, 'stalls': 0, 'max_run_ms': 0, 'errors': []}
    outp = '/tmp/mx-csteady.%d.out' % os.getpid()
    while not os.path.exists(stop):
        rc, err, dt = run_cmd(cmd, outp, max(30, 20 * period))
        res['runs'] += 1
        res['max_run_ms'] = max(res['max_run_ms'], int(dt * 1000))
        if rc != 0:
            res['errors'].append('run %d: rc %s %s' % (res['runs'], rc, err))
            if rc == 'timeout':
                res['stalls'] += 1
            continue
        if dt > 2 * period:
            res['stalls'] += 1
            res['errors'].append('run %d took %.0f ms (> 2 x %.0f)' % (res['runs'], dt * 1000, period * 1000))
        if ref and os.path.exists(outp) and md5_of(outp) != ref:
            res['bad_md5'] += 1
            res['errors'].append('run %d: output md5 differs' % res['runs'])
    res['errors'] = res['errors'][:20]
    out(res)


def role_ccycle(cmd, N, md5f, kill_s, stop):
    ref = open(md5f).read().split()[0] if md5f and os.path.exists(md5f) else None
    res = {'role': 'ccycle', 'cycles': 0, 'fail_start': 0, 'bad_md5': 0, 'errors': [], 'run_ms_max': 0}
    outp = '/tmp/mx-ccycle.%d.out' % os.getpid()
    rnd = random.Random(99)
    for i in range(1, N + 1):
        if stop and os.path.exists(stop):
            break
        res['cycles'] = i
        if kill_s:
            c = subprocess.Popen(cmd.replace('$OUT', outp), shell=True, start_new_session=True,
                                 stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            time.sleep(rnd.uniform(0.05, kill_s))
            if c.poll() is not None and c.returncode != 0:
                res['fail_start'] += 1
                res['errors'].append('cycle %d: exited rc %d before the kill' % (i, c.returncode))
            else:
                os.killpg(c.pid, signal.SIGKILL)
            c.wait()
            continue
        rc, err, dt = run_cmd(cmd, outp, 30)
        res['run_ms_max'] = max(res['run_ms_max'], int(dt * 1000))
        if rc != 0:
            res['fail_start'] += 1
            res['errors'].append('cycle %d: rc %s %s' % (i, rc, err))
        elif ref and md5_of(outp) != ref:
            res['bad_md5'] += 1
            res['errors'].append('cycle %d: output md5 differs' % i)
    res['errors'] = res['errors'][:20]
    out(res)


if __name__ == '__main__':
    role, desc = sys.argv[1], sys.argv[2]
    if role == 'ref':
        role_ref(desc, sys.argv[3], arg('--ka', -1, int))
    elif role == 'steady':
        role_steady(desc, arg('--ref'), arg('--period', 0.0333, float), arg('--stop'), arg('--ka', -1, int))
    elif role == 'once':
        role_once(desc)
    elif role == 'cycle':
        role_cycle(desc, arg('--ref'), arg('--frames', 30, int), arg('--cycles', 200, int),
                   arg('--variant', 'normal'), arg('--stop'))
    elif role == 'vref':
        role_vref(desc, sys.argv[3])
    elif role == 'vsteady':
        role_vsteady(desc, arg('--ref'), arg('--period', 0.0333, float), arg('--stop'), arg('--wrap', 600, int))
    elif role == 'vcycle':
        role_vcycle(desc, arg('--ref'), arg('--frames', 30, int), arg('--cycles', 200, int),
                    arg('--variant', 'normal'), arg('--stop'))
    elif role == 'csteady':
        role_csteady(desc, arg('--period', 1.0, float), arg('--stop'), arg('--md5'))
    elif role == 'ccycle':
        role_ccycle(desc, arg('--cycles', 200, int), arg('--md5'), arg('--kill', 0, float), arg('--stop'))
