#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# build-mod.sh <worktree> <kernel O dir> <out dir> [v4l2]: build + sign rockchip-vdec.ko
# (and v4l2-mem2mem.ko with "v4l2") from <worktree> against a configured kernel build.
set -e -o pipefail
export ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu-
W=$1 B=$2 OUT=$3 V=${4:-}
mkdir -p $OUT; rm -f $OUT/*.ko
X=
if [ "$V" = v4l2 ]; then
	make -s -C $W O=$B LOCALVERSION= -j8 M=$W/drivers/media/v4l2-core MO=$OUT/obj-v4l2 W=1 modules 2>&1 | { grep -v "Skipping BTF" || true; }
	cp $OUT/obj-v4l2/v4l2-mem2mem.ko $OUT/
	X="KBUILD_EXTRA_SYMBOLS=$OUT/obj-v4l2/Module.symvers"
fi
make -s -C $W O=$B LOCALVERSION= -j8 M=$W/drivers/media/platform/rockchip/rkvdec MO=$OUT/obj-rkvdec $X W=1 modules 2>&1 | { grep -v "Skipping BTF" || true; }
cp $OUT/obj-rkvdec/rockchip-vdec.ko $OUT/
for k in $OUT/*.ko; do
	$B/scripts/sign-file sha512 $B/certs/signing_key.pem $B/certs/signing_key.x509 $k
	echo "$(basename $k): $(modinfo -F vermagic $k) $(sha256sum $k | cut -c1-16)"
done
git -C $W log --oneline -1 > $OUT/BUILT-FROM; git -C $W diff --stat >> $OUT/BUILT-FROM
