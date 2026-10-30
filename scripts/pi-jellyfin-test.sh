#!/bin/bash
# Run the Jellyfin hardware-decode test (opi5-jellyfin-hwtest) on the Orange Pi and
# fetch the results into out/jellyfin-hwtest/.
# Usage: pi-jellyfin-test.sh [user@board] [-- opi5-jellyfin-hwtest options]
#   e.g. pi-jellyfin-test.sh -- --list
#        pi-jellyfin-test.sh -- --backend mpv,gst,ffmpeg --duration 30
# The server and login come from $TOP/local.env (never from scripts or arguments):
#   OPI5_JELLYFIN_URL='http://jellyfin.example:8096'
#   OPI5_JELLYFIN_USER='name'
#   OPI5_JELLYFIN_PASS='secret'
# They reach the board only on the test's stdin: not on its disk, in a command
# line or in the results. Results can name your library's titles, so they go to
# out/ (not exported), not work/_out/.
set -euo pipefail
. "$(dirname "$0")/env.sh"
PI=$OPI5_PI
if [ $# -gt 0 ] && [ "$1" != -- ]; then PI=$1; shift; fi
[ "${1:-}" = -- ] && shift
SSH=(-o BatchMode=yes -o UserKnownHostsFile="$OPI5_KNOWN_HOSTS" -i "$OPI5_SSH_KEY")
ENV=$TOP/local.env
TOOL=$TOP/overlay-desktop/usr/local/bin/opi5-jellyfin-hwtest

[ -f "$ENV" ] || { echo "missing $ENV with OPI5_JELLYFIN_URL/_USER/_PASS (see the header of $0)"; exit 1; }
[ -z "$(find "$ENV" -perm /077)" ] || { echo "$ENV is readable by others; chmod 600 $ENV"; exit 1; }
creds=$(
  set +u
  # shellcheck disable=SC1090
  . "$ENV"
  [ -n "$OPI5_JELLYFIN_URL" ] && [ -n "$OPI5_JELLYFIN_USER" ] && [ -n "$OPI5_JELLYFIN_PASS" ] ||
    { echo "set OPI5_JELLYFIN_URL, OPI5_JELLYFIN_USER and OPI5_JELLYFIN_PASS in $ENV" >&2; exit 1; }
  printf 'OPI5_JELLYFIN_URL=%s\nOPI5_JELLYFIN_USER=%s\nOPI5_JELLYFIN_PASS=%s\n' \
    "$OPI5_JELLYFIN_URL" "$OPI5_JELLYFIN_USER" "$OPI5_JELLYFIN_PASS"
)

# The desktop image has the tool in /usr/local/bin; the server image gets a copy
STAGE=/tmp/opi5-jellyfin-hwtest
RES=/tmp/opi5-jellyfin-hwtest-results
ssh "${SSH[@]}" "$PI" "mkdir -p $STAGE && rm -rf $RES"
scp -q "${SSH[@]}" "$TOOL" "$PI:$STAGE/"
# Values the remote shell sees are quoted; the credentials go to stdin only
remote="python3 -I $STAGE/opi5-jellyfin-hwtest --creds-stdin --out $RES"
for a in "$@"; do remote+=" $(printf '%q' "$a")"; done
printf '%s\n' "$creds" | ssh "${SSH[@]}" "$PI" "$remote"
case " $* " in *" --list "*) exit 0 ;; esac
dest=$TOP/out/jellyfin-hwtest
mkdir -p "$dest"
scp -q -r "${SSH[@]}" "$PI:$RES/*" "$dest/"
ssh "${SSH[@]}" "$PI" "rm -rf $RES"
echo "Results copied to $dest/"
