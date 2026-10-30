#!/bin/bash
# usage: opi5ssh.sh 'cmd'  -- waits up to 5 min for board
for i in $(seq 1 60); do
  ssh -o BatchMode=yes -o ConnectTimeout=4 -o UserKnownHostsFile=$HOME/orangepi5/.ssh/known_hosts -i $HOME/orangepi5/.ssh/opi5_ed25519 <user>@<board-ip> "$@" && exit 0
  rc=$?; [ $rc -ne 255 ] && exit $rc
  sleep 5
done
exit 255
