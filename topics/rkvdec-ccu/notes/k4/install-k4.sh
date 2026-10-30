#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Run ON the board after installing the kernel-4 debs (and their DTB), before the reboot.
set -e
cd $(dirname $(readlink -f $0))
D=/lib/modules/7.3.0-opi5/updates/opi5-rkvdec-ccu
sudo mkdir -p $D && sudo install -m 644 rockchip-vdec.ko v4l2-mem2mem.ko $D/
sudo rm -f /lib/modules/7.3.0-opi5/updates/opi5-codec-quality/rockchip-vdec.ko
sudo depmod -a; modinfo -n rockchip-vdec v4l2-mem2mem
T=/usr/lib/linux-image-7.3.0-opi5/rockchip/rk3588s-orangepi-5-sata.dtb
if fdtget $T /video-codec@fdc30000 compatible >/dev/null 2>&1; then echo "DTB already has the CCU"; else
	sudo cp -p $T /var/tmp/rk3588s-orangepi-5-sata.dtb.pre-ccu-k4
	sudo fdtoverlay -i $T -o /tmp/ccu.dtb rk3588-vdec-ccu.dtbo && sudo install -m 644 /tmp/ccu.dtb $T
	echo "CCU overlay applied ($(md5sum < $T | cut -c1-8)), backup /var/tmp/rk3588s-orangepi-5-sata.dtb.pre-ccu-k4"; fi
