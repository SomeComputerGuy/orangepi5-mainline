#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Build the rkvdec-reset test kernel (build-5 config + KASAN/ODEBUG/lockdep) as
# debs, in its own output dir so build/linux stays the image build.
# Source: work/rkvdec-reset-kbase (v7.3 + patches/linux). Release 7.3.0-opi5-kasan.
set -euo pipefail
TOP=$HOME/orangepi5
SRC=$TOP/work/rkvdec-reset-kbase B=$TOP/build/wt-rkvdec-reset-kasan
OUT=$TOP/work/_out/rkvdec-reset/debs
export ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu-
SYSROOT=$TOP/build/arm64-sysroot LIBDIR=$SYSROOT/usr/lib/aarch64-linux-gnu
export PATH=$TOP/build/xtool:$PATH
KCC="${CROSS_COMPILE}gcc -isystem $SYSROOT/usr/include -isystem $SYSROOT/usr/include/aarch64-linux-gnu -L$LIBDIR -Wl,-rpath-link=$LIBDIR"
export LOCALVERSION= KBUILD_BUILD_USER=opi5 KBUILD_BUILD_HOST=opi5-build
export DEBFULLNAME="Orange Pi 5 mainline build" DEBEMAIL=opi5@invalid
mkdir -p $B $OUT
if [ ! -f $B/.config ]; then
	cp $TOP/build/linux/.config $B/.config
	$SRC/scripts/kconfig/merge_config.sh -m -O $B $B/.config $TOP/work/_out/rkvdec-reset/scripts/kasan.config
	make -C $SRC O=$B CC="$KCC" olddefconfig
fi
for l in $(grep -v '^#' $TOP/work/_out/rkvdec-reset/scripts/kasan.config); do
	grep -qxF "$l" $B/.config || echo "CONFIG MISMATCH: $l"
done
export DEB_BUILD_PROFILES=pkg.linux-upstream.nokerneldbg
make -C $SRC O=$B CC="$KCC" -j"$(nproc)" DPKG_FLAGS=-d KDEB_PKGVERSION=7.3.0-5kasan${KREV:-1} bindeb-pkg
mv $B/../linux-*opi5-kasan*.deb $OUT/ 2>/dev/null || mv $TOP/build/linux-*kasan*.deb $OUT/
ls -l $OUT
