#!/bin/sh
# Decoder regression: VP8 (G1 fdb50000) and AV1 (vpu981 fdc70000). $1 = tag
D=/var/tmp/hmc; cd $D
[ -f vp8.webm ] || ffmpeg -loglevel error -f lavfi -i testsrc2=size=640x480:rate=30 -frames:v 60 -c:v libvpx -b:v 1M vp8.webm
if [ ! -f av1.ivf ]; then
  ffmpeg -loglevel error -f lavfi -i testsrc2=size=640x480:rate=30 -frames:v 30 -c:v libaom-av1 -cpu-used 8 -b:v 1M av1.ivf 2>/dev/null ||
  ffmpeg -loglevel error -f lavfi -i testsrc2=size=640x480:rate=30 -frames:v 30 -c:v libsvtav1 av1.ivf
fi
i0=$(grep -E 'fdb50000|fdc70000' /proc/interrupts | awk '{s=0; for(i=2;i<=9;i++) s+=$i; print $NF":"s}' | tr '\n' ' ')
timeout 60 gst-launch-1.0 -q filesrc location=vp8.webm ! matroskademux ! v4l2slvp8dec ! video/x-raw,format=NV12 ! filesink location=vp8-$1.nv12 || echo "FAIL vp8"
timeout 60 gst-launch-1.0 -q filesrc location=av1.ivf ! ivfparse ! av1parse ! v4l2slav1dec ! filesink location=av1-$1.raw || echo "FAIL av1"
i1=$(grep -E 'fdb50000|fdc70000' /proc/interrupts | awk '{s=0; for(i=2;i<=9;i++) s+=$i; print $NF":"s}' | tr '\n' ' ')
echo "vp8 $(md5sum < vp8-$1.nv12 | cut -c1-32) $(stat -c %s vp8-$1.nv12)"
echo "av1 $(md5sum < av1-$1.raw | cut -c1-32) $(stat -c %s av1-$1.raw)"
# software reference for vp8
[ -f vp8-sw.nv12 ] || ffmpeg -loglevel error -i vp8.webm -pix_fmt nv12 -f rawvideo vp8-sw.nv12
echo "vp8-sw $(md5sum < vp8-sw.nv12 | cut -c1-32)"
echo "irq before: $i0"; echo "irq after:  $i1"
