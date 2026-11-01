#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
# Delete the retired opi5/* branches from the kernel fork. Each one is deleted
# only if the fork has its preserving tag at exactly the same commit, checked
# right before deleting; anything else is skipped and reported.
#   tools/delete-retired-branches.sh        # shows the plan, asks once
#   tools/delete-retired-branches.sh --yes
set -euo pipefail
REPO=$(cd "$(dirname "$0")/.." && pwd)
MIRROR=$REPO/.work/linux
REMOTE=${OPI5_FORK_PUSH_URL:-git@github.com:SomeComputerGuy/linux.git}
YES=0; [ "${1:-}" = --yes ] && YES=1

# retired branch -> tag that preserves its tip
PAIRS=(
  "opi5/image-7.3        image-7.3.0-8"
  "opi5/image-7.3-extra  image-7.3.0-8-extra"
  "opi5/image-k6         image-7.3.0-6"
  "opi5/image-k7         image-7.3.0-7"
  "opi5/integration      archive/integration"
  "opi5/rkvdec-ccu-base  archive/rkvdec-ccu-base"
  "opi5/dw-dp-redetect   archive/dw-dp-redetect"
)

refs=$(git ls-remote "$REMOTE")
sha() { awk -v r="$1" '$2 == r { print $1 }' <<<"$refs"; }

del=()
for p in "${PAIRS[@]}"; do
  read -r b t <<<"$p"
  bs=$(sha "refs/heads/$b"); ts=$(sha "refs/tags/$t^{}")
  if [ -z "$bs" ]; then echo "  gone     $b"; continue; fi
  if [ -z "$ts" ] || [ "$bs" != "$ts" ]; then
    echo "  SKIP     $b (tag $t ${ts:+points elsewhere}${ts:-missing})"; continue
  fi
  echo "  delete   $b  (kept as tag $t, ${bs:0:12})"
  del+=("$b")
done
[ ${#del[@]} -gt 0 ] || { echo "nothing to delete"; exit 0; }
if [ $YES = 0 ]; then
  read -r -p "delete these ${#del[@]} branches from $REMOTE? [y/N] " a
  [ "$a" = y ] || [ "$a" = Y ] || { echo "nothing deleted"; exit 0; }
fi
git -C "$MIRROR" push "$REMOTE" --delete "${del[@]}"
echo "opi5/* branches on the fork now: $(git ls-remote --heads "$REMOTE" 'opi5/*' | wc -l)"
