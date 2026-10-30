#!/bin/bash
# runtest.sh <label> <planetest args...>  -- runs one test, counts POST_BUF_EMPTY
label=$1; shift
vp2=$(modetest -M rockchip -p 2>/dev/null | awk '/^[0-9]+\t/ && $2!=0 && $2!=83 {printf "p%s@crtc%s ", $1, $2}')
sudo pkill -INT -x gst-launch-1.0 2>/dev/null; sleep 0.5
start=$(awk '{print $1}' /proc/uptime)
out=$(sudo ~/vop2uf/planetest "$@" 2>&1)
sleep 0.3
end=$(awk '{print $1}' /proc/uptime)
cnt=$(sudo dmesg | awk -v s=$start -v e=$end '{t=substr($0,2,index($0,"]")-2)+0} t>=s && t<=e' | \
  awk '/POST_BUF_EMPTY/{n++} /callbacks suppressed/{for(i=1;i<=NF;i++) if($i=="callbacks") m+=$(i-1)} END{print n+0, m+0}')
other=$(sudo dmesg | awk -v s=$start -v e=$end '{t=substr($0,2,index($0,"]")-2)+0} t>=s && t<=e' | grep -v -E "POST_BUF|callbacks suppressed" | tail -3)
echo "[$label] (other-crtc planes: ${vp2:-none}) $* :: $(echo "$out" | tr '\n' ' ') :: POST_BUF_EMPTY printed/suppressed: $cnt"
[ -n "$other" ] && echo "   other dmesg: $other"
true
