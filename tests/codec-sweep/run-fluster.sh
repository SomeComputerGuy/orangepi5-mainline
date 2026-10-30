#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Fluster on every OPi5 stateless decoder, per device. Stock fluster's GStreamer-H.264-V4L2SL runs
# "v4l2slh264dec", which is whichever H.264 device registered first (the Hantro G1 on this board),
# so rkvdec's H.264 decoder was never tested. This uses a private copy of fluster (~/cq/flpkg) with
# extra GStreamer-<codec>-V4L2SL-RKVDEC/-HANTRO decoders whose element names are looked up per boot.
cd $(dirname $0); E=$(readlink -f elem.sh); O=$PWD/fluster-results.txt; : > $O
export OPI5_H264_RKVDEC=$($E h264 rkvdec) OPI5_H264_HANTRO=$($E h264 vpu121-dec) \
       OPI5_VP9_RKVDEC=$($E vp9 rkvdec) OPI5_H265_RKVDEC=$($E h265 rkvdec) OPI5_VP8_HANTRO=$($E vp8 vpu121-dec)
FL=$PWD/fluster-opi5; cat > $FL <<'EOS'
#!/bin/sh
PYTHONPATH=$HOME/cq/flpkg exec python3 -c 'import sys; from fluster.main import fluster_main; sys.argv[0]="fluster"; sys.exit(fluster_main())' "$@"
EOS
chmod +x $FL
fl() { $FL "$@"; }
mkdir -p fl; cd fl
fl download VP8-TEST-VECTORS VP9-TEST-VECTORS JVT-AVC_V1 JVT-FR-EXT JCT-VC-HEVC_V1 AV1-TEST-VECTORS >/dev/null 2>&1
for t in "GStreamer-VP8-V4L2SL-HANTRO VP8-TEST-VECTORS" "GStreamer-VP9-V4L2SL-RKVDEC VP9-TEST-VECTORS" \
         "GStreamer-H.264-V4L2SL-RKVDEC JVT-AVC_V1" "GStreamer-H.264-V4L2SL-HANTRO JVT-AVC_V1" \
         "GStreamer-H.264-V4L2SL-RKVDEC JVT-FR-EXT" "GStreamer-H.265-V4L2SL-RKVDEC JCT-VC-HEVC_V1" \
         "GStreamer-AV1-V4L2SL AV1-TEST-VECTORS"; do
	set -- $t; timeout 3600 $FL run -d $1 -ts $2 -j 2 -t 90 -s -so $1-$2.md > $1-$2.log 2>&1 </dev/null
	echo "$1 / $2: $(grep -m1 'Ran ' $1-$2.log)" | tee -a $O
done
echo DONE >> $O
