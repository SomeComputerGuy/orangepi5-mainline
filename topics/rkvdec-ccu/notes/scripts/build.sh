#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Build + sign v4l2-mem2mem.ko and rockchip-vdec.ko from the rkvdec-ccu worktree
# for the board kernel (7.3.0-opi5, build/linux config and signing key).
set -e -o pipefail
export ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu-
W=${W:-~/orangepi5/work/rkvdec-ccu-7.3} B=${B:-~/orangepi5/build/wt-rkvdec-ccu-7.3}
EXTRA=${EXTRA:-W=1}
make -s -C $W O=$B LOCALVERSION= -j6 M=$W/drivers/media/v4l2-core MO=$B/ext/v4l2 $EXTRA modules 2>&1 | { grep -v "Skipping BTF" || true; }
make -s -C $W O=$B LOCALVERSION= -j6 M=$W/drivers/media/platform/rockchip/rkvdec MO=$B/ext/rkvdec \
	KBUILD_EXTRA_SYMBOLS=$B/ext/v4l2/Module.symvers $EXTRA modules 2>&1 | { grep -v "Skipping BTF" || true; }
for k in $B/ext/v4l2/v4l2-mem2mem.ko $B/ext/rkvdec/rockchip-vdec.ko; do
	test -f $k
	$B/scripts/sign-file sha512 $B/certs/signing_key.pem $B/certs/signing_key.x509 $k
	echo "$(basename $k): $(modinfo -F vermagic $k) signer=$(modinfo -F signer $k) $(sha256sum $k | cut -c1-16)"
done
