#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Install a test kernel (whole debs from <debs dir>), reboot, short boot check.
# The caller holds BOARD-LOCK. Restore stock with NOLOCK=1 work/_out/k14/install-check.sh.
# Debs found by glob, version read from the deb (no hardcoded package names or versions).
set -u
D=${1:?debs dir}
S=$(cat ~/.claude/jobs/35761d63/tmp/ssh.cmd)
until timeout 10 $S true 2>/dev/null; do sleep 30; done
dpkg_idle() { until ! $S 'sudo fuser /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock' >/dev/null 2>&1; do sleep 10; done; }
IMG=$(ls $D/linux-image-7.3.0-opi5_*_arm64.deb); HDR=$(ls $D/linux-headers-7.3.0-opi5_*_arm64.deb)
[ $(echo "$IMG" | wc -w) = 1 ] && [ $(echo "$HDR" | wc -w) = 1 ] || { echo "need one image+headers deb"; exit 1; }
VER=$(dpkg-deb -f "$IMG" Version)
[ -n "$VER" ] || { echo "cannot read the version of $IMG"; exit 1; }
$S "mkdir -p /var/tmp/hevcrc2i && rm -f /var/tmp/hevcrc2i/*.deb" || exit 1
$S "cat > /var/tmp/hevcrc2i/image.deb" < $IMG || exit 1; $S "cat > /var/tmp/hevcrc2i/headers.deb" < $HDR || exit 1
dpkg_idle
$S 'sudo dpkg -i /var/tmp/hevcrc2i/image.deb /var/tmp/hevcrc2i/headers.deb >/dev/null 2>&1; echo dpkg=$?; true'
OUT=~/.claude/jobs/35761d63/tmp/hevc-rc2/install.txt
mkdir -p "${OUT%/*}"
$S 'dpkg -l linux-image-7.3.0-opi5 | awk "/^.i/{print \$1, \$3}"; stat -c "initrd=%s" /boot/initrd.img-7.3.0-opi5' > $OUT
cat $OUT
grep -qx "ii $VER" $OUT && ! grep -q "^initrd=0$" $OUT || { echo "INSTALL FAILED (want ii $VER)"; exit 2; }
$S 'rm -f /var/tmp/hevcrc2i/*.deb'
dpkg_idle
$S 'sudo systemctl reboot' 2>/dev/null; sleep 60
for i in $(seq 1 30); do timeout 8 $S true 2>/dev/null && break; sleep 10; done
$S 'uname -rv; echo "warn=$(sudo dmesg | grep -cE "WARNING|BUG:|Oops|Call trace")"; ls /sys/module/rockchip_venc/parameters/'
