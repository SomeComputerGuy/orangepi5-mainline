#!/bin/bash
# Rebuild Ubuntu's media packages for arm64 with the patches in patches/<source>/:
#   ffmpeg              V4L2 Request API (stateless decoder) hwaccels
#   mpv                 v4l2request hwdec + DRM PRIME interop; needs our ffmpeg
#   gst-plugins-bad1.0  v4l2codecs fixes and stateless H.264/H.265 encoders, kmssink fixes (patches/gstreamer)
#   gst-plugins-good1.0 v4l2transform colorimetry, souphttpsrc HEAD race (patches/gst-plugins-good)
#   alsa-ucm-conf       UCM for the RK3588 HDMI/DP and ES8388 sound cards (Architecture: all)
# Rootless: mmdebstrap --mode=unshare + qemu-user binfmt, no sudo.
# Each source builds in its own persistent arm64 chroot (stonking-arm64-<source>,
# made on first use by arm64-chroot / scripts/build-chroot.sh, kept in
# ~/chroots); every build still starts from a fresh /build tree and runs
# build-dep. OPI5_FRESH_CHROOT=1 bootstraps a throwaway chroot per build instead.
# Usage: build-media-debs.sh [source...]     (default: all of the above, in that order)
#        build-media-debs.sh --prepare-chroot [source...]
#            create the chroots and install the build-deps, without building
# Output: out/debs-media/*.deb plus a Packages index (a flat apt repository that
#         IMAGE_VARIANT=desktop scripts/build-image.sh installs from);
#         OPI5_MEDIA_REPO=DIR puts the repository elsewhere.
#
# patches/<dir>/*.patch are appended to debian/patches/series (upstream code,
# applied by dpkg-source); patches/<dir>/debian/*.patch change the packaging
# itself. <dir> is the source package name, except gstreamer for gst-plugins-bad1.0. The version gets "+opi5.<rev>", so it sorts above the archive version
# it was built from, and the image pins *+opi5* versions (etc/apt/preferences.d).
# When Ubuntu updates one of these packages, bump its version below and rebuild.
set -euo pipefail

if [ "${1:-}" = --in-chroot ]; then
  # Runs inside the build chroot (as the unshared root user): fetch, patch, build.
  src=$2 ver=$3 rev=$4 jobs=$5 pdir_name=${6:-$2} build=${7:-any}
  export DEBIAN_FRONTEND=noninteractive
  mkdir -p /build/debs && cd /build
  # Stock Ubuntu installs also use the -updates and -security pockets: build from (and against) them too, so a
  # rebuild never falls behind an archive (security) update of the same source.
  if [ ! -e /etc/apt/sources.list.d/opi5-pockets.list ]; then
    dist=$(sed -n 's/^VERSION_CODENAME=//p' /etc/os-release)
    for pk in updates security; do
      grep -hE "^deb(-src)? https?://[^ ]+ $dist " /etc/apt/sources.list /etc/apt/sources.list.d/*.list 2>/dev/null |
        sed "s/ $dist / $dist-$pk /"
    done > /etc/apt/sources.list.d/opi5-pockets.list
  fi
  apt-get update -q
  # persistent chroot: catch up with the archive, like a fresh bootstrap would
  if [ -n "${OPI5_PERSISTENT:-}" ]; then apt-get -q -y full-upgrade; fi
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
  # any: the arm64 packages (-B); all: an Architecture: all source (-A)
  if [ "$build" = all ]; then bd=--indep-only bt=-A; else bd=--arch-only bt=-B; fi
  apt-get build-dep -q -y $bd -Pnocheck ./
  if [ -n "${OPI5_DEPS_ONLY:-}" ]; then exit 0; fi
  # ccache (installed and seeded by the host side, see below): compilers of this
  # name in /usr/lib/ccache come first in PATH. Sources are always unpacked at
  # /build, so hits carry over between runs. Cache size is capped to keep the
  # copy in/out cheap. A persistent chroot keeps its cache in OPI5_CCACHE_DIR.
  ccdir=${OPI5_CCACHE_DIR:-/build/opi5-media-ccache}
  if [ -n "${OPI5_CCACHE_DIR:-}" ]; then
    mkdir -p "$ccdir"
    [ -d /usr/lib/ccache ] || apt-get install -q -y ccache
  fi
  if [ -d /usr/lib/ccache ] && [ -d "$ccdir" ]; then
    export PATH=/usr/lib/ccache:$PATH CCACHE_DIR=$ccdir CCACHE_BASEDIR=/build CCACHE_MAXSIZE=3G
  fi
  DEB_BUILD_OPTIONS="nocheck noautodbgsym parallel=$jobs" \
    dpkg-buildpackage $bt -us -uc -Pnocheck
  mv ../*.deb /build/debs/
  exit 0
fi

PREPARE=
if [ "${1:-}" = --prepare-chroot ]; then PREPARE=1; shift; fi
[ "$(id -u)" -ne 0 ] || { echo "run as your normal user (rootless build)"; exit 1; }
SELF=$(readlink -f "$0")
TOP=$(cd "$(dirname "$SELF")/.." && pwd)
REPO=${OPI5_MEDIA_REPO:-$TOP/out/debs-media}
FRESH=${OPI5_FRESH_CHROOT:-0}
[ -z "$PREPARE" ] || FRESH=0
# The persistent chroot manager: the installed arm64-chroot, else this repository's copy
CHROOT_TOOL=$(command -v arm64-chroot || echo "$TOP/scripts/build-chroot.sh")
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
  [gst-plugins-good1.0]=1.28.7-1ubuntu0.1   # stonking-security (CVE-2026-111183), was 1.28.7-1build1
  [alsa-ucm-conf]=1.2.16.1-1ubuntu1
)
declare -A REV=([ffmpeg]=4 [mpv]=2 [gst-plugins-bad1.0]=8 [gst-plugins-good1.0]=3 [alsa-ucm-conf]=1)
declare -A PDIR=([ffmpeg]=ffmpeg [mpv]=mpv [gst-plugins-bad1.0]=gstreamer [gst-plugins-good1.0]=gst-plugins-good [alsa-ucm-conf]=alsa-ucm-conf)
# Architecture: all sources (built with -A); the rest build their arm64 packages
declare -A BUILD=([alsa-ucm-conf]=all)

if [ $# -gt 0 ]; then
  SOURCES=("$@")
else
  SOURCES=(ffmpeg mpv gst-plugins-bad1.0 gst-plugins-good1.0 alsa-ucm-conf)
fi

# apt cache: apt-cacher-ng on 127.0.0.1:3142 is used if it is listening
# (OPI5_APT_PROXY=http://host:port overrides, OPI5_APT_PROXY=none disables). Only
# http is proxied; https sources go direct. The option lands in the build chroot's
# /etc/apt/apt.conf.d/99mmdebstrap (the chroot is thrown away); persistent
# chroots get it per entry (ARM64_CHROOT_APT_PROXY).
APT_PROXY=${OPI5_APT_PROXY:-}
if [ -z "$APT_PROXY" ] && (exec 3<>/dev/tcp/127.0.0.1/3142) 2>/dev/null; then
  APT_PROXY=http://127.0.0.1:3142
fi
APT_PROXY_OPTS=()
if [ -n "$APT_PROXY" ] && [ "$APT_PROXY" != none ]; then
  APT_PROXY_OPTS=(--aptopt="Acquire::http::Proxy \"$APT_PROXY\"" --aptopt='Acquire::https::Proxy "DIRECT"')
  echo "apt cache: using $APT_PROXY"
else
  echo "apt cache: not used (nothing on 127.0.0.1:3142, or OPI5_APT_PROXY=none)"
fi
export ARM64_CHROOT_APT_PROXY=${APT_PROXY:-none}

# ccache for the compiles inside the chroot (OPI5_MEDIA_CCACHE=0 disables). The
# cache lives on the host in $CCACHE_HOST and is copied into each build chroot and
# synced back out afterwards (bind mounts aren't permitted in the user namespace).
# The synced-out copy replaces the host cache, so evicted entries don't pile up; a
# failed build doesn't sync its cache back. Only the cache is exchanged: nothing
# of it ends up in the debs.
# A persistent chroot keeps its own cache inside, at $CCACHE_PERSISTENT.
CCACHE_HOST=$HOME/.cache/opi5-media-ccache   # basename must stay opi5-media-ccache
CCACHE_PERSISTENT=/var/cache/opi5-media-ccache
CCACHE_OPTS=() CCACHE_SYNC=() CCACHE_ENV=()
if [ "${OPI5_MEDIA_CCACHE:-1}" != 0 ] && [ "$FRESH" = 0 ]; then
  CCACHE_ENV=(--env "OPI5_CCACHE_DIR=$CCACHE_PERSISTENT")
  echo "ccache: in each persistent chroot at $CCACHE_PERSISTENT"
elif [ "${OPI5_MEDIA_CCACHE:-1}" != 0 ]; then
  rm -rf "$CCACHE_HOST.new"; mkdir -p "$CCACHE_HOST"
  CCACHE_OPTS=(--include=ccache
    --customize-hook='mkdir -p "$1/build"'
    --customize-hook="copy-in '$CCACHE_HOST' /build")
  CCACHE_SYNC=(--customize-hook="sync-out /build/opi5-media-ccache '$CCACHE_HOST.new'")
  echo "ccache: build chroot uses $CCACHE_HOST"
else
  echo "ccache: not used (OPI5_MEDIA_CCACHE=0)"
fi
mkdir -p "$REPO" "$WORK"
index_repo() {
  (cd "$REPO" && dpkg-scanpackages --multiversion . /dev/null > Packages 2>/dev/null)
}
index_repo
# Fresh chroots: apt runs as the unshared root (a subordinate uid), which can't
# read $HOME, so the local repository is served from a world-readable copy.
# Persistent chroots bind it in read-only (arm64-chroot setup lets that uid
# traverse $HOME).
STAGE=$(mktemp -d /tmp/opi5-media-repo.XXXXXX)
trap 'rm -rf "$STAGE"' EXIT
chmod 755 "$STAGE"

# Persistent chroot for one source: build (or only install build-deps) with a
# fresh /build; the debs come out through a writable bind of $1/debs
build_persistent() {
  local src=$1 w=$2 deps_only=$3
  local name=$SUITE-arm64-$src extra=()
  [ -z "$deps_only" ] || extra=(--env OPI5_DEPS_ONLY=1)
  "$CHROOT_TOOL" ensure "$name" --suite "$SUITE" --mirror "$MIRROR" --components "$COMPONENTS" \
    --keyring /usr/share/keyrings/ubuntu-archive-keyring.gpg --include ccache || return 1
  mkdir -p "$w/debs"; chmod 755 "$w"   # the chroot root must reach $w/debs
  "$CHROOT_TOOL" run --scratch /build --bind-rw "$w/debs:/build/debs" \
    --bind "$pdir:/tmp/opi5-patches" --bind "$SELF:/tmp/$(basename "$SELF")" \
    --local-repo "$REPO" --env OPI5_PERSISTENT=1 "${CCACHE_ENV[@]}" "${extra[@]}" \
    "$name" -- /bin/bash "/tmp/$(basename "$SELF")" --in-chroot "$src" "$ver" "$rev" "$JOBS" "${PDIR[$src]}" "${BUILD[$src]:-any}"
}

for src in "${SOURCES[@]}"; do
  [ -n "${VERSION[$src]:-}" ] || { echo "unknown source package $src"; exit 1; }
  pdir=$TOP/patches/${PDIR[$src]}
  [ -d "$pdir" ] || { echo "missing $pdir"; exit 1; }
  ver=${VERSION[$src]} rev=${REV[$src]}
  # A fresh work directory per run: an interrupted run's mmdebstrap may still finish
  # and sync its debs out later
  w=$(mktemp -d "$WORK/$src.XXXXXX")
  if [ -n "$PREPARE" ]; then
    echo "==> $src: chroot $SUITE-arm64-$src with build-deps (log: $w/build.log)"
    build_persistent "$src" "$w" 1 > "$w/build.log" 2>&1 || { echo "$src failed; see $w/build.log"; tail -20 "$w/build.log"; exit 1; }
    rm -rf "$w"
    continue
  fi
  echo "==> $src $ver+opi5.$rev (log: $w/build.log)"
  if [ "$FRESH" = 0 ]; then
    echo "    persistent chroot $SUITE-arm64-$src"
    build_persistent "$src" "$w" "" > "$w/build.log" 2>&1 || { echo "$src failed; see $w/build.log"; tail -20 "$w/build.log"; exit 1; }
  else
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
    "${APT_PROXY_OPTS[@]}" \
    --include=ca-certificates \
    --setup-hook="mkdir -p \"\$1/tmp\"" \
    --setup-hook="copy-in '$STAGE' /tmp" \
    --customize-hook="copy-in '$pdir' /tmp" \
    --customize-hook="mv \"\$1/tmp/${PDIR[$src]}\" \"\$1/tmp/opi5-patches\"" \
    --customize-hook="copy-in '$SELF' /tmp" \
    "${CCACHE_OPTS[@]}" \
    --customize-hook="chroot \"\$1\" /bin/bash /tmp/$(basename "$SELF") --in-chroot '$src' '$ver' '$rev' '$JOBS' '${PDIR[$src]}' '${BUILD[$src]:-any}'" \
    --customize-hook="sync-out /build/debs '$w/debs'" \
    "${CCACHE_SYNC[@]}" \
    "$SUITE" /dev/null \
    "deb $MIRROR $SUITE $COMPONENTS" \
    "deb-src $MIRROR $SUITE $COMPONENTS" \
    "deb [trusted=yes] file://$STAGE ./" \
    > "$w/build.log" 2>&1 || { echo "$src failed; see $w/build.log"; tail -20 "$w/build.log"; exit 1; }
  if [ -d "$CCACHE_HOST.new" ]; then rm -rf "$CCACHE_HOST"; mv "$CCACHE_HOST.new" "$CCACHE_HOST"; fi
  fi
  # Replace the previous build of this source in the repository
  for d in "$REPO"/*.deb; do
    [ -e "$d" ] || continue
    s=$(dpkg-deb -f "$d" Source); s=${s%% *}
    [ -n "$s" ] || s=$(dpkg-deb -f "$d" Package)
    if [ "$s" = "$src" ]; then rm -f "$d"; fi
  done
  # copy, not mv: debs from a persistent chroot belong to its subordinate root
  cp --preserve=timestamps "$w"/debs/*.deb "$REPO/"
  rm -rf "$w"
  chmod 644 "$REPO"/*.deb
  index_repo
  ls -1 "$REPO" | grep -c '\.deb$' | xargs echo "    repository now has debs:"
done
echo "Done: $REPO"
