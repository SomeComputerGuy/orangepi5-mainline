#!/bin/sh
set -e
export ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu-
W=~/orangepi5/work/hantro-multicore B=~/orangepi5/build/wt-hantro-multicore
make -s -C $W O=$B LOCALVERSION= -j6 M=$W/drivers/media/v4l2-core MO=$B/ext/v4l2 modules
make -s -C $W O=$B LOCALVERSION= -j6 M=$W/drivers/media/platform/verisilicon MO=$B/ext/hantro KBUILD_EXTRA_SYMBOLS=$B/ext/v4l2/Module.symvers W=1 modules
$B/scripts/sign-file sha512 $B/certs/signing_key.pem $B/certs/signing_key.x509 $B/ext/hantro/hantro-vpu.ko
ls -la $B/ext/hantro/hantro-vpu.ko
