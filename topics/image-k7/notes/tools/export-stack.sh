#!/bin/bash
# Export opi5/integration-7.3 (and -extra) as numbered patches.
# Usage: export-stack.sh <repo-worktree> <main-out-dir> <extra-out-dir>
set -euo pipefail
W=$1 OUTM=$2 OUTX=$3
OLD=~/orangepi5/patches/linux.bak-20261029
mkdir -p "$OUTM" "$OUTX"
mapfile -t C < <(git -C "$W" rev-list --reverse v7.3..opi5/integration-7.3)
# 0262 (drm/bridge: Keep oob_notify at the end of drm_bridge_funcs) is dropped
mapfile -t OLDN < <(cd "$OLD" && ls *.patch | grep -v '^0262-')
[ ${#C[@]} -eq 291 ] || { echo "expected 291 commits, got ${#C[@]}"; exit 1; }
[ ${#OLDN[@]} -eq 229 ] || { echo "expected 229 old patches"; exit 1; }
# numbers for the new commits (index 230..290)
NEW=(0601 0602 0603 0604 0605 0606 0607 0608 0609
     0701 0702 0703 0704 0705 0706 0707 0708 0709 0710 0711 0712 0713 0714
     0801 0802 0803 0804 0805 0806 0807 0808 0809
     0811 0812 0813 0814 0815 0816 0817
     0821 0822 0823 0824 0825 0826
     0831 0832 0833 0834 0835
     0901 0902 0903
     0911 0912 0913 0914
     1001 1002 1003 1004)
[ ${#NEW[@]} -eq 61 ] || { echo "NEW has ${#NEW[@]}"; exit 1; }
emit() { # commit filename outdir
  git -C "$W" format-patch -1 --stdout --no-numbered --no-signature "$1" > "$3/$2"
}
slug() { # commit -> format-patch's file name without the number
  local t; t=$(mktemp -d); git -C "$W" format-patch -q -1 -o "$t" "$1"
  basename "$t"/*.patch | cut -d- -f2-; rm -rf "$t"
}
for i in "${!C[@]}"; do
  c=${C[$i]}
  if [ "$i" -lt 92 ]; then name=${OLDN[$i]}
  elif [ "$i" -eq 92 ]; then name=0266-$(slug "$c")
  elif [ "$i" -le 229 ]; then name=${OLDN[$((i-1))]}
  else name=${NEW[$((i-230))]}-$(slug "$c"); fi
  emit "$c" "$name" "$OUTM"
done
mapfile -t X < <(git -C "$W" rev-list --reverse opi5/integration-7.3..opi5/integration-extra-7.3)
XN=(0001 0101 0102 0103 0104 0201 0202 0203 0204 0205 0206 0207 0208 0209)
[ ${#X[@]} -eq ${#XN[@]} ] || { echo "extra count ${#X[@]}"; exit 1; }
for i in "${!X[@]}"; do emit "${X[$i]}" "${XN[$i]}-$(slug "${X[$i]}")" "$OUTX"; done
ls "$OUTM" | wc -l; ls "$OUTX" | wc -l
