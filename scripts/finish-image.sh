#!/bin/bash
# Recover from the efivars "umount /sys: target is busy" failure: release leftover
# chroot mounts, then assemble the image from the already-built rootfs.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || exec sudo "$0" "$@"
TOP=$(cd "$(dirname "$0")/.." && pwd)
ROOT=$TOP/build/image/rootfs

for m in sys proc dev; do
  if mountpoint -q "$ROOT/$m"; then umount -R "$ROOT/$m"; fi
done
if findmnt -rno TARGET | grep -q "^$ROOT/"; then
  echo "still mounted under $ROOT:"; findmnt -rno TARGET | grep "^$ROOT/"; exit 1
fi
echo "No mounts left under $ROOT"

exec "$TOP/scripts/build-image.sh" --reuse-rootfs
