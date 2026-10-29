#!/bin/bash
# Copy the new kernel, U-Boot and helper files to the Orange Pi; then run the
# printed command on the Pi (needs your sudo password there).
set -euo pipefail
. "$(dirname "$0")/env.sh"
PI=${1:-$OPI5_PI}
SSH=(-o BatchMode=yes -o UserKnownHostsFile="$OPI5_KNOWN_HOSTS" -i "$OPI5_SSH_KEY")
STAGE=/tmp/opi5-update

files=("$TOP"/out/debs/linux-image-*.deb "$TOP"/out/debs/linux-headers-*.deb
       "$TOP"/out/u-boot-rockchip.bin "$TOP"/out/u-boot-rockchip-spi.bin
       "$TOP"/overlay/usr/local/sbin/opi5-install-ssd "$TOP"/scripts/pi-apply-update.sh)
for f in "${files[@]}"; do [ -f "$f" ] || { echo "missing $f"; exit 1; }; done

ssh "${SSH[@]}" "$PI" "rm -rf $STAGE && mkdir -p $STAGE"
scp -q "${SSH[@]}" "${files[@]}" "$PI:$STAGE/"
scp -q "${SSH[@]}" "$TOP/overlay/etc/default/u-boot" "$PI:$STAGE/u-boot.default"
echo "Copied. On the Pi, run:  sudo $STAGE/pi-apply-update.sh"
