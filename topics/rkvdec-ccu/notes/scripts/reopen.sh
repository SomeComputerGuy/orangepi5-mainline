#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# reopen.sh [cycles]: close and reopen one rkvdec context while another one streams (the "decoder reopen hang").
# Stream B: the 4K HEVC clip in a loop. Stream A: an H.264 conformance vector, CYCLES times per variant:
# normal close (EOS), SIGKILL mid-stream, and SIGKILL right after start (buffers queued).
# Pass: every A run ends (no 15 s timeout), B keeps advancing, no rkvdec "timed out", no hung task. -> ~/ccu/reopen/
N=${1:-200}; O=~/ccu/reopen; mkdir -p $O; cd $O
R=~/.local/share/fluster/resources; E4=$(~/cq/elem.sh h264 rkvdec); E5=$(~/cq/elem.sh h265 rkvdec)
A=$(ls $R/JVT-AVC_V1/CABA3_TOSHIBA_E/* | head -1)
n0=$(sudo -n dmesg | wc -l)
( while [ ! -f stop ]; do gst-launch-1.0 -q filesrc location=$HOME/demo/yacht_hevc_2160p120.mp4 ! qtdemux ! h265parse ! $E5 ! \
	identity silent=false ! fakevideosink sync=false 2>/dev/null | grep -c chain >> b-frames; done ) & BP=$!
rm -f stop; a() { gst-launch-1.0 -q filesrc location=$A ! h264parse ! $E4 ! fakevideosink sync=false >/dev/null 2>&1; }
for v in normal kill-mid kill-start; do
	hang=0; t0=$(date +%s)
	for i in $(seq 1 $N); do
		case $v in
		normal) timeout -s KILL 15 bash -c "$(declare -f a); A=$A E4=$E4 a" || hang=$((hang+1));;
		kill-mid) timeout -s KILL 0.3 bash -c "$(declare -f a); A=$A E4=$E4 a"; true;;
		kill-start) timeout -s KILL 0.05 bash -c "$(declare -f a); A=$A E4=$E4 a"; true;;
		esac
	done
	echo "$v: $N cycles in $(( $(date +%s) - t0 )) s, normal-run hangs: $hang, B decoder IRQs $(grep -E 'fdc38000|fdc40000' /proc/interrupts | awk '{s=0; for(i=2;i<=9;i++) s+=$i; printf "%s ", s}')" | tee -a summary.txt
done
touch stop; sleep 2; kill $BP 2>/dev/null; pkill -f yacht_hevc 2>/dev/null
echo "dmesg: $(sudo -n dmesg | tail -n +$n0 | grep -c 'timed out') timeouts, $(sudo -n dmesg | tail -n +$n0 | grep -cE 'hung_task|blocked for more') hung tasks, $(sudo -n dmesg | tail -n +$n0 | grep -cE 'KASAN|BUG:|Oops') bugs" | tee -a summary.txt
ps -eo stat,comm | grep -c "^D" | sed 's/^/D-state tasks: /' | tee -a summary.txt
