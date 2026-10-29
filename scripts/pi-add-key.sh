#!/bin/bash
# Install the build PC's project SSH key on the Orange Pi (prompts for the Pi's password).
# Usage: pi-add-key.sh [user@host]   (default $OPI5_PI from scripts/env.sh / local.env)
# Creates the project key ($OPI5_SSH_KEY, default .ssh/opi5_ed25519) if missing.
set -euo pipefail
. "$(dirname "$0")/env.sh"
PI=${1:-$OPI5_PI}
KEY=$OPI5_SSH_KEY
OPTS=(-o StrictHostKeyChecking=accept-new -o UserKnownHostsFile="$OPI5_KNOWN_HOSTS")
if [ ! -f "$KEY" ]; then
  mkdir -p "$(dirname "$KEY")"; chmod 700 "$(dirname "$KEY")"
  ssh-keygen -q -t ed25519 -N "" -C "opi5-project" -f "$KEY"
fi

if ! ssh "${OPTS[@]}" -o BatchMode=yes -i "$KEY" "$PI" true 2>/dev/null; then
  echo "Logging in once with your password (change it if prompted, then you'll be logged out)..."
  ssh "${OPTS[@]}" -o PubkeyAuthentication=no "$PI" true || true
  echo "Installing key..."
  ssh-copy-id "${OPTS[@]}" -i "$KEY.pub" "$PI"
fi
ssh "${OPTS[@]}" -o BatchMode=yes -i "$KEY" "$PI" 'echo "Key login OK: $(hostname) $(uname -r)"'
