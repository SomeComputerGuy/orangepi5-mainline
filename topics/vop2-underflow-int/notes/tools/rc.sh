#!/bin/bash
# rc.sh <label> <planetest args>: runs planetest, prints POST_BUF_EMPTY frames (printed+suppressed) and AXI ports used
label=$1; shift
s=$(awk "{print \$1}" /proc/uptime)
sudo ./planetest "$@" > /tmp/rt.log 2>&1 &
sleep 2; ax=""; for w in 0 1 2 3; do ax="$ax C$w:$(( ($(sudo ./devmem $((0xfdd91100+w*0x200)) | cut -d" " -f2 | sed s/^/0x/) >> 13) & 1 ))"; done
for w in 0 1 2 3; do ax="$ax E$w:$(( ($(sudo ./devmem $((0xfdd91808+w*0x200)) | cut -d" " -f2 | sed s/^/0x/) >> 1) & 1 ))"; done
wait; sleep 0.3; e=$(awk "{print \$1}" /proc/uptime)
n=$(sudo dmesg | awk -v s=$s -v e=$e "{t=substr(\$0,2,index(\$0,\"]\")-2)+0} t>=s && t<=e" | awk "/POST_BUF_EMPTY/{n++} /callbacks suppressed/{for(i=1;i<=NF;i++) if(\$i==\"callbacks\") m+=\$(i-1)} END{print n+m}")
echo "[$label] underflow frames: $n  axi(at 2s):$ax :: $(grep fps /tmp/rt.log)"
