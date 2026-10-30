#!/bin/bash
# watch.sh <secs> <interval>: log POST_BUF_EMPTY (printed+suppressed) and per-port loads periodically
end=$(( $(date +%s) + $1 ))
while [ $(date +%s) -lt $end ]; do
  n=$(sudo dmesg | awk "/POST_BUF_EMPTY/{n++} /vop2_isr.*callbacks suppressed/{for(i=1;i<=NF;i++) if(\$i==\"callbacks\") m+=\$(i-1)} END{print n+m}")
  echo "$(date +%T) up=$(cut -d" " -f1 /proc/uptime) pbe_total=$n gst=$(pgrep -c gst-launch) :: $(sudo python3 -I ~/vop2uf/portload.py)"
  sleep $2
done
