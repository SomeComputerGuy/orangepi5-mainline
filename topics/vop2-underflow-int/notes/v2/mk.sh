#!/bin/sh
# make wrapper for the vop2-underflow v2 worktree
TOP=$HOME/orangepi5
SYSROOT=$TOP/build/arm64-sysroot
LIBDIR=$SYSROOT/usr/lib/aarch64-linux-gnu
CROSS_COMPILE=aarch64-linux-gnu-
export PATH=$TOP/build/xtool:$PATH
KCC="${CROSS_COMPILE}gcc -isystem $SYSROOT/usr/include -isystem $SYSROOT/usr/include/aarch64-linux-gnu -L$LIBDIR -Wl,-rpath-link=$LIBDIR"
export KBUILD_BUILD_USER=opi5 KBUILD_BUILD_HOST=opi5-build
exec make -C $TOP/build/wt-vop2-uf2 O=$TOP/build/wt-vop2-uf2-out ARCH=arm64 CROSS_COMPILE=$CROSS_COMPILE CC="$KCC" LOCALVERSION= "$@"
