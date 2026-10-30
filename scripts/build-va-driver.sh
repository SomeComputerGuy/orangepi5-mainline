#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Build the VA-API driver for the V4L2 stateless decoders (v4l2-request-va-driver,
# our fork of megi's libva-v4l2_request) as an arm64 .deb, from a pinned commit,
# with the source package's own debian/ directory.
# Rootless: mmdebstrap --mode=unshare + qemu-user binfmt, no sudo (like
# build-media-debs.sh). The desktop image (build-image.sh --variant desktop)
# installs it from out/debs-media.
#
# Usage: build-va-driver.sh
#   VA_DRIVER_SRC=DIR   use this git checkout instead of cloning into src/
#   VA_DRIVER_COMMIT=SHA build another commit (default: the pin below)
# Output: out/debs-media/v4l2-request-va-driver_<version>_arm64.deb (+ Packages index)
set -euo pipefail

if [ "${1:-}" = --in-chroot ]; then
  # Runs inside the build chroot (as the unshared root user)
  jobs=$2
  export DEBIAN_FRONTEND=noninteractive
  mkdir -p /build/src /build/debs && cd /build/src
  tar -xf /tmp/va-driver-src.tar
  apt-get update -q
  apt-get build-dep -q -y --arch-only ./
  DEB_BUILD_OPTIONS="nocheck noautodbgsym parallel=$jobs" dpkg-buildpackage -B -us -uc
  mv ../*.deb /build/debs/
  exit 0
fi

# Source: https://github.com/SomeComputerGuy/libva-v4l2_request, branch opi5/main
# (base: https://xff.cz/git/libva-v4l2_request cac6ece + three of sofus13's HEVC fixes)
URL=https://github.com/SomeComputerGuy/libva-v4l2_request.git
COMMIT=${VA_DRIVER_COMMIT:-069af0906f8803047457309d8e1d46f861a1c0d0}

[ "$(id -u)" -ne 0 ] || { echo "run as your normal user (rootless build)"; exit 1; }
SELF=$(readlink -f "$0")
TOP=$(cd "$(dirname "$SELF")/.." && pwd)
SRC=${VA_DRIVER_SRC:-${OPI5_SRC:-$TOP/src}/libva-v4l2-request}
REPO=$TOP/out/debs-media
WORK=$TOP/build/va-driver
SUITE=stonking
MIRROR=http://ports.ubuntu.com/ubuntu-ports
COMPONENTS="main restricted universe multiverse"
JOBS=${MEDIA_JOBS:-6}

if [ ! -e "$SRC/.git" ]; then
  echo "==> cloning $URL into $SRC"
  git init -q "$SRC"
  git -C "$SRC" remote add origin "$URL"
fi
if ! git -C "$SRC" cat-file -e "$COMMIT^{commit}" 2>/dev/null; then
  git -C "$SRC" fetch -q --depth 1 origin "$COMMIT"
fi
echo "==> v4l2-request-va-driver at $COMMIT"

mkdir -p "$REPO" "$WORK"
w=$(mktemp -d "$WORK/build.XXXXXX")
# apt in the chroot runs as a subordinate uid that can't read $HOME: stage the
# source in a world-readable directory
STAGE=$(mktemp -d /tmp/opi5-va-driver.XXXXXX)
trap 'rm -rf "$STAGE"' EXIT
chmod 755 "$STAGE"
git -C "$SRC" archive --format=tar -o "$STAGE/va-driver-src.tar" "$COMMIT"
cp "$SELF" "$STAGE/build-va-driver.sh"
chmod -R a+rX "$STAGE"
echo "    log: $w/build.log"
mmdebstrap --mode=unshare --arch=arm64 --variant=buildd \
  --keyring=/usr/share/keyrings/ubuntu-archive-keyring.gpg \
  --aptopt='APT::Install-Recommends "false"' \
  --dpkgopt=force-unsafe-io \
  --include=ca-certificates \
  --setup-hook="mkdir -p \"\$1/tmp\"" \
  --customize-hook="upload '$STAGE/va-driver-src.tar' /tmp/va-driver-src.tar" \
  --customize-hook="upload '$STAGE/build-va-driver.sh' /tmp/build-va-driver.sh" \
  --customize-hook="chroot \"\$1\" /bin/bash /tmp/build-va-driver.sh --in-chroot '$JOBS'" \
  --customize-hook="sync-out /build/debs '$w/debs'" \
  "$SUITE" /dev/null \
  "deb $MIRROR $SUITE $COMPONENTS" \
  "deb-src $MIRROR $SUITE $COMPONENTS" \
  > "$w/build.log" 2>&1 || { echo "build failed; see $w/build.log"; tail -20 "$w/build.log"; exit 1; }
rm -f "$REPO"/v4l2-request-va-driver_*.deb
mv "$w"/debs/v4l2-request-va-driver_*.deb "$REPO/"
rm -rf "$w"
chmod 644 "$REPO"/*.deb
(cd "$REPO" && dpkg-scanpackages --multiversion . /dev/null > Packages 2>/dev/null)
ls -1 "$REPO"/v4l2-request-va-driver_*.deb
echo "Done: $REPO"
