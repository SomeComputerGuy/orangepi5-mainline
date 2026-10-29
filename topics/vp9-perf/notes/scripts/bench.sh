#!/bin/sh
# usage: bench.sh clip [nstreams] [sink]   (decode-only wall-clock fps, incl. pipeline startup)
f=$1; n=${2:-1}; sink=${3:-fakevideosink}
case $f in
*.webm)     dec="matroskademux ! vp9parse ! v4l2slvp9dec" ;;
*.hevc.mkv) dec="matroskademux ! h265parse ! v4l2slh265dec" ;;
*.h264.mkv) dec="matroskademux ! h264parse ! v4l2slvideo11h264dec" ;;
esac
frames=$(ffprobe -v error -count_packets -select_streams v:0 -show_entries stream=nb_read_packets -of csv=p=0 $f)
start=$(date +%s.%N)
for i in $(seq 1 $n); do
  timeout 120 gst-launch-1.0 -q filesrc location=$f ! $dec ! $sink sync=false &
done
wait
end=$(date +%s.%N)
awk -v f=$frames -v n=$n -v s=$start -v e=$end -v c="$f $sink" "BEGIN{printf \"%-32s x%d: %6.1f fps total (%d frames each, %.2fs)\n\", c, n, f*n/(e-s), f, e-s}"
