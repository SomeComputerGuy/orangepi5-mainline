#!/bin/bash
# Build TF-A BL31 (open source) + mainline U-Boot for Orange Pi 5 (RK3588S)
set -euo pipefail
. "$(dirname "$0")/env.sh"
SRC=$OPI5_SRC OUT=$TOP/out
for s in u-boot tf-a rkbin; do
  [ -e "$SRC/$s/.git" ] || "$TOP/scripts/fetch-sources.sh" "$s"
done
export CROSS_COMPILE=aarch64-linux-gnu-
J=$(nproc)
DDR_BLOB_ORIG=$SRC/rkbin/bin/rk35/rk3588_ddr_lp4_2112MHz_lp5_2400MHz_v1.24.bin

# The DDR init blob prints at 1500000 baud; patch a copy (rkbin's ddrbin_tool,
# only "uart baudrate" set, everything else kept) to match the 115200 console
DDR_WORK=$TOP/build/ddr
DDR_BLOB=$DDR_WORK/$(basename "$DDR_BLOB_ORIG" .bin)_uart115200.bin
mkdir -p "$DDR_WORK"
cp "$DDR_BLOB_ORIG" "$DDR_BLOB"
sed 's/^uart baudrate=.*/uart baudrate=115200/' "$SRC/rkbin/tools/ddrbin_param.txt" > "$DDR_WORK/param.txt"
(cd "$DDR_WORK" && python3 -I "$SRC/rkbin/tools/ddrbin_tool.py" rk3588 param.txt "$DDR_BLOB" >/dev/null)
(cd "$DDR_WORK" && python3 -I "$SRC/rkbin/tools/ddrbin_tool.py" rk3588 -g check.txt "$DDR_BLOB" >/dev/null)
grep -qx 'uart baudrate=115200' "$DDR_WORK/check.txt" || { echo "DDR blob baud patch failed"; exit 1; }

# BL31 (EL3 runtime firmware): "tfa" = mainline TF-A built from source,
# "rkbin" = Rockchip's prebuilt one from rkbin
BL31_SRC=${BL31_SRC:-tfa}
case "$BL31_SRC" in
  tfa)
    # src/tf-a is v2.15.0 plus patches/tf-a/*.patch, re-applied only when the
    # patch set changes (the previous source diff is saved first)
    TFA_BASE=v2.15.0
    mkdir -p "$TOP/build"
    want=$(cd "$TOP/patches/tf-a" && sha256sum ./*.patch)
    if [ "$(cat "$TOP/build/.tf-a-patches-applied" 2>/dev/null)" != "$want" ]; then
      git -C "$SRC/tf-a" diff --binary HEAD > "$TOP/build/src-tf-a-before-patches.diff"
      git -C "$SRC/tf-a" reset -q --hard "$TFA_BASE"
      for p in "$TOP"/patches/tf-a/*.patch; do
        git -C "$SRC/tf-a" apply --index "$p" || { echo "patch failed: $p"; exit 1; }
      done
      echo "$want" > "$TOP/build/.tf-a-patches-applied"
    fi
    make -C "$SRC/tf-a" -j"$J" PLAT=rk3588 bl31
    BL31=$SRC/tf-a/build/rk3588/release/bl31/bl31.elf ;;
  rkbin) BL31=$SRC/rkbin/bin/rk35/rk3588_bl31_v1.56.elf ;;
  *) echo "BL31_SRC must be tfa or rkbin"; exit 1 ;;
esac

# M.2 slot mode (one lane, shared by PCIe and SATA):
#   auto - try PCIe/NVMe first, then SATA, and pass Linux the matching DTB
#   sata - SATA only;  nvme - PCIe only (stock upstream)
M2_MODE=${M2_MODE:-auto}
BOARD_DTSI=arch/arm/dts/rk3588s-orangepi-5-u-boot.dtsi
EXTRA_DTSIS=(rk3588s-orangepi-5-sata-u-boot.dtsi rk3588s-orangepi-5-auto-u-boot.dtsi
             rk3588s-orangepi-5-cpuclk-u-boot.dtsi)
# Runs before the boot scan; with "fdtdir" in extlinux.conf, U-Boot loads
# $fdtdir/$fdtfile, so this picks the Linux DTB for the drive in the slot
M2_DETECT='if pci enum && nvme scan && nvme dev 0; then setenv opi5_m2 nvme; elif scsi scan && scsi dev 0; then setenv opi5_m2 sata; setenv fdtfile rockchip/rk3588s-orangepi-5-sata.dtb; else setenv opi5_m2 none; fi; echo M.2 slot: ${opi5_m2}'

cd "$SRC/u-boot"
git checkout -q -- "$BOARD_DTSI"
for f in "${EXTRA_DTSIS[@]}"; do rm -f "arch/arm/dts/$f"; done
case "$M2_MODE" in
  auto|sata)
    f=rk3588s-orangepi-5-$M2_MODE-u-boot.dtsi
    cp "$TOP/patches/u-boot/$f" arch/arm/dts/
    printf '\n#include "%s"\n' "$f" >> "$BOARD_DTSI" ;;
  nvme) ;;
  *) echo "M2_MODE must be auto, sata or nvme"; exit 1 ;;
esac
# Big-core clocks up before Linux (always)
cp "$TOP/patches/u-boot/rk3588s-orangepi-5-cpuclk-u-boot.dtsi" arch/arm/dts/
printf '\n#include "%s"\n' rk3588s-orangepi-5-cpuclk-u-boot.dtsi >> "$BOARD_DTSI"

make orangepi-5-rk3588s_defconfig
# OpenSSL 4 (Ubuntu 26.10 host) dropped the ENGINE API used by the FIT-signing
# host tools; we don't sign images, so build the tools without libcrypto
# (kwbimage, a Marvell-only image format, force-selects libcrypto).
scripts/config --disable TOOLS_KWBIMAGE --disable TOOLS_LIBCRYPTO
# Lets the SATA dtsi hold the M.2 slot's power enable pin high
scripts/config --enable GPIO_HOG
# Console at 115200 (upstream default is 1500000, which many USB-serial
# adapters, e.g. the original CP2102, can't do). The DDR init blob still
# prints its first few lines at 1500000.
scripts/config --set-val BAUDRATE 115200
if [ "$M2_MODE" = auto ]; then
  scripts/config --enable USE_PREBOOT --set-str PREBOOT "$M2_DETECT"
fi
make olddefconfig
make -j"$J" BL31="$BL31" ROCKCHIP_TPL="$DDR_BLOB"

mkdir -p "$OUT"
cp u-boot-rockchip.bin u-boot-rockchip-spi.bin "$OUT/"
printf 'M.2 mode: %s\nBL31: %s\n' "$M2_MODE" "$BL31_SRC" > "$OUT/u-boot-m2-mode.txt"
ls -l "$OUT"/u-boot-rockchip*.bin
