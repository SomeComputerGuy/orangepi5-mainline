#!/bin/sh
# usage: sudo trace-dec.sh clip out [nstreams] [sink] [parser] [decoder]  (from vp9-perf trace.sh)
T=/sys/kernel/tracing
f=$1; out=$2; n=${3:-1}; sink=${4:-fakevideosink}; parse=${5:-h264parse}; dec=${6:-v4l2slh264dec}
echo 0 > $T/tracing_on
echo nop > $T/current_tracer
echo > $T/trace
echo 30000 > $T/buffer_size_kb
: > $T/set_ftrace_filter
for fn in rkvdec_device_run rkvdec_h264_run rkvdec_hevc_run rkvdec_irq_handler \
	v4l2_h264_init_reflist_builder v4l2_h264_build_b_ref_lists rkvdec_h264_run_preamble \
	rkvdec_memcpy_toio v4l2_m2m_try_run v4l2_ctrl_request_setup v4l2_ctrl_request_complete \
	v4l2_m2m_buf_done_and_job_finish v4l2_m2m_ioctl_qbuf v4l2_m2m_ioctl_dqbuf \
	media_request_ioctl v4l2_m2m_request_queue v4l2_s_ext_ctrls; do
	echo $fn >> $T/set_ftrace_filter 2>/dev/null || echo "no $fn" >&2
done
echo function_graph > $T/current_tracer
echo 1 > $T/options/funcgraph-abstime
echo 1 > $T/options/funcgraph-proc
echo 0 > $T/options/funcgraph-irqs
echo 'name ~ "fdc[34]*"' > $T/events/irq/irq_handler_entry/filter
echo 'p:rkvwd rkvdec_schedule_watchdog core=%x0:x64' > $T/kprobe_events
echo 'p:rkvirq rkvdec_irq_handler core=%x1:x64' >> $T/kprobe_events
echo 1 > $T/events/kprobes/rkvwd/enable
echo 1 > $T/events/kprobes/rkvirq/enable
echo 1 > $T/events/irq/irq_handler_entry/enable
echo 1 > $T/tracing_on
for i in $(seq 1 $n); do
  timeout 120 gst-launch-1.0 -q filesrc location=$f ! matroskademux ! $parse ! $dec ! $sink sync=false &
done
wait
echo 0 > $T/tracing_on
cat $T/trace > $out
echo 0 > $T/events/irq/irq_handler_entry/enable
echo 0 > $T/events/kprobes/rkvwd/enable
echo 0 > $T/events/kprobes/rkvirq/enable
echo > $T/kprobe_events
echo nop > $T/current_tracer
: > $T/set_ftrace_filter
wc -l $out
