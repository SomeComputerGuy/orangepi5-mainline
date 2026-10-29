#!/bin/bash
# Fetch the pinned upstream sources the build scripts use into $OPI5_SRC
# (default: src/). Nothing third-party is stored in this repository; this is
# where it comes from. See docs/SOURCES.md.
#
# Usage: fetch-sources.sh [linux] [u-boot] [tf-a] [rkbin] [u-boot-upstream]
#        (no argument: all of them except u-boot-upstream)
# Existing trees are left alone (only their pinned commit is checked).
# Shallow clones keep the downloads small (Linux ~250 MB instead of ~5 GB).
set -euo pipefail
. "$(dirname "$0")/env.sh"

# name  url  ref (tag, or "-" for a bare commit)  commit
PINS=(
  "linux https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git v7.3 c03c1a14507dfaf8b856c2608f9ac216021fc222"
  "u-boot https://source.denx.de/u-boot/u-boot.git v2026.10 5508406582f6f7120dce0c4b3059819a41788db2"
  "tf-a https://github.com/ARM-software/arm-trusted-firmware.git v2.15.0 da738d5eae93af342fdc4995dd3c05acb4c9d757"
  "rkbin https://github.com/rockchip-linux/rkbin.git - 3e288fe814e059dd06833495f845cab04ac20a5c"
  # Base for patches/upstream/u-boot (only needed to regenerate those patches)
  "u-boot-upstream https://source.denx.de/u-boot/u-boot.git v2027.01-rc1 dfcfc4c9f78d1743f490a497082a4ec8e058aae8"
)

want=("$@")
[ ${#want[@]} -gt 0 ] || want=(linux u-boot tf-a rkbin)
mkdir -p "$OPI5_SRC"
for w in "${want[@]}"; do
  found=
  for pin in "${PINS[@]}"; do
    read -r name url ref commit <<<"$pin"
    [ "$name" = "$w" ] || continue
    found=1
    dir=$OPI5_SRC/$name
    if [ ! -e "$dir/.git" ]; then
      echo "==> $name: $url ${ref/#-/$commit}"
      if [ "$ref" = - ]; then
        git init -q "$dir"
        git -C "$dir" remote add origin "$url"
        git -C "$dir" fetch -q --depth 1 origin "$commit"
        git -C "$dir" checkout -q FETCH_HEAD
      else
        git -c advice.detachedHead=false clone -q --depth 1 --branch "$ref" "$url" "$dir"
      fi
    fi
    # The build scripts reset linux and tf-a to their tag before patching, so
    # the pinned commit only has to be present (and the tag, if any, match it)
    git -C "$dir" cat-file -e "$commit^{commit}" 2>/dev/null || { echo "$name: commit $commit missing in $dir"; exit 1; }
    if [ "$ref" != - ] && got=$(git -C "$dir" rev-parse -q --verify "$ref^{commit}"); then
      [ "$got" = "$commit" ] || { echo "$name: $ref is $got, expected $commit"; exit 1; }
    fi
    echo "$name: $commit OK"
  done
  [ -n "$found" ] || { echo "unknown source: $w"; exit 1; }
done
