#!/bin/bash
# Scan the repository for secrets and private data before publishing.
#
# Usage: tools/secret-scan.sh [dir]     (default: this repository)
# Scans every file that git would publish: tracked files plus untracked files
# that aren't ignored. Exit status 1 if anything is found that isn't allowed by
# tools/secret-scan.allow ("path-glob<TAB>regex" lines for reviewed hits).
#
# Kernel patches carry the public e-mail addresses of their authors and
# reviewers (From:, Signed-off-by:, Cc:, Link:); those are counted but not
# flagged inside patch files. Anywhere else, any address except the
# repository owner's is flagged.
set -uo pipefail
ROOT=$(cd "${1:-$(dirname "$0")/..}" && pwd)
ALLOW=$ROOT/tools/secret-scan.allow
OWNER_EMAIL=${OWNER_EMAIL:-aiyengar1990@gmail.com}
cd "$ROOT"

mapfile -d '' FILES < <(git ls-files -z --cached --others --exclude-standard)
echo "Scanning ${#FILES[@]} files in $ROOT"

fail=0
report() { # class file line text
  local cls=$1 f=$2 ln=$3 txt=$4
  if [ -f "$ALLOW" ]; then
    while IFS=$'\t' read -r glob re; do
      [ -z "$glob" ] || [[ $glob == \#* ]] && continue
      # shellcheck disable=SC2053
      if [[ $f == $glob ]] && grep -qE -- "$re" <<<"$txt"; then return; fi
    done < "$ALLOW"
  fi
  printf '  [%s] %s:%s: %s\n' "$cls" "$f" "$ln" "${txt:0:160}"
  fail=1
}

# 1. Files that must never be published, by name
for f in "${FILES[@]}"; do
  case "$f" in
    *.pem|*.key|*.p12|*.pfx|*/x509.genkey|*signing_key*|*/id_rsa*|*/id_ed25519*|*_ed25519|*_ed25519.pub|*known_hosts*|.ssh/*|*/.ssh/*|local.env|cidata/user-data|*.ko|*.dtb|*.dtbo|*.img|*.img.xz|*.deb)
      report file "$f" 0 "file type/name must not be published" ;;
  esac
done

# 2. Content patterns (case-insensitive extended regex)
PATTERNS=(
  'secret:-----BEGIN [A-Z ]*PRIVATE KEY-----'
  'secret:-----BEGIN (OPENSSH|RSA|EC|DSA|PGP|ENCRYPTED|CERTIFICATE)'
  'secret:ssh-(ed25519|rsa|dss) AAAA|ecdsa-sha2-nistp[0-9]+ AAAA'
  'secret:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_|xox[baprs]-|AKIA[0-9A-Z]{16}|AIza[0-9A-Za-z_-]{30}'
  'secret:\b(password|passwd|secret|api[_-]?key|auth[_-]?token|access[_-]?token)\b["]?[[:space:]]*[:=][[:space:]]*[^[:space:]$<{(]'
  'ip:\b10\.55\.[0-9]+\.[0-9]+|\b192\.168\.[0-9]+\.[0-9]+|\b172\.(1[6-9]|2[0-9]|3[01])\.[0-9]+\.[0-9]+|\b10\.[0-9]+\.[0-9]+\.[0-9]+\b'
  'mac:\b([0-9a-f]{2}:){5}[0-9a-f]{2}\b'
  'path:/home/[a-z]'
)
# Site-specific patterns (private hostnames etc.) are kept out of the repository
PRIV=$ROOT/.work/private/private.conf
if [ -f "$PRIV" ]; then
  while IFS=$'\t' read -r k re _; do
    [ "$k" = scan ] && PATTERNS+=("private:$re")
  done < "$PRIV"
else
  echo "note: no $PRIV, scanning with the generic patterns only"
fi
for f in "${FILES[@]}"; do
  [ -f "$f" ] || continue
  grep -Iq . "$f" 2>/dev/null || continue   # skip binaries / empty files
  for p in "${PATTERNS[@]}"; do
    cls=${p%%:*} re=${p#*:}
    while IFS= read -r hit; do
      [ -n "$hit" ] || continue
      report "$cls" "$f" "${hit%%:*}" "${hit#*:}"
    done < <(grep -nIiE -- "$re" "$f" 2>/dev/null)
  done
done

# 3. E-mail addresses
patch_mails=0
for f in "${FILES[@]}"; do
  [ -f "$f" ] && grep -Iq . "$f" 2>/dev/null || continue
  while IFS= read -r hit; do
    [ -n "$hit" ] || continue
    ln=${hit%%:*} txt=${hit#*:}
    # Drop URLs and message-ids (local part with a long digit run or a UUID)
    txt=$(sed -E 's#[a-z]+://[^ )>`"]*##g' <<<"$txt")
    others=$(grep -oiE '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' <<<"$txt" | grep -viF "$OWNER_EMAIL" | grep -viE '^git@github\.com$|@anthropic\.com$|@(example|localhost)\b|\.(patch|json|txt|mbx|cover)$' | grep -vE '^[^@]*[0-9]{6}|^[^@]*-v[0-9]+-[0-9]+-|^[0-9a-f]{8}-[0-9a-f]{4}-' || true)
    [ -n "$others" ] || continue
    if [[ $f == *.patch || $f == */cover-letter* ]]; then
      patch_mails=$((patch_mails + 1)); continue
    fi
    report email "$f" "$ln" "$txt"
  done < <(grep -nIE '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' "$f" 2>/dev/null)
done
echo "Public addresses inside patch files/cover letters (authors, reviewers, lists): $patch_mails lines (not flagged)"

if [ "$fail" = 0 ]; then
  echo "SECRET SCAN: PASS"
else
  echo "SECRET SCAN: FAIL (fix the hits above, or allow reviewed ones in tools/secret-scan.allow)"
fi
exit "$fail"
