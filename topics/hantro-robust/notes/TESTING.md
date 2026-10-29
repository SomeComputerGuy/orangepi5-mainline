# hantro-robust: on-board test procedure (Orange Pi 5, RK3588S, kernel 7.3.0-opi5)

Fixes under test:

1. `media: verisilicon: Drop the runtime PM reference when clocks fail to enable`
2. `media: verisilicon: Make the codec run error handling consistent`
3. `media: verisilicon: Reset the Rockchip encoder cores on timeout`
4. `media: verisilicon: Reinitialize the IOMMU after a timeout`
5. `media: verisilicon: Don't hold a VPU behind an IOMMU in reset after remove` (backport of
   86102e78d from opi5/hantro-multicore; only on the single-core branch)
6. `dt-bindings: media: rockchip,rk3568-vepu: Add the reset lines`
7. `arm64: dts: rockchip: Add the reset lines of the RK3588 VEPU121 cores`

## Artifacts

All modules are signed with the 7.3.0-opi5 build key (vermagic `7.3.0-opi5`). Only
`hantro-vpu.ko` changes; v4l2-core is unchanged.

B=`~/orangepi5/build/wt-hantro-robust`

| File | Branch | Use |
|---|---|---|
| `$B/ext/hantro/hantro-vpu.ko` | `opi5/hantro-robust` (single-core, on hantro-validate) | final module |
| `$B/ext/hantro-debug/hantro-vpu.ko` | `opi5/hantro-robust-debug` (+ DEBUG fault injection) | tests below |
| `$B/ext/hantro-mc/hantro-vpu.ko` | `opi5/hantro-robust-mc` (on hantro-multicore 86102e78d) | final module, multi-core |
| `$B/ext/hantro-mc-debug/hantro-vpu.ko` | `opi5/hantro-robust-mc-debug` | tests below, multi-core |
| `$B/arch/arm64/boot/dts/rockchip/rk3588s-orangepi-5.dtb` | both (same DT change) | adds VEPU121 `resets` |

Run the tests with a `-debug` module. The `fault_inject` module parameter only exists
there. It is DEBUG-only and must not go upstream. It is a bitmask, and each bit clears
itself once it has fired, so it affects exactly one job:

| value | effect (VEPU2 JPEG encoder) | exercises |
|---|---|---|
| 1 | `.run()` returns -EIO after `hantro_start_prepare_run()` | fix 2 |
| 2 | `device_run()` acts as if `clk_bulk_enable()` failed | fix 1 |
| 4 | job programmed but the encoder is never started: a clean timeout, core idle | watchdog path, fix 4 |
| 8 | input plane 0 set to IOVA 0x01000000 (unmapped): IOMMU fault, wedged core | fixes 3 + 4 (the original bug) |

Each injection prints `hantro: injecting fault <bit>` in dmesg.

## 0. Install

```sh
# DTB: install it where the image loads it from (same procedure as for the other
# DT changes), reboot, then check that the resets are there:
for n in fdba0000 fdba4000 fdba8000 fdbac000; do
  echo "$n: $(tr '\0' ' ' < /proc/device-tree/video-codec@$n/reset-names)"; \
  xxd -g4 /proc/device-tree/video-codec@$n/resets; done
# expect "axi ahb" and the IDs 0x163 0x164 / 0x165 0x166 / 0x167 0x168 / 0x169 0x16a

# module (copy it to /tmp first)
sudo modprobe -r hantro_vpu
sudo install -m644 /tmp/hantro-vpu.ko /lib/modules/$(uname -r)/updates/hantro-vpu.ko
sudo depmod -a && sudo modprobe hantro_vpu
modinfo -F filename hantro_vpu         # must point at updates/
ls /sys/module/hantro_vpu/parameters/  # debug module: fault_inject is listed
D=/dev/v4l/by-path/platform-fdba0000.video-codec-video-index0
sudo dmesg -C
```

Test input (1920x1088 NM12, 3133440 bytes/frame):

```sh
gst-launch-1.0 videotestsrc num-buffers=8 pattern=smpte ! \
  video/x-raw,format=NV12,width=1920,height=1088 ! filesink location=src.nv12
enc() {  # $1 = output file, $2 = frame count
  v4l2-ctl -d $D --set-fmt-video-out=width=1920,height=1088,pixelformat=NM12 \
    --set-fmt-video=pixelformat=JPEG --stream-out-mmap=4 --stream-mmap=4 \
    --stream-from=src.nv12 --stream-to=$1 --stream-count=${2:-8} --verbose 2>&1 | tail -4
}
```

PM and clock state helper (on multi-core, run it for all four cores; a job can land on
any of them):

```sh
pm() {
  for n in fdba0000 fdba4000 fdba8000 fdbac000; do
    p=/sys/devices/platform/$n.video-codec/power
    [ -e $p ] || continue
    i=$(( (0x$n - 0xfdba0000) / 0x4000 ))
    m=$(printf '%x' $((0x$n + 0x800)))
    printf '%s: %s usage=%s  iommu=%s  aclk_en=%s\n' $n \
      $(cat $p/runtime_status) $(cat $p/runtime_usage) \
      $(cat /sys/devices/platform/$m.iommu/power/runtime_status 2>/dev/null || echo -) \
      $(sudo cat /sys/kernel/debug/clk/aclk_jpeg_encoder$i/clk_enable_count 2>/dev/null || echo -)
  done
}
```

(Single-core module: only fdba0000 is probed. The other nodes print "missing multi-core
support, ignoring this instance".)

Baseline: `enc base.mjpeg; sleep 1; pm`. Expect 8 frames, then on every core
`suspended usage=0`, the IOMMU `suspended`, and `aclk_en=0` (or whatever it was before the
module loaded). Write the baseline values down: the checks below compare against them.

## 1. Clock-enable failure path (fix 1)

```sh
echo 2 | sudo tee /sys/module/hantro_vpu/parameters/fault_inject
enc f2.mjpeg 8; sleep 1; pm; dmesg | tail
```

- Expected: one frame comes back with an error (v4l2-ctl prints an error buffer, or one
  frame fewer is written), the other 7 encode. After `sleep 1`: `suspended usage=0`,
  `aclk_en` back to baseline.
- Before fix 1: `runtime_usage` stays at 1 and `runtime_status` stays `active` for good.

## 2. `.run()` failure path (fix 2)

```sh
echo 1 | sudo tee /sys/module/hantro_vpu/parameters/fault_inject
enc f1.mjpeg 8; sleep 1; pm; dmesg | tail
```

- Expected: as in test 1. The next frames encode normally, the stream keeps going (the
  request and job machinery are not stuck), and after 1 s: `suspended usage=0` and
  `aclk_en` back to baseline.
- Before fix 2: usage +1 and `aclk_en` +1 per injected failure, and the device never
  suspends again.
- Do both tests 3 times in a row: the usage count must not grow.
- The VP9 and AV1 contract changes can't be triggered from the encoder. They are only
  compile-tested; a decoder fluster run (AV1 on fdc70000, VP9 n/a on RK3588) is the
  regression check: no new failures, and no "frame processing timed out" in dmesg.

## 3. Clean timeout (watchdog + IOMMU re-init, core idle)

```sh
echo 4 | sudo tee /sys/module/hantro_vpu/parameters/fault_inject
enc f4.mjpeg 8; sleep 1; pm; dmesg
```

- Expected dmesg: `injecting fault 2`, then about 2 s later
  `hantro_watchdog:...: frame processing timed out!`. **No** rk_iommu messages.
- The failed frame is returned with an error, the remaining frames encode (decode
  `f4.mjpeg` and check that the frames are valid), and after 1 s:
  `suspended usage=0`, `aclk_en` at baseline.

## 4. Real wedge: unmapped IOVA (fixes 3 + 4, the original bug)

```sh
echo 8 | sudo tee /sys/module/hantro_vpu/parameters/fault_inject
enc f8.mjpeg 8; sleep 1; pm; dmesg
```

Expected dmesg, in order:

1. `hantro: injecting fault 3`
2. rk_iommu page fault(s) from `fdba0800.iommu` (or the core the job ran on):
   `Page fault at 0x01000000 of type read` and `iova = 0x01000000: dte_index: ...`
3. About 2 s later: `frame processing timed out!`
4. **No** `Enable stall request timed out`, `Disable paging request timed out`,
   `Enable paging request timed out` or `FORCE_RESET command timed out` after the timeout
   message. (The reset pulse puts the core back to idle before the IOMMU is
   reinitialized.)

Then:

- The remaining frames of the same stream encode correctly. This proves that the
  next job after recovery succeeds on the same core and IOMMU. Also run `enc after.mjpeg 8`
  and decode its frames: they must be valid.
- After 1 s: `suspended usage=0`, IOMMU `suspended`, `aclk_en` at baseline. No
  `Disable paging request timed out` when the IOMMU runtime-suspends.
- Repeat 5 times. Then run the GStreamer loop from the hantro-validate TESTING.md
  (section 5): all pipelines must reach EOS.
- Optional, to read the reset state (needs /dev/mem): `busybox devmem 0xfd7c0ab0` (CRU
  SOFTRST_CON44, bits 10..15 = A/H resets of enc0..2) and `busybox devmem 0xfd7c0ab4`
  (CON45, bits 0..1 = enc3). The low 16 bits must read 0 (deasserted) at all times outside
  the 5 us pulse.

Negative control (optional, it can wedge the board: be ready to power-cycle): with the
**old** DTB, which has no resets, test 4 shows what the IOMMU re-init does alone. If the
stall timeouts come back and the later jobs time out, the CRU reset is what makes recovery
work. Don't `modprobe -r` in that state; reboot.

Multi-core module (`-mc-debug`): run tests 3 and 4 with 8 or more jobs in flight from 2
to 4 parallel `enc` processes (`enc a.mjpeg 32 & enc b.mjpeg 32 & wait`). The injected job
fails on one core only. The other streams must not see errors, and all cores end
`suspended usage=0`. A secondary core is detached from the main core's domain and attached
back: no `Failed to attach back` message, and the frames that core encodes after recovery
must be valid.

## 5. Safe unload/reload

After test 4 (core recovered), and again right after a fresh boot:

```sh
for i in 1 2 3; do
  sudo modprobe -r hantro_vpu && sleep 2 && sudo modprobe hantro_vpu && sleep 1
  enc r$i.mjpeg 8
done
dmesg | grep -Ei 'serror|panic|iommu|timed out'
```

- Expected: no SError or panic, no rk_iommu timeouts, and every `r$i.mjpeg` decodes.
- The `sleep 2` matters: it lets the IOMMU autosuspend while the driver is unbound,
  which is the window where fix 5 matters. The VEPU121 resets now exist in the DT and likely
  cover the IOMMU bus interface, so without fix 5 that suspend would hit an IOMMU held in
  reset (SError, as seen with the AV1 decoder). Also run it once with `sleep 0.05`.
- Also unload the module with AV1 (fdc70000) bound. That is fix 5's original case.

## Pass/fail summary

| Test | Pass criterion |
|---|---|
| 1 clk fail | one error frame, then `suspended usage=0`, aclk_en at baseline; no growth over 3 runs |
| 2 run fail | same as 1; the stream continues |
| 3 clean timeout | one "timed out", no rk_iommu messages, later frames valid, PM balanced |
| 4 wedge | page fault + "timed out", **no** stall/paging timeouts, later frames valid, PM balanced, 5/5 repeats |
| 4 mc | other streams unaffected, all cores balanced |
| 5 unload | 3/3 reload cycles without SError/hang, encodes valid after each |
