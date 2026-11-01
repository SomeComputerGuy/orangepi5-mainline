#!/bin/sh
# SPDX-License-Identifier: GPL-2.0
# DCLK / FRL / polarity matrix on HDMI-A-1, one DRM master (gdm stopped). Usage: matrix.sh <outdir> [steps...]
# Default: the full clock matrix. Each step: name:kmsctl-spec (see /var/tmp/wedge/seq.sh).
. /var/tmp/wedge/seq.sh
T3840_60="timing=594000/3840:4016:4104:4400/2160:2168:2178:2250/1048581"
T3840_5994="timing=593407/3840:4016:4104:4400/2160:2168:2178:2250/1048581"
T4096_60="timing=594000/4096:4184:4272:4400/2160:2168:2178:2250/2097157"
T4096_5994="timing=593407/4096:4184:4272:4400/2160:2168:2178:2250/2097157"
T120="timing=1188000/3840:4016:4104:4400/2160:2168:2178:2250/1048581"
T11988="timing=1186813/3840:4016:4104:4400/2160:2168:2178:2250/1048581"
T480="timing=27000/720:736:798:858/480:489:495:525/1048586"
T1440_120="timing=497750/2560:2608:2640:2720/1440:1443:1448:1525/5"
out=$1; shift
if [ $# -eq 0 ]; then
	set -- \
	"p1080:$T1080,$B8,$RGB,$LIN" \
	"t60_8:$T3840_60,$B8,$RGB,$LIN" "t5994_8:$T3840_5994,$B8,$RGB,$LIN" \
	"f60_10:$T3840_60,$B10,$RGB,$AFBC30" "f5994_10:$T3840_5994,$B10,$RGB,$AFBC30" \
	"g60_10:$T4096_60,$B10,$RGB,$AFBC30" "g5994_10:$T4096_5994,$B10,$RGB,$AFBC30" \
	"f120_8:$T120,$B8,$RGB,$LIN" "f11988_8:$T11988,$B8,$RGB,$LIN" \
	"f120_10:$T120,$B10,$RGB,$AFBC30" "f11988_10:$T11988,$B10,$RGB,$AFBC30" \
	"y420:$T4096_5994,$B8,$Y420,$LIN" "p480:$T480,$B8,$RGB,$LIN" "q1440:$T1440_120,$B8,$RGB,$LIN" \
	"p1080b:$T1080,$B8,$RGB,$LIN"
fi
python3 -I /var/tmp/wedge/clkrun.py "$out" "$@" | grep -v '^{' | tee -a "$out.summary"
