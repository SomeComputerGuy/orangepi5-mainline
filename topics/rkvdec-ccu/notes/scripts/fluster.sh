#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# fluster.sh <tag> [suite...]: fluster on rkvdec only (GStreamer v4l2codecs elements of the rkvdec
# device, looked up per boot), -j2. Uses a private fluster copy ~/ccu/flpkg (codec-quality's ~/cq/flpkg with its decoder classes made picklable; adds
# GStreamer-<codec>-V4L2SL-RKVDEC decoders) and the vectors in ~/.local/share/fluster.
# Results: ~/ccu/fluster-<tag>/<decoder>-<suite>.{log,md}, summary in ~/ccu/fluster-<tag>/summary.txt
set -u
E=~/cq/elem.sh; T=$1; shift
SUITES=${*:-JCT-VC-HEVC_V1 JVT-AVC_V1 JVT-FR-EXT VP9-TEST-VECTORS}
export OPI5_H264_RKVDEC=$($E h264 rkvdec) OPI5_VP9_RKVDEC=$($E vp9 rkvdec) OPI5_H265_RKVDEC=$($E h265 rkvdec)
echo "elements: h264=$OPI5_H264_RKVDEC h265=$OPI5_H265_RKVDEC vp9=$OPI5_VP9_RKVDEC"
D=~/ccu/fluster-$T; rm -rf $D; mkdir -p $D; cd $D
FL=$D/fluster-opi5; cat > $FL <<'EOS'
#!/bin/sh
PYTHONPATH=$HOME/ccu/flpkg exec python3 -c 'import sys; from fluster.main import fluster_main; sys.argv[0]="fluster"; sys.exit(fluster_main())' "$@"
EOS
chmod +x $FL
for s in $SUITES; do
	case $s in JCT-VC*) d=GStreamer-H.265-V4L2SL-RKVDEC;; JVT*) d=GStreamer-H.264-V4L2SL-RKVDEC;; VP9*) d=GStreamer-VP9-V4L2SL-RKVDEC;; esac
	timeout 3600 nice $FL -r ~/.local/share/fluster/resources run -d $d -ts $s -j 2 -t 60 -s -so $d-$s.md > $d-$s.log 2>&1 </dev/null
	echo "$d / $s: $(grep -m1 -E 'Ran [0-9]+/' $d-$s.log)" | tee -a summary.txt
done
echo "DONE $(date)" >> summary.txt
