#!/bin/bash
# Bridge this PC's second ethernet port ($OPI5_PORT) onto the main LAN port ($OPI5_UPLINK)
# so a device plugged into enp130s0 gets DHCP etc. straight from the LAN router.
# If you don't confirm within 120 s (e.g. you lost connectivity), the old
# network config is restored automatically.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || exec sudo "$0" "$@"
. "$(dirname "$0")/env.sh"
UPLINK=$OPI5_UPLINK PORT=$OPI5_PORT BR=br0
CONF=/etc/netplan/90-opi5-bridge.yaml
# Drop-in for the .network file netplan generates for the bridge (10-netplan-br0.network)
DROPIN_DIR=/etc/systemd/network/10-netplan-$BR.network.d
DROPIN=$DROPIN_DIR/50-opi5-same-dhcp-id.conf
MAC=$(cat /sys/class/net/$UPLINK/address)
# networkd's DHCP client ID is IAID(derived from interface name)+DUID(machine-id).
# Reuse the uplink's IAID so br0 presents the same MAC *and* client ID -> same lease.
IAID=$(networkctl status "$UPLINK" | sed -n 's/.*DHCPv4 Client ID: IAID:\(0x[0-9a-f]*\)\/DUID.*/\1/p')
[ -n "$IAID" ] || { echo "couldn't read the DHCP IAID of $UPLINK"; exit 1; }

# Keep running if the SSH session drops, so the automatic revert still happens
trap '' HUP

echo "Current netplan config (will stay in place; $CONF overrides it):"
for f in /etc/netplan/*.yaml; do [ "$f" = "$CONF" ] || { echo "== $f"; cat "$f"; }; done
echo

# The bridge takes the uplink's MAC so the router hands this PC the same IP as before
cat > "$CONF" <<YAML
network:
  version: 2
  ethernets:
    $UPLINK:
      dhcp4: false
      dhcp6: false
    $PORT:
      dhcp4: false
      dhcp6: false
  bridges:
    $BR:
      interfaces: [$UPLINK, $PORT]
      macaddress: $MAC
      dhcp4: true
      dhcp6: true
      parameters:
        stp: false
        forward-delay: 0
YAML
chmod 600 "$CONF"
mkdir -p "$DROPIN_DIR"
cat > "$DROPIN" <<INI
[DHCPv4]
IAID=$IAID
[DHCPv6]
IAID=$IAID
INI
echo "br0 will use MAC $MAC and DHCP IAID $IAID (same as $UPLINK)"

# From here on, a dead SSH terminal makes writes fail; don't let that abort the
# revert. Output is also kept in a log.
set +e
exec > >(tee --output-error=warn -a /var/log/opi5-bridge.log) 2>&1
echo "Applying. The network drops for a few seconds while $BR takes over $UPLINK."
netplan apply
sleep 5
ip -br addr show "$BR" || true
echo
if read -r -t 120 -p "Network OK? Press ENTER within 120 s to keep it (otherwise it is reverted): "; then
  echo "Kept. Devices on $PORT now get addresses from the LAN. Undo with scripts/bridge-off.sh"
  bridge link show
else
  echo; echo "No confirmation: reverting."
  rm -f "$CONF" "$DROPIN"; rmdir "$DROPIN_DIR" 2>/dev/null || true
  if ip link show "$BR" >/dev/null 2>&1; then ip link delete "$BR"; fi
  netplan apply
  exit 1
fi
