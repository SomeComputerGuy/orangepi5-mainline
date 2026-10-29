#!/bin/sh
# Build, strip and sign the modules for the 7.3.0-opi5 board kernel.
set -e
export ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu-
W=$HOME/orangepi5/work/vepu121-h264enc B=$HOME/orangepi5/build/wt-vepu121-h264enc
O=$HOME/orangepi5/work/_out/vepu121-h264enc/modules
make -C $W O=$B LOCALVERSION= -j6 W=1 M=$W/drivers/media/v4l2-core MO=$B/ext/v4l2 modules
make -C $W O=$B LOCALVERSION= -j6 W=1 M=$W/drivers/media/platform/verisilicon MO=$B/ext/hantro \
	KBUILD_EXTRA_SYMBOLS=$B/ext/v4l2/Module.symvers modules
rm -rf $O; mkdir -p $O
for k in videodev v4l2-h264 v4l2-h264-enc v4l2-h264-enc-rbsp v4l2-h264-enc-rc; do cp $B/ext/v4l2/$k.ko $O/; done
cp $B/ext/hantro/hantro-vpu.ko $O/
for k in $O/*.ko; do
	aarch64-linux-gnu-strip --strip-debug $k
	$B/scripts/sign-file sha512 $B/certs/signing_key.pem $B/certs/signing_key.x509 $k
	tail -c 28 $k | grep -q "Module signature appended" || { echo "unsigned: $k"; exit 1; }
done
# Do not strip after signing: it removes the signature.
(cd $O && sha256sum *.ko > SHA256SUMS)
echo "signed:"; ls -la $O
