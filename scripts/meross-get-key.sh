#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# One-time setup for scripts/board-power.py: log in to the Meross cloud once, fetch the account key
# the plugs sign local commands with, look up the board's plug by its name in the Meross app, and
# store MEROSS_DEVICE, MEROSS_UUID, MEROSS_IP and MEROSS_KEY in local.env (never published).
# Every plug on the account shares the key, so board-power.py checks the UUID behind MEROSS_IP
# before each command and refuses any other plug: each project names its own plug here.
# Run it yourself in a terminal; it asks for the Meross email and password.
#
#   scripts/meross-get-key.sh "<plug name in the Meross app>" <plug LAN IP>
#   MEROSS_API=https://iotx-eu.meross.com scripts/meross-get-key.sh ...   # non-US accounts
set -euo pipefail
TOP=$(cd "$(dirname "$0")/.." && pwd)
USAGE='usage: meross-get-key.sh "<plug name in the Meross app>" <plug LAN IP>'
NAME=${1:?$USAGE}
IP=${2:?$USAGE}
API=${MEROSS_API:-https://iotx-us.meross.com}
VENV=$HOME/.cache/opi5-meross-venv

if [ ! -x "$VENV/bin/python" ]; then
  echo "setting up $VENV (meross-iot)..."
  python3 -m venv "$VENV"
  "$VENV/bin/pip" -q install meross-iot
fi

PY=$(mktemp --suffix=.py); trap 'rm -f "$PY"' EXIT
cat > "$PY" <<'EOF'
import asyncio, getpass, sys
from meross_iot.http_api import MerossHttpClient

async def main():
    api, name = sys.argv[1], sys.argv[2]
    # prompts on stderr and answers from the terminal: stdout carries only "key uuid"
    with open("/dev/tty") as tty:
        sys.stderr.write("Meross email: "); sys.stderr.flush()
        email = tty.readline().strip()
    password = getpass.getpass("Meross password: ")
    c = await MerossHttpClient.async_from_user_password(api_base_url=api, email=email,
                                                        password=password)
    try:
        devs = await c.async_list_devices()
        hit = [d for d in devs if d.dev_name == name]
        if len(hit) != 1:
            sys.exit(f"{len(hit)} plugs named {name!r}; on the account: "
                     + ", ".join(repr(d.dev_name) for d in devs))
        print(c.cloud_credentials.key, hit[0].uuid)
    finally:
        await c.async_logout()

asyncio.run(main())
EOF
read -r KEY UUID < <("$VENV/bin/python" -I "$PY" "$API" "$NAME")
[ -n "${KEY:-}" ] && [ -n "${UUID:-}" ] || { echo "no key/uuid returned"; exit 1; }

ENVF=$TOP/local.env
touch "$ENVF"; chmod 600 "$ENVF"
sed -i '/^MEROSS_\(IP\|KEY\|MAC\|UUID\|DEVICE\)=/d' "$ENVF"
printf 'MEROSS_DEVICE=%s\nMEROSS_UUID=%s\nMEROSS_IP=%s\nMEROSS_KEY=%s\n' \
  "$NAME" "$UUID" "$IP" "$KEY" >> "$ENVF"
echo "wrote MEROSS_DEVICE, MEROSS_UUID, MEROSS_IP and MEROSS_KEY to $ENVF"
"$TOP/scripts/board-power.py" status && echo "plug '$NAME' answers at $IP: OK"
