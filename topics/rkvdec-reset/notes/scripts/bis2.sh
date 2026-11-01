#!/bin/bash
# results in ~/rrres: logind RemoveIPC wipes /dev/shm files of aruni when its last session closes
# bis.sh tag [nfluster] [nsvasp]: bisect data point: N x fluster JVT-AVC_V1 (-j2) per-vector vs reference, then svasp.sh
export RRLOG=~/rrres FLDIR=~/rrres; cd ~/rr; mkdir -p ~/rrres; o=~/rrres/bis-$1.txt
n0=$(sudo -n dmesg | wc -l)
{ for i in $(seq 1 ${2:-6}); do ./fluster.sh $1-$i JVT-AVC_V1 2>&1 | tail -1 | grep -oE "Ran [0-9/]+"
  ./flcmp.sh ~/rrres/fluster-$1-$i | sed "s/ (ref:.*//" | cut -c40-300; done
  [ "${3:-0}" -gt 0 ] && ./svasp.sh $3 2>&1 | tail -3
  echo "since start: timeouts $(sudo -n dmesg | tail -n +$n0 | grep -c 'timed out'), KASAN/Oops/canary $(sudo -n dmesg | grep -cE 'BUG: KASAN|Oops|CANARY')"; } > $o 2>&1
echo DONE >> $o
