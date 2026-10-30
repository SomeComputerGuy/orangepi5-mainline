#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
# Run on the Orange Pi 5 after each boot, with a USB 3 device in the upper
# (USB3) Type-A port. Prints PASS when the device is on the SuperSpeed xHCI
# (fcd00000, 5000M), FAIL when it is on the EHCI of that port (fc880000).
set -u
ss=$(ls -d /sys/devices/platform/fcd00000.usb/xhci-hcd.*.auto/usb*/*-1 2>/dev/null | head -1)
hs=$(ls -d /sys/devices/platform/fc880000.usb/usb*/*-1 2>/dev/null | head -1)
ehci_port=$(ls -d /sys/devices/platform/fc880000.usb/usb*/*-0:1.0/usb*-port1 2>/dev/null | head -1)
if [ -e "$ehci_port/peer" ]; then
	echo "EHCI port peer: $(readlink -f "$ehci_port/peer")"
else
	echo "EHCI port peer: none"
fi
sudo -n dmesg | grep -E 'SuperSpeed peer port available|using ehci-platform|xhci-hcd.1.auto: xHCI Host' | head
if [ -n "$ss" ]; then
	echo "PASS: $(cat "$ss/product") on $(basename "$ss") at $(cat "$ss/speed")M"
elif [ -n "$hs" ]; then
	echo "FAIL: $(cat "$hs/product") on $(basename "$hs") at $(cat "$hs/speed")M (EHCI)"
else
	echo "NO DEVICE in the upper port"
fi
