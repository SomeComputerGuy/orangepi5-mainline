# SPDX-License-Identifier: GPL-2.0
# 1203 A/B: $1 = off|on. off: move the rockchipdrm drop-in aside; on: put it back. Rebuild initramfs, reboot.
set -e; M=/lib/modules/7.3.0-opi5/updates
if [ "$1" = off ]; then mv $M/opi5-hdmi10 /var/tmp/opi5-hdmi10.off; else mv /var/tmp/opi5-hdmi10.off $M/opi5-hdmi10; fi
depmod 7.3.0-opi5; update-initramfs -u -k 7.3.0-opi5 >/dev/null 2>&1; sync; echo "$1 ready, rebooting"; systemctl reboot
