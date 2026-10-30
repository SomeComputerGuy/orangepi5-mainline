#!/bin/bash
# Unattended: install kernel build 3 (7.3.0-3, patches/linux 292-patch stack) on the Orange Pi 5,
# reboot, then validate every video block and write REPORT.md. Runs on the HOST; needs no human.
#   nohup ~/orangepi5/work/_out/k3-validation/run-k3.sh > ~/orangepi5/work/_out/k3-validation/run.log 2>&1 &
set -uo pipefail
TOP=${TOP:-$HOME/orangepi5}   # the workspace this ran in (set TOP to yours)
OUT=$TOP/work/_out/k3-validation
LOG=$OUT/logs; mkdir -p "$LOG"
REP=$OUT/REPORT.md
PI=${OPI5_PI:-ubuntu@orangepi5}
SSHO=(-o BatchMode=yes -o ConnectTimeout=5 -o ServerAliveInterval=15 -o UserKnownHostsFile=$TOP/.ssh/known_hosts -i $TOP/.ssh/opi5_ed25519)
SERIAL=${OPI5_TMP:-/tmp}/serial-hang.log
DEBS=("$TOP"/out/debs/linux-image-7.3.0-opi5_7.3.0-3_arm64.deb "$TOP"/out/debs/linux-headers-7.3.0-opi5_7.3.0-3_arm64.deb)
DTB=$TOP/build/wt-integration-7.3/arch/arm64/boot/dts/rockchip/rk3588s-orangepi-5-sata.dtb   # stack + 1005 (DP)
DEMO_SRC=$TOP/work/_downloads/uvg/enc

ts() { date '+%F %T'; }
say() { echo "[$(ts)] $*"; }
rep() { echo "$*" >> "$REP"; }
R() { ssh "${SSHO[@]}" "$PI" "$@"; }                       # run on the board
waitup() {   # waitup <max seconds>: wait until ssh answers
  local end=$(( $(date +%s) + $1 ))
  while [ "$(date +%s)" -lt "$end" ]; do R true 2>/dev/null && return 0; sleep 5; done; return 1
}
sertail() { [ -f "$SERIAL" ] && tail -c 4000 "$SERIAL" | tr -d '\r' | strings | tail -40; }

: > "$REP"
rep "# Kernel 3 install and video validation (unattended run)"
rep ""
rep "Started $(ts). Script: \`work/_out/k3-validation/run-k3.sh\`, logs in \`work/_out/k3-validation/logs/\`."
rep ""

if [ "${K3_INSTALLED:-0}" != 1 ]; then
# ---------------------------------------------------------------- 0. preflight
for f in "${DEBS[@]}" "$DTB"; do [ -f "$f" ] || { rep "**ABORT:** missing $f"; exit 1; }; done
say "waiting for the board"
waitup 1800 || { rep "**ABORT:** board unreachable for 30 min before install."; rep '```'; sertail >> "$REP"; rep '```'; exit 1; }
# Give a running suspend-test agent a few minutes to restore the board, then make sure ourselves
sleep 120; waitup 900
R 'sudo -n sed -i "s/ irqchip.gicv3_pseudo_nmi=1//" /etc/default/u-boot; sudo -n rm -f /etc/modprobe.d/zz-suspend-test.conf; echo none | sudo -n tee /sys/power/pm_test >/dev/null 2>&1; grep ^U_BOOT_PARAMETERS /etc/default/u-boot' > "$LOG/preflight.txt" 2>&1

# ---------------------------------------------------------------- 1. copy + install
say "copying demo clips and packages"
cp "$TOP/work/_out/demo/demo.sh" "$TOP/work/_out/rkvenc-hevc/tools/rkvenc-enc" "$TOP/work/_out/vepu121-h264enc/tools/v4l2-h264-slenc" "$DEMO_SRC"/
for i in 1 2 3 4 5; do
  rsync -a --partial --inplace -e "ssh ${SSHO[*]}" --exclude '*.log' "$DEMO_SRC"/ "$PI":demo/ && break; sleep 20; waitup 600
done
R 'rm -rf /tmp/k3 && mkdir -p /tmp/k3' && scp -q "${SSHO[@]}" "${DEBS[@]}" "$DTB" "$PI":/tmp/k3/ || { rep "**ABORT:** copy to board failed."; exit 1; }
say "installing"
R 'set -e
   D=/usr/lib/linux-image-7.3.0-opi5/rockchip/rk3588s-orangepi-5-sata.dtb
   sudo -n cp -p $D /var/tmp/rk3588s-orangepi-5-sata.dtb.K2-dp
   sudo -n cp -p /boot/vmlinuz-7.3.0-opi5 /var/tmp/vmlinuz-7.3.0-opi5.kernel2
   sudo -n cp -p /boot/initrd.img-7.3.0-opi5 /var/tmp/initrd.img-7.3.0-opi5.kernel2
   sudo -n mkdir -p /var/tmp/updates-k2 && sudo -n cp -a /lib/modules/7.3.0-opi5/updates/. /var/tmp/updates-k2/ 2>/dev/null || true
   # every interim drop-in module is in the package now; updates/ would shadow it
   sudo -n rm -rf /lib/modules/7.3.0-opi5/updates/opi5-*
   sudo -n rm -f /etc/modules-load.d/opi5-reset-scmi.conf
   export DEBIAN_FRONTEND=noninteractive
   sudo -n -E dpkg -i /tmp/k3/linux-image-7.3.0-opi5_7.3.0-3_arm64.deb /tmp/k3/linux-headers-7.3.0-opi5_7.3.0-3_arm64.deb
   sudo -n install -m644 /tmp/k3/rk3588s-orangepi-5-sata.dtb $D
   sudo -n depmod -a 7.3.0-opi5
   sudo -n u-boot-update >/dev/null
   grep -m1 append /boot/extlinux/extlinux.conf
   ls /lib/modules/7.3.0-opi5/updates/ 2>/dev/null || true; sync' > "$LOG/install.txt" 2>&1
rc=$?
rep "## 1. Install"
rep ""
if [ $rc -ne 0 ]; then rep "**ABORT:** install failed (rc=$rc), board NOT rebooted; see logs/install.txt."; exit 1; fi
rep "Installed linux-image/headers 7.3.0-3, the stack+1005 DTB, removed all \`updates/opi5-*\` drop-ins (backup \`/var/tmp/updates-k2\`); kernel-2 image backups in \`/var/tmp/*.kernel2\`."
rep ""

else
  rep "## 1. Install"; rep ""; rep "Installed in the previous run (logs/install.txt); this run starts at the reboot."; rep ""
  waitup 900
fi

# ---------------------------------------------------------------- 2. reboot + boot health
say "rebooting"
R 'sudo -n systemctl reboot' >/dev/null 2>&1
sleep 30
if ! waitup 600; then
  rep "## 2. Boot: **FAILED** — board did not come back within 10 min."
  rep ""; rep "Rescue: interrupt U-Boot on serial and boot \`/var/tmp/vmlinuz-7.3.0-opi5.kernel2\` is NOT enough (kernel 2's modules were replaced); reinstall \`out/debs-k2/\` from a rescue boot. Serial tail:"
  rep '```'; sertail >> "$REP"; rep '```'; exit 1
fi
sleep 45   # let udev / modules settle
R 'uname -v; systemctl is-system-running; cat /proc/cmdline
   echo "--- BTF/module rejections: $(sudo -n dmesg | grep -cE "failed to validate module|BTF.*-22|disagrees about version")"
   echo "--- drivers:"; for m in rockchip_vdec hantro_vpu rockchip_venc rockchip_jpegd rockchip_iep rockchip_rga panthor rocket dwc3_rockchip rockchipdrm; do printf "%-15s %s %s\n" $m "$(grep -q "^$m " /proc/modules && echo loaded || echo MISSING)" "$(modinfo -n $m 2>/dev/null)"; done
   echo "--- video nodes:"; for d in /sys/class/video4linux/video*; do printf "%s %s\n" /dev/$(basename $d) "$(cat $d/name)"; done
   echo "--- drm:"; for c in /sys/class/drm/card*-*; do echo "$c $(cat $c/status 2>/dev/null)"; done
   echo "--- devfreq:"; ls /sys/class/devfreq
   echo "--- dtb symbols: $(ls /sys/firmware/devicetree/base/__symbols__ >/dev/null 2>&1 && echo yes || echo no), dp0 status: $(tr -d "\0" < /sys/firmware/devicetree/base/dp@fde50000/status)"
   echo "--- kernel errors:"; sudo -n dmesg --level=err,crit,alert,emerg | head -30' > "$LOG/boot.txt" 2>&1
rep "## 2. Boot health"
rep ""; rep '```'; cat "$LOG/boot.txt" >> "$REP"; rep '```'; rep ""

# Ethernet throughput (host listener, board sender/receiver)
HIP=$(ip -4 route get ${OPI5_PI_IP:-172.31.55.129} | grep -oP 'src \K\S+')
scp -q "${SSHO[@]}" ${OPI5_TMP:-/tmp}/tcpt.py "$PI":/tmp/tcpt.py 2>/dev/null
if [ -f ${OPI5_TMP:-/tmp}/tcpt.py ]; then
  (timeout 40 python3 -I ${OPI5_TMP:-/tmp}/tcpt.py serve-recv x 5299 > "$LOG/eth-up.txt" 2>&1 &) ; sleep 1
  R "python3 -I /tmp/tcpt.py send $HIP 5299" >> "$LOG/eth-up.txt" 2>&1; sleep 2
  (timeout 40 python3 -I ${OPI5_TMP:-/tmp}/tcpt.py serve-send x 5299 > "$LOG/eth-down.txt" 2>&1 &) ; sleep 1
  R "python3 -I /tmp/tcpt.py recv $HIP 5299" >> "$LOG/eth-down.txt" 2>&1
  rep "Ethernet: board→host $(grep -oE '[0-9]+ Mbit/s' "$LOG/eth-up.txt" | head -1), host→board $(grep -oE '[0-9]+ Mbit/s' "$LOG/eth-down.txt" | head -1)."; rep ""
fi

# ---------------------------------------------------------------- 3. decoder bit-exactness (first 30 frames vs ffmpeg)
say "decoder bit-exactness"
rep "## 3. Decoder bit-exactness (first 30 frames, hardware vs ffmpeg software, tight I420)"
rep ""; rep "| Decoder | Clip | Result |"; rep "|---|---|---|"
R 'bash -s' > "$LOG/bitexact.txt" 2>&1 <<'EOS'
source <(sed -n '/^conn()/,/^mux()/p' ~/demo/demo.sh)
cmp30() {   # cmp30 <label> <file> <demux+parse> <element>
  local n=30 fs
  [ -n "$4" ] || { echo "| $1 | $(basename $2) | no element |"; return; }
  timeout 120 gst-launch-1.0 -q filesrc location=$2 ! $3 ! $4 ! videoconvert ! video/x-raw,format=I420 ! identity eos-after=$((n+10)) ! filesink location=/tmp/hw.yuv >/dev/null 2>&1
  timeout 120 ffmpeg -hide_banner -loglevel error -y -i $2 -frames:v $n -f rawvideo -pix_fmt yuv420p /tmp/sw.yuv
  fs=$(( $(stat -c %s /tmp/sw.yuv) / n ))
  local ok=0 i
  for i in $(seq 0 $((n-1))); do cmp -s <(dd if=/tmp/hw.yuv bs=$fs skip=$i count=1 2>/dev/null) <(dd if=/tmp/sw.yuv bs=$fs skip=$i count=1 2>/dev/null) && ok=$((ok+1)); done
  echo "| $1 ($4) | $(basename $2) | $ok/$n frames bit-exact |"
  rm -f /tmp/hw.yuv /tmp/sw.yuv
}
D=~/demo
cmp30 "rkvdec HEVC"  $D/yacht_hevc_2160p120.mp4 "qtdemux ! h265parse"        "$(elem h265 rkvdec)"
cmp30 "rkvdec VP9"   $D/yacht_vp9_2160p120.webm "matroskademux ! vp9parse"   "$(elem vp9 rkvdec)"
cmp30 "rkvdec H.264" $D/yacht_h264_2160p120.mp4 "qtdemux ! h264parse"        "$(elem h264 rkvdec)"
cmp30 "AV1 VPU"      $D/yacht_av1_1080p120.mkv  "matroskademux ! av1parse"   "$(elem av1 av1)"
cmp30 "G1 H.264"     $D/yacht_h264_1080p120.mp4 "qtdemux ! h264parse"        "$(elem h264 vpu121-dec)"
cmp30 "G1 VP8"       $D/yacht_vp8_1080p120.webm "matroskademux"              "$(elem vp8 vpu121-dec)"
cmp30 "G1 MPEG-2"    $D/yacht_mpeg2_1080p120.mpg "mpegpsdemux ! mpegvideoparse" "$(elem mpeg2 vpu121-dec)"
EOS
grep '^|' "$LOG/bitexact.txt" >> "$REP"; rep ""

# ---------------------------------------------------------------- 4. on-screen playback (HDMI 4K120 console)
say "playback demo"
rep "## 4. Playback on HDMI (kmssink, Esmart plane; fps from fpsdisplaysink; dmesg lines during each run)"
rep ""; rep '```'
R '~/demo/demo.sh list' >> "$REP" 2>&1
for s in dec-hevc dec-vp9 dec-h264 dec-av1 g1-h264 g1-vp8 g1-mpeg2; do
  R "timeout 120 ~/demo/demo.sh $s" > "$LOG/play-$s.txt" 2>&1; cat "$LOG/play-$s.txt" >> "$REP"; sleep 3
done
R "timeout 120 ~/demo/demo.sh dual" > "$LOG/play-dual.txt" 2>&1
echo "--- dual display (HDMI HEVC + DP VP9 simultaneously):" >> "$REP"; cat "$LOG/play-dual.txt" >> "$REP"
rep '```'; rep ""

# ---------------------------------------------------------------- 5. encode -> playback + PSNR
say "encoders"
rep "## 5. Encoders: encode the 4K/1080p source, play the result on screen, PSNR vs source (first 60 frames)"
rep ""; rep '```'
for s in enc-hevc enc-h264 enc-vepu2 jpeg; do
  R "timeout 300 ~/demo/demo.sh $s" > "$LOG/$s.txt" 2>&1; cat "$LOG/$s.txt" >> "$REP"; sleep 3
done
R 'cd ~/demo/out
   psnr() { ffmpeg -hide_banner -nostats -i "$1" -f rawvideo -pix_fmt nv12 -s "$2" -r 120 -i "$3" -frames:v 60 -lavfi psnr -f null - 2>&1 | grep -oE "PSNR y:[0-9.]+ u:[0-9.]+ v:[0-9.]+ average:[0-9.]+"; }
   for f in venc_hevc.mkv venc_h264.mkv; do [ -s $f ] && echo "$f: $(ls -la $f | awk "{print \$5}") bytes, $(psnr $f 3840x2160 ~/demo/yacht_2160p.nv12)"; done
   [ -s vepu2_h264.mkv ] && echo "vepu2_h264.mkv: $(ls -la vepu2_h264.mkv | awk "{print \$5}") bytes, $(psnr vepu2_h264.mkv 1920x1080 ~/demo/yacht_1080p.nv12)"' > "$LOG/psnr.txt" 2>&1
rep '```'; rep ""; rep "PSNR / sizes:"; rep '```'; cat "$LOG/psnr.txt" >> "$REP"; rep '```'; rep ""

# ---------------------------------------------------------------- 6. conformance (fluster, -j2)
say "fluster"
rep "## 6. Conformance (fluster, -j2)"
rep ""
R 'cd ~/vp9conf
   fluster download JVT-AVC_V1 JCT-VC-HEVC_V1 >/dev/null 2>&1
   for t in "GStreamer-VP9-V4L2SL VP9-TEST-VECTORS" "GStreamer-H.264-V4L2SL JVT-AVC_V1" "GStreamer-H.265-V4L2SL JCT-VC-HEVC_V1"; do
     set -- $t; timeout 1500 fluster run -d $1 -ts $2 -j 2 -t 60 -s -so k3-$2.md > k3-$2.log 2>&1
     echo "$1 / $2: $(grep -m1 "Ran " k3-$2.log)"
   done
   diff <(grep -E "^\|vp9" k2.md | sort) <(grep -E "^\|vp9" k3-VP9-TEST-VECTORS.md | sort) >/dev/null && echo "VP9 per-vector identical to kernel 2" || echo "VP9 per-vector DIFFERS from kernel 2 (see ~/vp9conf/k3-VP9-TEST-VECTORS.md)"' > "$LOG/fluster.txt" 2>&1
rep '```'; cat "$LOG/fluster.txt" >> "$REP"; rep '```'; rep ""

# ---------------------------------------------------------------- 7. v4l2-compliance + final health
say "compliance"
R 'for d in /sys/class/video4linux/video*; do n=$(cat $d/name); case "$n" in *Aluratek*) continue;; esac
     printf "%-34s %s\n" "$n" "$(timeout 120 v4l2-compliance -d /dev/$(basename $d) 2>&1 | grep -E "^Total" | tail -1)"; done
   echo "--- GPU devfreq: $(cat /sys/class/devfreq/fb000000.gpu/available_frequencies 2>/dev/null)"
   echo "--- POST_BUF_EMPTY total this boot: $(sudo -n dmesg | grep -c POST_BUF_EMPTY)"
   echo "--- new kernel errors since boot:"; sudo -n dmesg --level=err,crit,alert,emerg | grep -v POST_BUF_EMPTY | tail -20
   echo "--- Oops/BUG/SError: $(sudo -n dmesg | grep -cE "Oops|BUG:|SError|Internal error")"' > "$LOG/final.txt" 2>&1
rep "## 7. v4l2-compliance and final health"
rep ""; rep '```'; cat "$LOG/final.txt" >> "$REP"; rep '```'; rep ""
rep "Finished $(ts)."
say "done; report at $REP"
