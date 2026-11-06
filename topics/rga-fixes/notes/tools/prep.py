#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""rga3-nv15: make the test inputs and software references on the host (run with python3 -I).

prep.py OUTDIR
  10-bit content: HEVC Main10 and VP9 Profile 2 encodes of a noisy test pattern (host libx265/libvpx) and the
  JCT-VC conformance stream WPP_A_ericsson_MAIN10_2, decoded by FFmpeg (software) to yuv420p10le = the reference.
  Writes tight (no row padding) raw frames: *.nv15, *.p010, *.nv12 inputs and *.yuv10 references, plus
  8-bit pictures for the rotation cases and FFmpeg-scaled references. Skips work already done (resumable).
"""
import os, subprocess, sys
import numpy as np

OUT = sys.argv[1]
FATE = '~/orangepi5/work/_downloads/fate-suite/hevc-conformance/WPP_A_ericsson_MAIN10_2.bit'
FF = ['ffmpeg', '-nostdin', '-loglevel', 'error', '-y']
os.makedirs(OUT, exist_ok=True)


def p(name):
    return os.path.join(OUT, name)


def run(args):
    subprocess.run(args, check=True)


def pack_nv15(a):
    """10-bit samples (rows, cols, cols % 4 == 0) -> V4L2 NV15 bytes: 4 samples in 40 bits, little endian."""
    a = a.astype(np.uint64).reshape(a.shape[0], -1, 4)
    v = a[..., 0] | (a[..., 1] << 10) | (a[..., 2] << 20) | (a[..., 3] << 30)
    b = np.stack([(v >> (8 * i)) & 0xff for i in range(5)], axis=-1).astype(np.uint8)
    return b.reshape(a.shape[0], -1)


def frames10(path, w, h):
    raw = np.fromfile(path, '<u2')
    fs = w * h * 3 // 2
    for f in raw.reshape(-1, fs):
        y = f[:w * h].reshape(h, w)
        u = f[w * h:w * h + w * h // 4].reshape(h // 2, w // 2)
        v = f[w * h + w * h // 4:].reshape(h // 2, w // 2)
        yield y, np.stack([u, v], axis=-1).reshape(h // 2, w)   # interleaved CbCr like NV12


def make10(name, src, w, h):
    ref = p(f'{name}.yuv10')
    if not os.path.exists(ref):
        run(FF + ['-i', src, '-frames:v', '4', '-pix_fmt', 'yuv420p10le', '-f', 'rawvideo', ref + '.tmp'])
        os.rename(ref + '.tmp', ref)
    if os.path.exists(p(f'{name}.nv12')):
        return
    nv15, p010, nv12, yuv10 = [], [], [], []
    for y, c in frames10(ref, w, h):
        nv15 += [pack_nv15(y).tobytes(), pack_nv15(c).tobytes()]
        p010 += [(y.astype('<u2') << 6).tobytes(), (c.astype('<u2') << 6).tobytes()]
        nv12 += [np.clip((y + 2) >> 2, 0, 255).astype(np.uint8).tobytes(),
                 np.clip((c + 2) >> 2, 0, 255).astype(np.uint8).tobytes()]
        yuv10 += [y.astype('<u2').tobytes(), c.astype('<u2').tobytes()]
    for ext, data in (('nv15', nv15), ('p010', p010), ('ref10', yuv10), ('nv12', nv12)):
        with open(p(f'{name}.{ext}'), 'wb') as f:
            f.write(b''.join(data))


# 10-bit sources: test pattern plus noise in 10 bits, so that the two low bits carry information
src10 = p('src10.yuv')
if not os.path.exists(src10):
    run(FF + ['-f', 'lavfi', '-i', 'testsrc2=s=1920x1080:r=30', '-frames:v', '4', '-pix_fmt', 'yuv420p',
              '-f', 'rawvideo', p('src8.yuv')])
    a = np.fromfile(p('src8.yuv'), np.uint8).astype(np.int32) << 2
    rng = np.random.default_rng(1)
    a = np.clip(a + rng.integers(-12, 13, a.shape), 64, 940).astype('<u2')
    a.tofile(src10 + '.tmp')
    os.rename(src10 + '.tmp', src10)
RAW10 = ['-f', 'rawvideo', '-pix_fmt', 'yuv420p10le', '-s', '1920x1080', '-r', '30', '-i', src10]
if not os.path.exists(p('hevc10.mkv')):
    run(FF + RAW10 + ['-c:v', 'libx265', '-profile:v', 'main10', '-pix_fmt', 'yuv420p10le',
              '-x265-params', 'log-level=error:crf=16', p('hevc10.tmp.mkv')])
    os.rename(p('hevc10.tmp.mkv'), p('hevc10.mkv'))
if not os.path.exists(p('vp92.webm')):
    run(FF + RAW10 + ['-c:v', 'libvpx-vp9', '-profile:v', '2', '-pix_fmt', 'yuv420p10le', '-crf', '20',
              '-b:v', '0', '-deadline', 'good', '-cpu-used', '4', p('vp92.tmp.webm')])
    os.rename(p('vp92.tmp.webm'), p('vp92.webm'))
make10('hevc10', p('hevc10.mkv'), 1920, 1080)
make10('vp92', p('vp92.webm'), 1920, 1080)
make10('conf', FATE, 416, 240)

# 8-bit pictures for the rotation cases (one frame each)
if not os.path.exists(p('rgb.xr24')):
    run(FF + ['-f', 'lavfi', '-i', 'testsrc2=s=1920x1080,noise=alls=20:allf=t', '-frames:v', '1',
              '-pix_fmt', 'bgr0', '-f', 'rawvideo', p('rgb.xr24')])
if not os.path.exists(p('rgb720.xr24')):
    run(FF + ['-f', 'lavfi', '-i', 'testsrc2=s=1280x720,noise=alls=20:allf=t', '-frames:v', '1',
              '-pix_fmt', 'bgr0', '-f', 'rawvideo', p('rgb720.xr24')])
if not os.path.exists(p('pic.nv12')):
    run(FF + ['-f', 'lavfi', '-i', 'testsrc2=s=1920x1080,noise=alls=20:allf=t', '-frames:v', '1',
              '-pix_fmt', 'nv12', '-f', 'rawvideo', p('pic.nv12')])
if not os.path.exists(p('pic.nv16')):
    run(FF + ['-f', 'lavfi', '-i', 'testsrc2=s=1920x1080', '-frames:v', '1',
              '-pix_fmt', 'nv16', '-f', 'rawvideo', p('pic.nv16')])
# first frame of the HEVC NV15 / ref10 for the 10-bit rotation cases
for ext, n in (('nv15', 1920 * 1080 * 15 // 8), ('ref10', 1920 * 1080 * 3)):
    if not os.path.exists(p(f'hevc10-f0.{ext}')):
        with open(p(f'hevc10.{ext}'), 'rb') as f, open(p(f'hevc10-f0.{ext}'), 'wb') as g:
            g.write(f.read(n))

# FFmpeg references for the scaling cases (bicubic, 8 bit)
if not os.path.exists(p('hevc10-720.nv12ref')):
    run(FF + ['-f', 'rawvideo', '-pix_fmt', 'yuv420p10le', '-s', '1920x1080', '-i', p('hevc10.yuv10'),
              '-vf', 'scale=1280:720:flags=bicubic', '-pix_fmt', 'nv12', '-f', 'rawvideo', p('hevc10-720.nv12ref')])
if not os.path.exists(p('pic-r90-540.nv12ref')):
    run(FF + ['-f', 'rawvideo', '-pix_fmt', 'nv12', '-s', '1920x1080', '-i', p('pic.nv12'),
              '-vf', 'transpose=clock,scale=540:960:flags=bicubic', '-pix_fmt', 'nv12', '-f', 'rawvideo',
              p('pic-r90-540.nv12ref')])
open(p('PREP-DONE'), 'w').write('ok\n')
print('prep done', OUT)
