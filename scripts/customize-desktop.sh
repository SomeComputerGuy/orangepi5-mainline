#!/bin/bash
# mmdebstrap customize hook for IMAGE_VARIANT=desktop; runs before customize-rootfs.sh
# (which then adds the common overlay, the kernel and the first-boot cleanup).
# The desktop is Ubuntu Desktop plus the board enablement in build-image.sh's
# DESKTOP_PKGS; this hook only adds overlay-desktop/ (each file's reason:
# work/_out/desktop-image/RESULTS.md, "What the image contains").
set -euo pipefail
R=$1 TOP=$2

# mmdebstrap's copy of the build-time Mozilla source (NNNNmozilla.sources); the
# image uses overlay-desktop's mozilla.sources
rm -f "$R"/etc/apt/sources.list.d/[0-9][0-9][0-9][0-9]*.sources
rsync -rlt --chown=root:root --chmod=D755,F644 "$TOP/overlay-desktop/" "$R/"
chmod 600 "$R/etc/netplan/01-network-manager-all.yaml"   # netplan wants it private

chroot "$R" systemctl set-default graphical.target
