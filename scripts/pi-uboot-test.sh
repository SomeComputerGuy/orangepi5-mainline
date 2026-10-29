#!/bin/bash
# Copy the freshly built U-Boot to the Orange Pi for an SD-card boot test
set -euo pipefail
. "$(dirname "$0")/env.sh"
PI=${1:-$OPI5_PI}
SSH=(-o BatchMode=yes -o UserKnownHostsFile="$OPI5_KNOWN_HOSTS" -i "$OPI5_SSH_KEY")
STAGE=/tmp/opi5-uboot-test
ssh "${SSH[@]}" "$PI" "rm -rf $STAGE && mkdir -p $STAGE"
scp -q "${SSH[@]}" "$TOP/out/u-boot-rockchip.bin" "$TOP/scripts/pi-apply-uboot-test.sh" "$PI:$STAGE/"
echo "Copied. On the Pi, run:  sudo $STAGE/pi-apply-uboot-test.sh"
