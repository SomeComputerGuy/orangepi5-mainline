#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Build the VA-API driver for the V4L2 stateless decoders (v4l2-request-va-driver,
# our fork of megi's libva-v4l2_request) as an arm64 .deb, from a pinned commit,
# with the source package's own debian/ directory.
# Rootless: mmdebstrap --mode=unshare + qemu-user binfmt, no sudo (like
# build-media-debs.sh). The desktop image (build-image.sh --variant desktop)
# installs it from out/debs-media.
# Builds in the persistent arm64 chroot stonking-arm64-v4l2-request-va-driver
# (made on first use by arm64-chroot / scripts/build-chroot.sh, kept in
# ~/chroots) from a fresh /build tree, running build-dep each time.
#
# Usage: build-va-driver.sh [--prepare-chroot]
#   --prepare-chroot    only create the chroot and install the build-deps
#   VA_DRIVER_SRC=DIR   use this git checkout instead of cloning into src/
#   VA_DRIVER_COMMIT=SHA build another commit (default: the pin below)
#   OPI5_FRESH_CHROOT=1 bootstrap a throwaway chroot for this build instead
#   OPI5_MEDIA_REPO=DIR put the deb and the index there instead of out/debs-media
# Output: out/debs-media/v4l2-request-va-driver_<version>_arm64.deb (+ Packages index)
set -euo pipefail

if [ "${1:-}" = --in-chroot ]; then
  # Runs inside the build chroot (as the unshared root user)
  jobs=$2
  export DEBIAN_FRONTEND=noninteractive
  mkdir -p /build/src /build/debs && cd /build/src
  tar -xf /tmp/va-driver-src.tar
  apt-get update -q
  # persistent chroot: catch up with the archive, like a fresh bootstrap would
  if [ -n "${OPI5_PERSISTENT:-}" ]; then apt-get -q -y full-upgrade; fi
  apt-get build-dep -q -y --arch-only ./
  if [ -n "${OPI5_DEPS_ONLY:-}" ]; then exit 0; fi
  DEB_BUILD_OPTIONS="nocheck noautodbgsym parallel=$jobs" dpkg-buildpackage -B -us -uc
  mv ../*.deb /build/debs/
  exit 0
fi

# Source: https://github.com/SomeComputerGuy/libva-v4l2_request, branch opi5/main
# (base: https://xff.cz/git/libva-v4l2_request cac6ece + three of sofus13's HEVC fixes)
URL=https://github.com/SomeComputerGuy/libva-v4l2_request.git
COMMIT=${VA_DRIVER_COMMIT:-e912dc47684e32276b9594c593855a79fae474f6}

PREPARE=
if [ "${1:-}" = --prepare-chroot ]; then PREPARE=1; shift; fi
[ "$(id -u)" -ne 0 ] || { echo "run as your normal user (rootless build)"; exit 1; }
SELF=$(readlink -f "$0")
TOP=$(cd "$(dirname "$SELF")/.." && pwd)
SRC=${VA_DRIVER_SRC:-${OPI5_SRC:-$TOP/src}/libva-v4l2-request}
REPO=${OPI5_MEDIA_REPO:-$TOP/out/debs-media}
FRESH=${OPI5_FRESH_CHROOT:-0}
[ -z "$PREPARE" ] || FRESH=0
# The persistent chroot manager: the installed arm64-chroot, else this repository's copy
CHROOT_TOOL=$(command -v arm64-chroot || echo "$TOP/scripts/build-chroot.sh")
WORK=$TOP/build/va-driver
SUITE=stonking
MIRROR=http://ports.ubuntu.com/ubuntu-ports
COMPONENTS="main restricted universe multiverse"
JOBS=${MEDIA_JOBS:-6}
CHROOT=$SUITE-arm64-v4l2-request-va-driver

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
if [ "$FRESH" = 0 ]; then
  echo "    persistent chroot $CHROOT"
  extra=()
  [ -z "$PREPARE" ] || extra=(--env OPI5_DEPS_ONLY=1)
  mkdir -p "$w/debs"; chmod 755 "$w"   # the chroot root must reach $w/debs
  { "$CHROOT_TOOL" ensure "$CHROOT" --suite "$SUITE" --mirror "$MIRROR" --components "$COMPONENTS" \
      --keyring /usr/share/keyrings/ubuntu-archive-keyring.gpg &&
    "$CHROOT_TOOL" run --scratch /build --bind-rw "$w/debs:/build/debs" \
      --bind "$STAGE/va-driver-src.tar:/tmp/va-driver-src.tar" \
      --bind "$STAGE/build-va-driver.sh:/tmp/build-va-driver.sh" \
      --env OPI5_PERSISTENT=1 "${extra[@]}" \
      "$CHROOT" -- /bin/bash /tmp/build-va-driver.sh --in-chroot "$JOBS"
  } > "$w/build.log" 2>&1 || { echo "build failed; see $w/build.log"; tail -20 "$w/build.log"; exit 1; }
  if [ -n "$PREPARE" ]; then rm -rf "$w"; echo "Done: $CHROOT has the build-deps"; exit 0; fi
else
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
fi
rm -f "$REPO"/v4l2-request-va-driver_*.deb
# copy, not mv: debs from a persistent chroot belong to its subordinate root
cp --preserve=timestamps "$w"/debs/v4l2-request-va-driver_*.deb "$REPO/"
rm -rf "$w"
chmod 644 "$REPO"/*.deb
(cd "$REPO" && dpkg-scanpackages --multiversion . /dev/null > Packages 2>/dev/null)
ls -1 "$REPO"/v4l2-request-va-driver_*.deb
echo "Done: $REPO"
