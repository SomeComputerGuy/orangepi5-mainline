#!/bin/bash
# Rebuild Ubuntu's media packages for arm64 with the patches in patches/<source>/:
#   ffmpeg              V4L2 Request API (stateless decoder) hwaccels
#   mpv                 v4l2request hwdec + DRM PRIME interop; needs our ffmpeg
#   gst-plugins-bad1.0  v4l2codecs and kmssink fixes (patches/gstreamer)
#   gst-plugins-good1.0 v4l2transform colorimetry, souphttpsrc HEAD race (patches/gst-plugins-good)
# Rootless: mmdebstrap --mode=unshare + qemu-user binfmt, no sudo.
# Usage: build-media-debs.sh [source...]     (default: all of the above, in that order)
# Output: out/debs-media/*.deb plus a Packages index (a flat apt repository that
#         IMAGE_VARIANT=desktop scripts/build-image.sh installs from).
#
# patches/<dir>/*.patch are appended to debian/patches/series (upstream code,
# applied by dpkg-source); patches/<dir>/debian/*.patch change the packaging
# itself. <dir> is the source package name, except gstreamer for gst-plugins-bad1.0. The version gets "+opi5.<rev>", so it sorts above the archive version
# it was built from, and the image pins *+opi5* versions (etc/apt/preferences.d).
# When Ubuntu updates one of these packages, bump its version below and rebuild.
set -euo pipefail

if [ "${1:-}" = --in-chroot ]; then
  # Runs inside the build chroot (as the unshared root user): fetch, patch, build.
  src=$2 ver=$3 rev=$4 jobs=$5 pdir_name=${6:-$2}
  export DEBIAN_FRONTEND=noninteractive
  mkdir -p /build/debs && cd /build
  apt-get update -q
  apt-get source -q --only-source "$src=$ver"
  dir=$(find . -maxdepth 1 -mindepth 1 -type d -name "${src}-*" | head -1)
  cd "$dir"
  mkdir -p debian/patches; touch debian/patches/series
  for p in /tmp/opi5-patches/*.patch; do
    [ -e "$p" ] || continue
    cp "$p" "debian/patches/opi5-$(basename "$p")"
    echo "opi5-$(basename "$p")" >> debian/patches/series
  done
  for p in /tmp/opi5-patches/debian/*.patch; do
    [ -e "$p" ] || continue
    patch -p1 --no-backup-if-mismatch < "$p"
  done
  {
    echo "$src ($ver+opi5.$rev) $(dpkg-parsechangelog -S Distribution); urgency=medium"
    echo
    echo "  * Orange Pi 5 (RK3588) rebuild with the orangepi5 build's patches/$pdir_name:"
    for p in /tmp/opi5-patches/*.patch /tmp/opi5-patches/debian/*.patch; do
      [ -e "$p" ] || continue
      echo "    - $(sed -n 's/^Subject: \(\[PATCH[^]]*\] \)\{0,1\}//p' "$p" | head -1)"
    done
    echo
    echo " -- Arun Iyengar <aiyengar1990@gmail.com>  $(date -R)"
    echo
    cat debian/changelog
  } > debian/changelog.new
  mv debian/changelog.new debian/changelog
  apt-get build-dep -q -y --arch-only -Pnocheck ./
  DEB_BUILD_OPTIONS="nocheck noautodbgsym parallel=$jobs" \
    dpkg-buildpackage -B -us -uc -Pnocheck
  mv ../*.deb /build/debs/
  exit 0
fi

[ "$(id -u)" -ne 0 ] || { echo "run as your normal user (rootless build)"; exit 1; }
SELF=$(readlink -f "$0")
TOP=$(cd "$(dirname "$SELF")/.." && pwd)
REPO=$TOP/out/debs-media
WORK=$TOP/build/media
SUITE=stonking
MIRROR=http://ports.ubuntu.com/ubuntu-ports
COMPONENTS="main restricted universe multiverse"
JOBS=${MEDIA_JOBS:-6}          # the host is shared; qemu-user runs one CPU per job
# Archive version each patch set was made for, and our revision of it
declare -A VERSION=(
  [ffmpeg]=7:8.1.2-2ubuntu2
  [mpv]=0.41.0-2ubuntu5
  [gst-plugins-bad1.0]=1.28.6-1ubuntu1
  [gst-plugins-good1.0]=1.28.7-1build1
)
declare -A REV=([ffmpeg]=2 [mpv]=1 [gst-plugins-bad1.0]=3 [gst-plugins-good1.0]=1)
declare -A PDIR=([ffmpeg]=ffmpeg [mpv]=mpv [gst-plugins-bad1.0]=gstreamer [gst-plugins-good1.0]=gst-plugins-good)

if [ $# -gt 0 ]; then
  SOURCES=("$@")
else
  SOURCES=(ffmpeg mpv gst-plugins-bad1.0 gst-plugins-good1.0)
fi

mkdir -p "$REPO" "$WORK"
index_repo() {
  (cd "$REPO" && dpkg-scanpackages --multiversion . /dev/null > Packages 2>/dev/null)
}
index_repo
# apt runs as the unshared root (a subordinate uid), which can't read $HOME, so
# the local repository is served from a world-readable copy
STAGE=$(mktemp -d /tmp/opi5-media-repo.XXXXXX)
trap 'rm -rf "$STAGE"' EXIT
chmod 755 "$STAGE"

for src in "${SOURCES[@]}"; do
  [ -n "${VERSION[$src]:-}" ] || { echo "unknown source package $src"; exit 1; }
  pdir=$TOP/patches/${PDIR[$src]}
  [ -d "$pdir" ] || { echo "missing $pdir"; exit 1; }
  ver=${VERSION[$src]} rev=${REV[$src]}
  # A fresh work directory per run: an interrupted run's mmdebstrap may still finish
  # and sync its debs out later
  w=$(mktemp -d "$WORK/$src.XXXXXX")
  echo "==> $src $ver+opi5.$rev (log: $w/build.log)"
  rm -f "$STAGE"/*
  cp "$REPO"/Packages "$STAGE"/
  for d in "$REPO"/*.deb; do if [ -e "$d" ]; then cp "$d" "$STAGE"/; fi; done
  chmod -R a+rX "$STAGE"
  # The local repository is a file:// mirror, so mpv's build-deps resolve to our
  # libav*-dev rather than Ubuntu's. The outer apt reads it at $STAGE on the host,
  # apt inside the chroot at the same path in the chroot (copy-in; bind mounts
  # aren't permitted in the user namespace).
  mmdebstrap --mode=unshare --arch=arm64 --variant=buildd \
    --keyring=/usr/share/keyrings/ubuntu-archive-keyring.gpg \
    --aptopt='APT::Install-Recommends "false"' \
    --dpkgopt=force-unsafe-io \
    --include=ca-certificates \
    --setup-hook="mkdir -p \"\$1/tmp\"" \
    --setup-hook="copy-in '$STAGE' /tmp" \
    --customize-hook="copy-in '$pdir' /tmp" \
    --customize-hook="mv \"\$1/tmp/${PDIR[$src]}\" \"\$1/tmp/opi5-patches\"" \
    --customize-hook="copy-in '$SELF' /tmp" \
    --customize-hook="chroot \"\$1\" /bin/bash /tmp/$(basename "$SELF") --in-chroot '$src' '$ver' '$rev' '$JOBS' '${PDIR[$src]}'" \
    --customize-hook="sync-out /build/debs '$w/debs'" \
    "$SUITE" /dev/null \
    "deb $MIRROR $SUITE $COMPONENTS" \
    "deb-src $MIRROR $SUITE $COMPONENTS" \
    "deb [trusted=yes] file://$STAGE ./" \
    > "$w/build.log" 2>&1 || { echo "$src failed; see $w/build.log"; tail -20 "$w/build.log"; exit 1; }
  # Replace the previous build of this source in the repository
  for d in "$REPO"/*.deb; do
    [ -e "$d" ] || continue
    s=$(dpkg-deb -f "$d" Source); s=${s%% *}
    [ -n "$s" ] || s=$(dpkg-deb -f "$d" Package)
    if [ "$s" = "$src" ]; then rm -f "$d"; fi
  done
  mv "$w"/debs/*.deb "$REPO/"
  rm -rf "$w"
  chmod 644 "$REPO"/*.deb
  index_repo
  ls -1 "$REPO" | grep -c '\.deb$' | xargs echo "    repository now has debs:"
done
echo "Done: $REPO"
