#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Where does a steady rkvdec context lose time while a second context cycles on rkvdec?
#   trace-sameblock.sh A B SECS      (block names from matrix.sh; run from ~/reopen on the board)
# Traces, for every rkvdec job: the OUTPUT buffer handed to the driver (vb2_buf_queue, i.e. the
# request was queued), device_run() (job start: kprobe, ctx pointer), the core's interrupt
# (irq_handler_entry), vb2_buf_done of OUTPUT and CAPTURE, and the userspace DQBUF (v4l2_dqbuf),
# plus B's open/release/STREAMON/STREAMOFF/CREATE_BUFS and the rk_iommu map/unmap work. Raw
# trace -> results/trace-<time>/trace.txt; analyze-trace.py prints the per-context breakdown.
set -u
D=$(cd "$(dirname "$0")" && pwd); A=${1:-rkvdec-h264}; B=${2:-rkvdec-h264}; SECS=${3:-20}
O=$D/results/trace-$(date +%H%M%S); mkdir -p $O
T=/sys/kernel/tracing
t() { echo "$2" | sudo tee "$T/$1" > /dev/null; }
t tracing_on 0; t trace ""; t kprobe_events ""; t buffer_size_kb 65536
# Offsets from pahole on this build: v4l2_fh.m2m_ctx = 128 (rkvdec_ctx starts with its fh),
# vb2_buffer.index = 8, .type = 12.
for k in "p:mx/run rockchip_vdec:rkvdec_device_run m2m=+128(%x0):x64" \
         "p:mx/hwstart rockchip_vdec:rkvdec_schedule_watchdog core=%x0:x64" \
         "p:mx/bufq v4l2_m2m_buf_queue m2m=%x0:x64 idx=+8(%x1):u32 type=+12(%x1):u32" \
         "p:mx/done v4l2_m2m_buf_done_and_job_finish m2m=%x1:x64 state=%x2:u32" \
         "p:mx/dqbuf v4l2_m2m_dqbuf m2m=%x1:x64" \
         "p:mx/streamon v4l2_m2m_streamon m2m=%x1:x64 type=%x2:u32" \
         "p:mx/streamoff v4l2_m2m_streamoff m2m=%x1:x64 type=%x2:u32" \
         "p:mx/open rockchip_vdec:rkvdec_open" "p:mx/release rockchip_vdec:rkvdec_release" \
         "p:mx/createbufs vb2_create_bufs q=%x0:x64" "r:mx/createbufs_ret vb2_create_bufs ret=\$retval" \
         "p:mx/map rk_iommu_map" "r:mx/map_ret rk_iommu_map" \
         "p:mx/unmap rk_iommu_unmap" "r:mx/unmap_ret rk_iommu_unmap"; do
  echo "$k" | sudo tee -a $T/kprobe_events > /dev/null || echo "kprobe failed: $k"
done
t events/mx/enable 1
for e in irq/irq_handler_entry; do t events/$e/enable 1; done
grep -E 'fdc38000|fdc40000' /proc/interrupts | awk '{print $1, $NF}' > $O/irqs.txt
DA=$(bash $D/matrix.sh desc $A); DB=$(bash $D/matrix.sh desc $B); KB=$(bash $D/matrix.sh kf $B)
# PACED=1: A plays at its own frame rate (sink sync), as a player does; default: as fast as it can.
[ "${PACED:-0}" = 1 ] && DA=${DA/fakesink name=chk sync=false/fakesink name=chk sync=true}
echo "A=$A paced=${PACED:-0} B=$B secs=$SECS" > $O/info.txt
rm -f /tmp/tr.stop
t tracing_on 1
python3 $D/mx.py steady "$DA" --period 10 --stop /tmp/tr.stop --ka -1 > $O/A.json 2>$O/A.log &
SP=$!; sleep 2
python3 $D/mx.py cycle "$DB" --frames $KB --cycles 1000 --variant normal --stop /tmp/tr.stop > $O/B.json 2>$O/B.log &
CP=$!; sleep $SECS; touch /tmp/tr.stop; wait $SP $CP
t tracing_on 0
sudo cat $T/trace > $O/trace.txt
t events/enable 0; t kprobe_events ""
python3 $D/analyze-trace.py $O | tee $O/summary.txt
