#!/bin/bash
# Publish this repository to GitHub (and optionally the kernel branches and
# release binaries). Nothing is pushed until you confirm. See PUBLISH.md.
#
#   ./publish.sh --private|--public [--name NAME] [--owner LOGIN]
#                [--kernel-fork [--fork-name NAME] [--force-branches]]
#                [--release DIR] [--yes]
#
#   --private / --public  visibility of the main repository (required; pick one)
#   --name NAME           repository name (default orangepi5-mainline)
#   --owner LOGIN         GitHub account (default SomeComputerGuy)
#   --kernel-fork         also fork torvalds/linux and push the opi5/* branches
#                         and the image-*/archive/* tags of .work/linux (a fork
#                         of a public repository is always public). New and
#                         fast-forward branches and new tags are pushed; nothing
#                         on the fork is deleted or moved backwards
#   --force-branches      also force-push opi5/* branches that were rewritten
#                         (e.g. a topic rebase); existing tags are never moved
#   --fork-name NAME      name of the kernel fork (default linux: the existing
#                         fork github.com/SomeComputerGuy/linux)
#   --release DIR         also create a GitHub release with the binaries in DIR
#                         (e.g. ~/orangepi5/out); checked for private strings first
#   --yes                 don't ask for confirmation
set -euo pipefail
REPO=$(cd "$(dirname "$0")" && pwd)
cd "$REPO"
VIS= NAME=orangepi5-mainline OWNER=SomeComputerGuy FORK=0 FORK_NAME=linux RELDIR= YES=0 FORCE_BR=0
while [ $# -gt 0 ]; do
  case "$1" in
    --private) VIS=private; shift ;;
    --public) VIS=public; shift ;;
    --name) NAME=$2; shift 2 ;;
    --owner) OWNER=$2; shift 2 ;;
    --kernel-fork) FORK=1; shift ;;
    --fork-name) FORK_NAME=$2; shift 2 ;;
    --force-branches) FORCE_BR=1; shift ;;
    --release) RELDIR=$2; shift 2 ;;
    --yes) YES=1; shift ;;
    -h|--help) sed -n '2,25p' "$0"; exit 0 ;;
    *) echo "unknown option: $1"; exit 1 ;;
  esac
done
[ -n "$VIS" ] || { echo "choose --private or --public (see PUBLISH.md)"; exit 1; }
confirm() { [ $YES = 1 ] && return 0; read -rp "$1 [y/N] " a; [ "$a" = y ] || [ "$a" = Y ]; }

echo "==> Checks"
command -v gh >/dev/null || { echo "GitHub CLI missing: sudo apt install gh  (or follow the web-UI steps in PUBLISH.md)"; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "Log in first: gh auth login   (then re-run)"; exit 1; }
[ -n "$OWNER" ] || OWNER=$(gh api user -q .login)
[ -z "$(git status --porcelain)" ] || { echo "uncommitted changes; commit them first (git status)"; exit 1; }
tools/secret-scan.sh >/tmp/opi5-secret-scan.txt 2>&1 || { cat /tmp/opi5-secret-scan.txt; echo "secret scan failed: not publishing"; exit 1; }
tail -1 /tmp/opi5-secret-scan.txt
# The scan above covers the files; also check every commit's metadata and messages
priv=$(sed -n 's/^scan\t//p' .work/private/private.conf 2>/dev/null | paste -sd'|')
if git log --all --format='%an <%ae>%n%cn <%ce>%n%B' | grep -qiE "${priv:+$priv|}BEGIN .*PRIVATE KEY"; then
  echo "private data in commit metadata/messages: not publishing"; exit 1
fi
files=$(git ls-files | wc -l); size=$(git count-objects -vH | sed -n 's/^size-pack: //p')
echo "Main repository: $OWNER/$NAME ($VIS), branch $(git branch --show-current), $files files, pack $size"
git log --oneline | sed 's/^/  /'

if gh repo view "$OWNER/$NAME" >/dev/null 2>&1; then
  echo "==> $OWNER/$NAME exists already; will push to it"
  URL=$(gh repo view "$OWNER/$NAME" --json sshUrl -q .sshUrl)
else
  confirm "Create github.com/$OWNER/$NAME ($VIS) and push?" || { echo "stopped"; exit 1; }
  gh repo create "$OWNER/$NAME" "--$VIS" \
    --description "Orange Pi 5 (RK3588S) on mainline Linux, U-Boot and TF-A: build scripts, patches, upstream topic series" \
    --disable-wiki
  URL=$(gh repo view "$OWNER/$NAME" --json sshUrl -q .sshUrl)
fi
if git remote get-url origin >/dev/null 2>&1; then git remote set-url origin "$URL"; else git remote add origin "$URL"; fi
gh auth setup-git >/dev/null 2>&1 || true
# gh repo view gives the SSH URL; fall back to HTTPS (gh's credential helper) if SSH isn't set up
if ! git ls-remote origin >/dev/null 2>&1; then git remote set-url origin "https://github.com/$OWNER/$NAME.git"; fi
git push -u origin "$(git branch --show-current)"
echo "Pushed: https://github.com/$OWNER/$NAME"

if [ $FORK = 1 ]; then
  echo "==> Kernel branches"
  [ -d .work/linux/.git ] || tools/recreate-kernel-branches.sh
  echo "Branches and tags to push (a fork of torvalds/linux is PUBLIC):"
  git -C .work/linux for-each-ref --format='  %(refname:short)' refs/heads/opi5/ 'refs/tags/image-*' 'refs/tags/archive/*'
  confirm "Fork torvalds/linux as $OWNER/$FORK_NAME and push these?" || { echo "stopped"; exit 1; }
  if ! gh repo view "$OWNER/$FORK_NAME" >/dev/null 2>&1; then
    gh repo fork torvalds/linux --clone=false --default-branch-only --fork-name "$FORK_NAME"
    for i in $(seq 30); do gh repo view "$OWNER/$FORK_NAME" >/dev/null 2>&1 && break; sleep 5; done
  fi
  # The scratch repository is shallow at v7.3 and c339f4010. GitHub accepts the
  # push because the fork already has both commits (from torvalds/linux);
  # push.negotiate lets git find them so only the new objects (~90 MB) go up.
  FURL=git@github.com:$OWNER/$FORK_NAME.git
  git ls-remote "$FURL" >/dev/null 2>&1 || FURL=https://github.com/$OWNER/$FORK_NAME.git
  # Classify every local opi5/* branch against the fork: new, unchanged,
  # fast-forward, or rewritten (pushed only with --force-branches). Branches on
  # the fork that are no longer generated are listed, never deleted here.
  declare -A remote=()
  while read -r sha ref; do remote[$ref]=$sha; done < <(git ls-remote "$FURL" 'refs/heads/opi5/*' 'refs/tags/image-*' 'refs/tags/archive/*')
  push=() rewritten=() stale=()
  while read -r sha ref; do
    r=${remote[$ref]:-}
    if [ -z "$r" ]; then push+=("$ref:$ref")
    elif [ "$r" = "$sha" ]; then :
    elif git -C .work/linux merge-base --is-ancestor "$r" "$sha" 2>/dev/null; then push+=("$ref:$ref")
    else rewritten+=("$ref")
    fi
  done < <(git -C .work/linux for-each-ref --format='%(objectname) %(refname)' refs/heads/opi5/)
  # Tags: only new ones (an existing tag on the fork is never moved)
  while read -r sha ref; do
    r=${remote[$ref]:-}
    if [ -z "$r" ]; then push+=("$ref:$ref")
    elif [ "$r" != "$sha" ]; then
      [ "$(git -C .work/linux rev-parse -q --verify "$r^{commit}" 2>/dev/null)" = "$(git -C .work/linux rev-parse "$ref^{commit}")" ] ||
        echo "  WARNING: tag ${ref#refs/tags/} differs on the fork; left alone"
    fi
  done < <(git -C .work/linux for-each-ref --format='%(objectname) %(refname)' 'refs/tags/image-*' 'refs/tags/archive/*')
  for ref in "${!remote[@]}"; do
    [[ $ref == refs/heads/* ]] || continue
    git -C .work/linux rev-parse -q --verify "$ref" >/dev/null || stale+=("${ref#refs/heads/}")
  done
  if [ ${#rewritten[@]} -gt 0 ]; then
    printf '  rewritten (not a fast-forward): %s\n' "${rewritten[@]#refs/heads/}"
    if [ $FORCE_BR = 1 ]; then push+=("${rewritten[@]/#/+}")
    else echo "  not pushed; re-run with --force-branches to force-push them"; fi
  fi
  if [ ${#push[@]} -gt 0 ]; then
    printf '  push: %s\n' "${push[@]%%:*}"
    git -C .work/linux -c push.negotiate=true push "$FURL" "${push[@]}"
  else
    echo "  fork is up to date"
  fi
  if [ ${#stale[@]} -gt 0 ]; then
    mapfile -t stale < <(printf '%s\n' "${stale[@]}" | sort)
    echo "  On the fork but no longer generated (not deleted; check that an archive/ or image- tag keeps each tip, then):"
    echo "    git -C .work/linux push $FURL --delete ${stale[*]}"
  fi
  echo "Pushed: https://github.com/$OWNER/$FORK_NAME/branches"
fi

if [ -n "$RELDIR" ]; then
  echo "==> Release binaries from $RELDIR"
  shopt -s nullglob
  assets=("$RELDIR"/ubuntu-*-orangepi5.img.xz "$RELDIR"/ubuntu-*-orangepi5.img.xz.sha256
          "$RELDIR"/u-boot-rockchip.bin "$RELDIR"/u-boot-rockchip-spi.bin "$RELDIR"/debs/linux-*.deb)
  [ ${#assets[@]} -gt 0 ] || { echo "no assets in $RELDIR"; exit 1; }
  pat=$(sed -n 's/^scan\t//p' .work/private/private.conf 2>/dev/null | paste -sd'|')
  pat=${pat:-BEGIN .*PRIVATE KEY}
  bad=0
  for d in "$RELDIR"/debs/linux-*.deb; do
    if { dpkg-deb -f "$d"; dpkg-deb --fsys-tarfile "$d" | tar -xO --wildcards './boot/vmlinuz-*' 2>/dev/null | zcat -f | strings | grep 'Linux version'; } | grep -qiE "$pat"; then
      echo "  $d: contains the build host name (rebuild with the current scripts/build-kernel.sh)"; bad=1
    fi
    if dpkg-deb -c "$d" | grep -qiE 'signing_key\.pem|\.priv|x509\.genkey'; then echo "  $d: contains a private key"; bad=1; fi
  done
  [ $bad = 0 ] || { echo "not uploading these binaries"; exit 1; }
  echo "NOTE: the image boots with user ubuntu / password ubuntu (must be changed at first login) unless you built it with your own cidata/user-data."
  tag=image-$(date -u +%Y%m%d)
  printf '  %s\n' "${assets[@]}"
  confirm "Create release $tag on $OWNER/$NAME with these files?" || { echo "stopped"; exit 1; }
  gh release create "$tag" "${assets[@]}" --repo "$OWNER/$NAME" --title "Orange Pi 5 Ubuntu 26.10 image ($tag)" \
    --notes "Ubuntu 26.10 server image for the Orange Pi 5, built from commit $(git rev-parse --short HEAD) of this repository. Linux 7.3 + patches/linux, U-Boot v2026.10, TF-A v2.15.0. First login: ubuntu / ubuntu (a password change is forced). Kernel modules are signed with a key that is not published, so out-of-tree modules have to be built with your own kernel build (see README)."
fi
echo "Done."
