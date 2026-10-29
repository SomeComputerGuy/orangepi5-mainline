#!/bin/bash
# Review, sign off and email the two upstream U-Boot patches.
#  1. installs git send-email if missing (asks for sudo)
#  2. shows each patch for review
#  3. regenerates them with your Signed-off-by (DCO) once you confirm
#  4. configures Gmail SMTP for git send-email if not already set (Gmail
#     addresses only; configure sendemail.* yourself otherwise)
#  5. sends them; git send-email asks before each mail and prompts for your
#     SMTP password (for Gmail an app password: https://myaccount.google.com/apppasswords)
set -euo pipefail
. "$(dirname "$0")/env.sh"
P=$TOP/patches/upstream/u-boot
NAME=$OPI5_NAME EMAIL=$OPI5_EMAIL
[ -n "$NAME" ] && [ -n "$EMAIL" ] || { echo "set OPI5_NAME/OPI5_EMAIL (local.env) or git user.name/user.email"; exit 1; }

if ! git send-email --help >/dev/null 2>&1; then
  echo "==> Installing git-email"
  sudo apt-get install -y git-email
fi

echo "==> Generating patches for review"
"$TOP/scripts/make-uboot-patches.sh" >/dev/null
for f in "$P"/*.patch; do
  ${PAGER:-less} "$f"
done

cat <<'EOF'

Signing off certifies the Developer Certificate of Origin for these
patches under your name: https://developercertificate.org
EOF
read -rp "Add your Signed-off-by and continue? [y/N] " ok
[ "$ok" = y ] || [ "$ok" = Y ] || { echo "Stopped; nothing sent."; exit 1; }
"$TOP/scripts/make-uboot-patches.sh" -s >/dev/null
grep -L "^Signed-off-by: $NAME" "$P"/*.patch | grep . && { echo "sign-off missing"; exit 1; }

if [ -z "$(git config --global --get sendemail.smtpserver || true)" ] && [[ $EMAIL == *@gmail.com ]]; then
  echo "==> Configuring git send-email for Gmail ($EMAIL)"
  git config --global sendemail.smtpserver smtp.gmail.com
  git config --global sendemail.smtpserverport 587
  git config --global sendemail.smtpencryption tls
  git config --global sendemail.smtpuser "$EMAIL"
fi

echo "==> Sending (you'll be asked to confirm each mail)"
git send-email --confirm=always --suppress-cc=self --from="$NAME <$EMAIL>" "$P"/*.patch
