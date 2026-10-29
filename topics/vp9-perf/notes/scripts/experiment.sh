#!/bin/sh
# Run in ~/vp9perf with the debug module loaded. $1 = tag
P=/sys/module/rockchip_vdec/parameters
I=$(grep -E "fdc38000|fdc40000" /proc/interrupts | cut -d: -f1 | tr -d " ")
i=0; while pgrep -f "fluster|slenc|gst-launch" >/dev/null && [ $i -lt 60 ]; do sleep 5; i=$((i+1)); done
run() { # name cache cnt aff
	echo $2 | sudo -n tee $P/dbg_cache >/dev/null; echo $3 | sudo -n tee $P/dbg_cnt_nc >/dev/null
	for q in $I; do echo $4 | sudo -n tee /proc/irq/$q/smp_affinity_list >/dev/null; done
	echo "== $1: dbg_cache=$(cat $P/dbg_cache) dbg_cnt_nc=$(cat $P/dbg_cnt_nc) irq_aff=$4 load=$(cut -d' ' -f1 /proc/loadavg)"
	pgrep -af "fluster|slenc|gst-launch" | grep -v pgrep
	for c in 4k8.webm 4k10.webm 4k10hb.webm; do ./bench.sh $c 1; ./bench.sh $c 2; done
	./bench.sh 1080p.webm 1; ./bench.sh 4k8.hevc.mkv 1; ./bench.sh 4k8.h264.mkv 1
	sudo -n ./trace.sh 4k8.webm $HOME/vp9perf/t3_$1_4k8_x1.txt 1 >/dev/null
	sudo -n ./trace.sh 4k10.webm $HOME/vp9perf/t3_$1_4k10_x2.txt 2 >/dev/null
	for c in 4k10hb.webm 1080p.webm; do ./md5.sh $c; done
}
run E0 -2 0 0-7
run E1 -2 1 0-7
run E2 -1 1 0-7
run E3 -1 1 4-7
run E4 -1 0 0-7
for q in $I; do echo 0-7 | sudo -n tee /proc/irq/$q/smp_affinity_list >/dev/null; done
echo -1 | sudo -n tee $P/dbg_cache >/dev/null
sudo chown aruni t3_*
sudo -n dmesg | grep DBG
