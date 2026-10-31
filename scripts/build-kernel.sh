#!/bin/bash
# Build mainline Linux as Debian packages (linux-image/linux-headers) for arm64,
# configured like Ubuntu's generic arm64 kernel plus Orange Pi 5 tweaks
set -euo pipefail
. "$(dirname "$0")/env.sh"
SRC=$OPI5_SRC/linux OUT=$TOP/out BUILD=$TOP/build/linux
[ -e "$SRC/.git" ] || "$TOP/scripts/fetch-sources.sh" linux
export ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu-
# Two builds in the same O= directory corrupt each other's objects
mkdir -p "$TOP/build"
exec 9>"$TOP/build/.kernel-build.lock"
flock -n 9 || { echo "another kernel build is running"; exit 1; }
# Ubuntu kernel whose config is the base (from ports.ubuntu.com)
UBUNTU_KVER=${UBUNTU_KVER:-7.3.0-10}
UBUNTU_PKG=linux-modules-${UBUNTU_KVER}-generic_${UBUNTU_KVER}.${UBUNTU_KVER##*-}_arm64.deb
KCONF_DIR=$TOP/build/ubuntu-kconfig
UBUNTU_CONFIG=$KCONF_DIR/boot/config-${UBUNTU_KVER}-generic

if [ ! -f "$UBUNTU_CONFIG" ]; then
  mkdir -p "$KCONF_DIR"
  curl -sSfo "$KCONF_DIR/$UBUNTU_PKG" "http://ports.ubuntu.com/ubuntu-ports/pool/main/l/linux/$UBUNTU_PKG"
  dpkg-deb --fsys-tarfile "$KCONF_DIR/$UBUNTU_PKG" | tar -x -C "$KCONF_DIR" "./boot/config-${UBUNTU_KVER}-generic"
fi

# linux-headers ships arm64 builds of scripts/ (sign-file, gendwarfksyms) for
# DKMS, which link arm64 libcrypto, libdw, libelf and zlib. Unpack those into a
# private sysroot (no host apt changes). builddeb rebuilds scripts/ with a bare
# "aarch64-linux-gnu-gcc" (no extra flags), so a wrapper of that name, first in
# PATH, adds the sysroot paths. The kernel itself includes none of these headers.
SYSROOT=$TOP/build/arm64-sysroot
LIBDIR=$SYSROOT/usr/lib/aarch64-linux-gnu
SYSROOT_PKGS=(libssl-dev libssl4 libdw-dev libdw1t64 libelf-dev libelf1t64
              zlib1g-dev zlib1g libzstd1 liblzma5 libbz2-1.0)
mkdir -p "$SYSROOT/debs"
for pkg in "${SYSROOT_PKGS[@]}"; do
  [ -f "$SYSROOT/debs/.$pkg" ] && continue
  # Same pool path as the host's amd64 package, arm64 file on ports
  f=$(apt-cache show "$pkg" | awk '/^Filename:/{print $2; exit}')
  [ -n "$f" ] || { echo "no package $pkg"; exit 1; }
  deb=${f%_*}_arm64.deb
  curl -sSfo "$SYSROOT/debs/${deb##*/}" "http://ports.ubuntu.com/ubuntu-ports/$deb"
  dpkg-deb -x "$SYSROOT/debs/${deb##*/}" "$SYSROOT"
  touch "$SYSROOT/debs/.$pkg"
done
XTOOL=$TOP/build/xtool
mkdir -p "$XTOOL"
cat > "$XTOOL/${CROSS_COMPILE}gcc" <<WRAP
#!/bin/sh
exec /usr/bin/${CROSS_COMPILE}gcc -I$SYSROOT/usr/include -I$SYSROOT/usr/include/aarch64-linux-gnu -L$LIBDIR -Wl,-rpath-link=$LIBDIR "\$@"
WRAP
chmod +x "$XTOOL/${CROSS_COMPILE}gcc"
export PATH=$XTOOL:$PATH
# Kept identical to earlier builds so kbuild doesn't see a changed compiler
# command line and rebuild everything (the wrapper supplies the paths anyway)
KCC="${CROSS_COMPILE}gcc -isystem $SYSROOT/usr/include -isystem $SYSROOT/usr/include/aarch64-linux-gnu -L$LIBDIR -Wl,-rpath-link=$LIBDIR"
# Release is exactly <version>-opi5: no "+"/"-dirty" for our patched tree
export LOCALVERSION=
# Keep the build machine's user/host name out of the binaries (/proc/version,
# the deb Maintainer field)
export KBUILD_BUILD_USER=${KBUILD_BUILD_USER:-opi5}
export KBUILD_BUILD_HOST=${KBUILD_BUILD_HOST:-opi5-build}
export DEBFULLNAME=${DEBFULLNAME:-${OPI5_NAME:-Orange Pi 5 mainline build}}
export DEBEMAIL=${DEBEMAIL:-${OPI5_EMAIL:-opi5@invalid}}

# Board patches: src/linux is v7.3 plus patches/linux/*.patch, applied in order.
# OPI5_EXTRA=1 also applies patches/linux-extra/*.patch on top and merges
# scripts/opi5-extra.config: hardware support that hasn't been tested on a board
# yet (USB-C DP alt mode, MIPI DSI LCD and MIPI CSI camera overlays, rkisp2).
# Re-applied only when the patch set changes, so unchanged sources keep their
# mtimes and the build stays incremental. The previous source diff is saved first.
BASE=v7.3
OPI5_EXTRA=${OPI5_EXTRA:-0}
PATCH_DIRS=("$TOP/patches/linux")
CONFIGS=("$TOP/scripts/opi5.config")
if [ "$OPI5_EXTRA" = 1 ]; then
  PATCH_DIRS+=("$TOP/patches/linux-extra")
  CONFIGS+=("$TOP/scripts/opi5-extra.config")
  echo "OPI5_EXTRA=1: also applying patches/linux-extra (not tested on hardware)"
fi
mkdir -p "$BUILD"
want=$(for d in "${PATCH_DIRS[@]}"; do (cd "$d" && sha256sum ./*.patch | sed "s|\./|${d##*/}/|"); done)
if [ "$(cat "$BUILD/.patches-applied" 2>/dev/null)" != "$want" ]; then
  git -C "$SRC" diff --binary HEAD > "$BUILD/src-linux-before-patches.diff"
  git -C "$SRC" reset -q --hard "$BASE"
  # a previous run that stopped half-way may have left files its patches created
  git -C "$SRC" clean -fdq
  for d in "${PATCH_DIRS[@]}"; do
    for p in "$d"/*.patch; do
      git -C "$SRC" apply --index "$p" || { echo "patch failed: $p"; exit 1; }
    done
  done
  echo "$want" > "$BUILD/.patches-applied"
fi

mkdir -p "$BUILD" "$OUT/debs"
cp "$UBUNTU_CONFIG" "$BUILD/.config"
"$SRC/scripts/kconfig/merge_config.sh" -m -O "$BUILD" "$BUILD/.config" "${CONFIGS[@]}"
make -C "$SRC" O="$BUILD" CC="$KCC" olddefconfig
# Report fragment options that didn't stick (renamed/missing deps)
cat "${CONFIGS[@]}" | grep -v '^#' | grep . | while IFS= read -r l; do
  k=${l%%=*}; v=${l#*=}
  if [ "$v" = n ]; then
    if grep -q "^$k=" "$BUILD/.config"; then echo "CONFIG MISMATCH: $l"; fi
  elif ! grep -qxF "$l" "$BUILD/.config"; then
    echo "CONFIG MISMATCH: $l -> $(grep "^$k=\|$k is not set" "$BUILD/.config")"
  fi
done
# The arm64 libssl-dev build-dep is satisfied by $SYSROOT, which dpkg can't see,
# so skip dpkg's build-dep check (-d).
# Debug info is kept for BTF (eBPF tooling); skip the huge -dbg package
export DEB_BUILD_PROFILES=pkg.linux-upstream.nokerneldbg
make -C "$SRC" O="$BUILD" CC="$KCC" -j"$(nproc)" DPKG_FLAGS=-d KDEB_PKGVERSION="$(make -s -C "$SRC" kernelversion)-7" bindeb-pkg
mv "$BUILD"/../linux-*.deb "$OUT/debs/"
ls -l "$OUT/debs"
