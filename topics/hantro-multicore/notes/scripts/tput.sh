#!/bin/sh
# Run N parallel 1080p NV12 encodes of /dev/shm/hmc/raw.nv12 (100 frames each, looped L times) and report aggregate fps
N=$1; L=${2:-3}
F=/dev/shm/hmc/raw.nv12
irqs() { grep -E 'fdba[0-9a-f]+\.video-codec' /proc/interrupts | awk '{s=0; for(i=2;i<=9;i++) s+=$i; print $NF":"s}' | tr '\n' ' '; }
before=$(irqs)
start=$(date +%s.%N)
for i in $(seq $N); do
  ( for l in $(seq $L); do timeout 120 gst-launch-1.0 -q filesrc location=$F blocksize=3110400 ! rawvideoparse format=nv12 width=1920 height=1080 framerate=30/1 ! v4l2jpegenc ! fakesink sync=false || echo FAIL; done ) &
done
wait
end=$(date +%s.%N)
after=$(irqs)
awk -v n=$N -v l=$L -v s=$start -v e=$end 'BEGIN{t=e-s; printf "N=%d frames=%d time=%.2f fps=%.1f\n", n, n*l*100, t, n*l*100/t}' 
echo "irq before: $before"
echo "irq after:  $after"
