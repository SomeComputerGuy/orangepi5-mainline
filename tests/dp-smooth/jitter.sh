#!/bin/sh
# jitter.sh <tag> <frames-on-crtc0> -- <gst-launch args...>: vblank interval stats on crtc0/1 while a pipeline runs
TAG=$1 N=$2; shift 3
cd ~/dpsmooth; mkdir -p out
sudo ./vblwait 0 $N > out/$TAG.c0 & P0=$!
sudo ./vblwait 1 $((N/2)) > out/$TAG.c1 & P1=$!
timeout -s INT $((N/60+1)) gst-launch-1.0 -q "$@" >/dev/null 2>&1
wait $P0 $P1
for c in c0 c1; do awk -v tag=$TAG.$c 'NR>1{d=($2-p)*1000; s+=d; ss+=d*d; n++; if(d>mx)mx=d; if(mn==""||d<mn)mn=d} {p=$2} END{m=s/n; printf "%s n=%d mean=%.3f sd=%.3f min=%.3f max=%.3f\n",tag,n,m,sqrt(ss/n-m*m),mn,mx}' out/$TAG.$c; done
