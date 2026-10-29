#!/bin/bash
# Recreate the kernel branches from the patch files in this repository, in a
# scratch kernel repository, ready to push to a GitHub fork of torvalds/linux.
#
#   tools/recreate-kernel-branches.sh [--linux DIR] [--work DIR] [--no-verify] [topic...]
#
#   --linux DIR  an existing kernel clone to borrow objects from (it is only
#                read; its objects are used through git "alternates"). It must
#                contain v7.3 (c03c1a14) and, for the v7.4-* topics, c339f4010.
#                Default: ~/orangepi5/src/linux if it exists. Without one, the
#                two base commits are fetched with --depth 1 (~300 MB each).
#   --work DIR   scratch repository (default: .work/linux in this repo)
#   --no-verify  don't compare each recreated branch tip's tree with the tree
#                recorded at export time (topics/<topic>/topic.env TIP_TREE)
#   topic...     only these topics (their parents must exist already)
#
# Result: branches opi5/<topic> for every topic in tools/export/topics.conf
# that has commits, plus opi5/image-7.3 (v7.3 + patches/linux, i.e. the image
# kernel). Commits keep their authors and author dates; the committer is
# $COMMITTER_NAME <$COMMITTER_EMAIL> (default: the repository owner) with the
# author date, so unchanged patches always give the same commit IDs.
#
# Why recreate rather than push the workspace branches: the workspace commits
# have a build-host committer address, and the workspace clone is shallow. A
# shallow repository can push to GitHub as long as the remote already has the
# shallow boundary commits (v7.3 and c339f4010 are both in torvalds/linux, so a
# fork has them); see PUBLISH.md.
set -euo pipefail
REPO=$(cd "$(dirname "$0")/.." && pwd)
LINUX=
[ -d "$HOME/orangepi5/src/linux/.git" ] && LINUX=$HOME/orangepi5/src/linux
WORK=$REPO/.work/linux
VERIFY=1
ONLY=()
while [ $# -gt 0 ]; do
  case "$1" in
    --linux) LINUX=$2; shift 2 ;;
    --work) WORK=$2; shift 2 ;;
    --no-verify) VERIFY=0; shift ;;
    -h|--help) sed -n '2,25p' "$0"; exit 0 ;;
    *) ONLY+=("$1"); shift ;;
  esac
done
COMMITTER_NAME=${COMMITTER_NAME:-Arun Iyengar}
COMMITTER_EMAIL=${COMMITTER_EMAIL:-aiyengar1990@gmail.com}
export GIT_COMMITTER_NAME=$COMMITTER_NAME GIT_COMMITTER_EMAIL=$COMMITTER_EMAIL

V73=c03c1a14507dfaf8b856c2608f9ac216021fc222
C339=c339f4010dea8b0d754f84ace70cd1b089878ef8
g() { git -C "$WORK" "$@"; }

# --- scratch repository ------------------------------------------------------
if [ ! -d "$WORK/.git" ]; then
  git init -q "$WORK"
  if [ -n "$LINUX" ]; then
    objs=$(git -C "$LINUX" rev-parse --path-format=absolute --git-common-dir)/objects
    echo "$objs" > "$WORK/.git/objects/info/alternates"
    sh=$(git -C "$LINUX" rev-parse --path-format=absolute --git-common-dir)/shallow
    [ -f "$sh" ] && cp "$sh" "$WORK/.git/shallow"
  fi
fi
g config core.abbrev 12
g config am.threeWay false
g config gc.auto 0     # never prune: objects may live in the alternate
have() { g cat-file -e "$1^{commit}" 2>/dev/null; }
if ! have $V73; then
  echo "==> fetching v7.3 (depth 1)"
  g fetch -q --depth 1 https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git tag v7.3
fi
need_c339=0
grep -q '^UPSTREAM_BASE=c339f4010' "$REPO"/topics/*/topic.env 2>/dev/null && need_c339=1
if [ $need_c339 = 1 ] && ! have $C339; then
  echo "==> fetching c339f4010 (depth 1)"
  g fetch -q --depth 1 https://github.com/torvalds/linux.git $C339
fi
g update-ref refs/base/v7.3 $V73
have $C339 && g update-ref refs/base/c339f4010 $C339

# orig workspace commit -> recreated commit
MAP=$WORK/.git/opi5-commit-map
: > "$MAP"
echo "$V73 $V73" >> "$MAP"; echo "$C339 $C339" >> "$MAP"
lookup() { awk -v k="$1" '$1 == k {print $2}' "$MAP" | tail -1; }

checkout() { g checkout -q -f --detach "$1"; g clean -q -fdx; }

# --- topics ------------------------------------------------------------------
mapfile -t TOPICS < <(grep -vE '^\s*(#|$|BOARDBASE=)' "$REPO/tools/export/topics.conf" | awk -F' [|] ' '{print $1}')
made=()
for t in "${TOPICS[@]}"; do
  if [ ${#ONLY[@]} -gt 0 ] && [[ ! " ${ONLY[*]} " == *" $t "* ]]; then continue; fi
  env=$REPO/topics/$t/topic.env
  [ -f "$env" ] || { echo "skip $t (not exported)"; continue; }
  # shellcheck disable=SC1090
  (. "$env"; [ "$COMMITS" -gt 0 ]) || { echo "skip $t (no commits)"; continue; }
  BASE_ORIG=$(sed -n 's/^BASE_ORIG=//p' "$env")
  TIP_TREE=$(sed -n 's/^TIP_TREE=//p' "$env")
  start=$(lookup "$BASE_ORIG")
  if [ -z "$start" ]; then
    # Parent created in an earlier run: use the existing branch
    parent=$(sed -n 's/^PARENT=//p' "$env")
    if g rev-parse -q --verify "refs/heads/opi5/$parent" >/dev/null &&
       [ "$(sed -n 's/^TIP_ORIG=//p' "$REPO/topics/$parent/topic.env")" = "$BASE_ORIG" ]; then
      start=$(g rev-parse "refs/heads/opi5/$parent")
    else
      echo "$t: base $BASE_ORIG is not a recreated commit (recreate its parent '$parent' in the same run)"; exit 1
    fi
  fi
  printf '==> %-20s on %s ... ' "$t" "${start:0:12}"
  checkout "$start"
  n=0
  while read -r p orig; do
    [ -n "$p" ] && [[ $p != \#* ]] || continue
    if ! g am -q --committer-date-is-author-date --keep-non-patch "$REPO/topics/$t/$p" >/dev/null 2>"$WORK/.git/am.err"; then
      echo; echo "$t: git am failed on $p:"; cat "$WORK/.git/am.err"; g am --abort || true; exit 1
    fi
    echo "$orig $(g rev-parse HEAD)" >> "$MAP"
    n=$((n + 1))
  done < "$REPO/topics/$t/series"
  if [ $VERIFY = 1 ] && [ "$(g rev-parse 'HEAD^{tree}')" != "$TIP_TREE" ]; then
    echo; echo "$t: recreated tree $(g rev-parse 'HEAD^{tree}') != exported $TIP_TREE"; exit 1
  fi
  g branch -q -f "opi5/$t" HEAD
  made+=("opi5/$t")
  echo "$n commits, $([ $VERIFY = 1 ] && echo 'tree verified' || echo 'not verified')"
done

# --- image kernel: v7.3 + patches/linux (what scripts/build-kernel.sh builds) --
# plus opi5/image-7.3-extra = that + patches/linux-extra (OPI5_EXTRA=1 builds)
apply_dir() { # dir
  local p d n=0
  for p in "$1"/*.patch; do
    [ -e "$p" ] || continue
    if head -1 "$p" | grep -qE '^From [0-9a-f]{40} '; then
      g am -q --committer-date-is-author-date --keep-non-patch "$p" >/dev/null 2>"$WORK/.git/am.err" ||
        { echo; echo "git am failed on $p:"; cat "$WORK/.git/am.err"; g am --abort || true; exit 1; }
    else
      # Plain diff (no mail header): commit it as the owner, named after the file
      g apply --index "$p"
      d=$(g log -1 --format=%aI HEAD)   # deterministic: the date of the commit below
      GIT_AUTHOR_DATE=$d GIT_COMMITTER_DATE=$d g -c user.name="$COMMITTER_NAME" -c user.email="$COMMITTER_EMAIL" \
        commit -q -m "patches/${1##*/}: $(basename "$p" .patch)" -m "Applied from a plain diff in patches/${1##*/}/."
    fi
    n=$((n + 1))
  done
  echo "$n patches"
}
if [ ${#ONLY[@]} -eq 0 ] || [[ " ${ONLY[*]} " == *" image-7.3 "* ]]; then
  printf '==> %-20s on v7.3 ... ' image-7.3
  checkout $V73
  apply_dir "$REPO/patches/linux"
  g branch -q -f opi5/image-7.3 HEAD
  made+=(opi5/image-7.3)
  if compgen -G "$REPO/patches/linux-extra/*.patch" >/dev/null; then
    printf '==> %-20s on image-7.3 ... ' image-7.3-extra
    apply_dir "$REPO/patches/linux-extra"
    g branch -q -f opi5/image-7.3-extra HEAD
    made+=(opi5/image-7.3-extra)
  else
    g branch -q -D opi5/image-7.3-extra 2>/dev/null || true
  fi
fi

echo
echo "Branches in $WORK:"
g for-each-ref --format='  %(refname:short) %(objectname:short) %(subject)' refs/heads/opi5/
# Private-data check on what would be pushed: commit identities and messages
leak=$(g log --format='%an <%ae>%n%cn <%ce>%n%B' "${made[@]}" --not refs/base/v7.3 $(have $C339 && echo refs/base/c339f4010) |
       grep -nE "$(sed -n 's/^scan\t//p' "$REPO/.work/private/private.conf" 2>/dev/null | paste -sd'|' | sed 's/^$/^$NONE/')" || true)
if [ -n "$leak" ]; then
  echo "PRIVATE DATA in the recreated commits:"; echo "$leak" | head; exit 1
fi
echo "Commit identities/messages checked for private data: clean"
