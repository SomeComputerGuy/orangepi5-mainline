#!/bin/bash
# Install a tcpm.ko variant as a drop-in and put it in the initramfs.
# Usage: sudo install-tcpm.sh /var/tmp/tcpm-test/<stock-test|fixed-test|fixed>/tcpm.ko
#        sudo install-tcpm.sh --remove     (back to the in-tree tcpm.ko)
# Takes effect at the next boot (tcpm can't be reloaded: fusb302 owns the DP HPD bridge).
set -e
D=/lib/modules/7.3.0-opi5/updates/opi5-tcpm
if [ "$1" = --remove ]; then rm -rf $D; else mkdir -p $D; install -m644 "$1" $D/tcpm.ko; fi
depmod 7.3.0-opi5
modinfo -n -k 7.3.0-opi5 tcpm
update-initramfs -u -k 7.3.0-opi5
lsinitramfs /boot/initrd.img-7.3.0-opi5 | grep 'tcpm.ko$'
