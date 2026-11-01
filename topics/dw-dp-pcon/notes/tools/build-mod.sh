#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
# Build an external-module copy of a kernel dir against build/linux (matches board 7.3.0-opi5)
set -e
TOP=$HOME/orangepi5
export ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- LOCALVERSION=
SYSROOT=$TOP/build/arm64-sysroot; LIBDIR=$SYSROOT/usr/lib/aarch64-linux-gnu
export PATH=$TOP/build/xtool:$PATH
KCC="${CROSS_COMPILE}gcc -isystem $SYSROOT/usr/include -isystem $SYSROOT/usr/include/aarch64-linux-gnu -L$LIBDIR -Wl,-rpath-link=$LIBDIR"
make -C $TOP/build/linux CC="$KCC" M="$1" modules
