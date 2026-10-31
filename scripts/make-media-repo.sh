#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
# Turn out/debs-media/*.deb into a signed apt repository (the same layout and
# signing a PPA has), so the image's copy of it gives apt a Release file and an
# OpenPGP signature like any other source:
#   out/media-repo/pool/main/*.deb
#   out/media-repo/dists/$SUITE/main/binary-arm64/Packages{,.xz}
#   out/media-repo/dists/$SUITE/{Release,Release.gpg,InRelease}
#   out/media-repo/opi5-media-archive-keyring.gpg   (public key, for Signed-By)
# The signing key lives outside the source tree ($OPI5_REPO_GNUPGHOME, default
# ~/.local/share/opi5-repo-gnupg) and is created on first use.
set -euo pipefail
TOP=$(cd "$(dirname "$0")/.." && pwd)
IN=$TOP/out/debs-media OUT=$TOP/out/media-repo
SUITE=${SUITE:-stonking}
export GNUPGHOME=${OPI5_REPO_GNUPGHOME:-$HOME/.local/share/opi5-repo-gnupg}
UID_STR="Orange Pi 5 mainline media rebuilds <aiyengar1990@gmail.com>"

ls "$IN"/*.deb >/dev/null 2>&1 || { echo "no debs in $IN (run scripts/build-media-debs.sh)"; exit 1; }
install -d -m700 "$GNUPGHOME"
if ! gpg --batch --list-secret-keys "$UID_STR" >/dev/null 2>&1; then
  gpg --batch --passphrase '' --quick-generate-key "$UID_STR" ed25519 sign never
fi
FPR=$(gpg --batch --with-colons --list-secret-keys "$UID_STR" | awk -F: '/^fpr:/{print $10; exit}')

rm -rf "$OUT"
B=dists/$SUITE/main/binary-arm64
install -d "$OUT/pool/main" "$OUT/$B"
cp "$IN"/*.deb "$OUT/pool/main/"
(cd "$OUT" && dpkg-scanpackages --multiversion pool/main /dev/null > "$B/Packages" 2>/dev/null)
xz -k -9 "$OUT/$B/Packages"

R=$OUT/dists/$SUITE/Release
{
  echo "Origin: orangepi5-mainline"
  echo "Label: Orange Pi 5 media rebuilds"
  echo "Suite: $SUITE"
  echo "Codename: $SUITE"
  echo "Date: $(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S UTC')"
  echo "Architectures: arm64"
  echo "Components: main"
  echo "Description: Ubuntu packages rebuilt with V4L2 stateless decoding and Orange Pi 5 audio profiles"
  echo "SHA256:"
  for f in main/binary-arm64/Packages main/binary-arm64/Packages.xz; do
    p=$OUT/dists/$SUITE/$f
    printf ' %s %16d %s\n' "$(sha256sum "$p" | cut -d' ' -f1)" "$(stat -c%s "$p")" "$f"
  done
} > "$R"
gpg --batch --yes -u "$FPR" --clearsign -o "$OUT/dists/$SUITE/InRelease" "$R"
gpg --batch --yes -u "$FPR" -abs -o "$OUT/dists/$SUITE/Release.gpg" "$R"
gpg --batch --export "$FPR" > "$OUT/opi5-media-archive-keyring.gpg"
chmod -R a+rX "$OUT"
echo "signed repository in $OUT ($(ls "$OUT/pool/main" | wc -l) packages, key $FPR)"
