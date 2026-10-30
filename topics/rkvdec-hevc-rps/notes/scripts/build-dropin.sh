#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Host: build signed rockchip-vdec.ko drop-ins for the board kernel (7.3.0-opi5)
# from opi5/rkvdec-hevc-rps-7.3, with and without the six RPS commits, against
# build/linux's .config, Module.symvers and module signing key (read only).
# Output: work/_out/rkvdec-hevc-rps/modules/{before,after}/rockchip-vdec.ko
set -e -o pipefail
export ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu-
W=~/orangepi5/work/rkvdec-hevc-rps-7.3 B=~/orangepi5/build/wt-rkvdec-hevc-rps-7.3-board
L=~/orangepi5/build/linux O=~/orangepi5/work/_out/rkvdec-hevc-rps/modules
BR=opi5/rkvdec-hevc-rps-7.3 BASE=opi5/integration-7.3
test -z "$(git -C $W status --porcelain --untracked-files=no)" || { echo "$W has local changes" >&2; exit 1; }
mkdir -p $B/certs $O/before $O/after
cp $L/.config $L/Module.symvers $B/
cp $L/certs/signing_key.pem $L/certs/signing_key.x509 $B/certs/
make -s -C $W O=$B LOCALVERSION= olddefconfig
make -s -C $W O=$B LOCALVERSION= -j6 modules_prepare
build() {	# build <ref> <variant>
	git -C $W checkout -q --detach $1
	make -s -C $W O=$B LOCALVERSION= -j6 M=$W/drivers/media/platform/rockchip/rkvdec \
		MO=$B/ext/rkvdec-$2 W=1 modules 2>&1 | { grep -v "Skipping BTF" || true; }
	k=$B/ext/rkvdec-$2/rockchip-vdec.ko
	$B/scripts/sign-file sha512 $B/certs/signing_key.pem $B/certs/signing_key.x509 $k
	install -m644 $k $O/$2/rockchip-vdec.ko
	echo "$2: $(git -C $W rev-parse --short HEAD) $(modinfo -F vermagic $k | cut -d' ' -f1)" \
	     "srcversion=$(modinfo -F srcversion $k) sha256=$(sha256sum $k | cut -c1-16)"
}
trap 'git -C $W checkout -q $BR' EXIT
build $BASE before
build $BR after
