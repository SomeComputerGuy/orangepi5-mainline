#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
# Orange Pi 5 board test for the rkvdec HEVC RPS fixes (opi5/rkvdec-hevc-rps-7.3).
# Swaps in the before/after rockchip-vdec.ko drop-ins, runs the tests of TESTING.md
# with each, and restores the board's own module at the end.
#
# usage: board-hevc-rps.sh VECTOR_DIR OUT_DIR [--variants "before after"] [--ffmpeg BIN]
#                          [--fluster] [--move-others]
#   VECTOR_DIR  JCT-VC-HEVC_V1 vectors, one subdirectory per vector (fluster or
#               hevc-conf/x layout)
#   --ffmpeg    also run ffmpeg-hevc-extsps/board-hevc-extsps.sh with BIN (an FFmpeg
#               with patches/ffmpeg 0012, e.g. /var/tmp/extsps/bin/ffmpeg-after)
#   --fluster   also run fluster GStreamer-H.265-V4L2SL-RKVDEC JCT-VC-HEVC_V1 (~30-60 min
#               per variant; needs the private fluster in ~/cq/flpkg)
#   --move-others  move other updates/*/rockchip-vdec.ko drop-ins aside for the run
set -u -o pipefail
HERE=$(cd "$(dirname "$0")/.." && pwd)
VEC=$(readlink -f "$1") OUT=$(mkdir -p "$2" && readlink -f "$2"); shift 2
VARIANTS="before after" FF="" FLUSTER=0 MOVE=0
while [ $# -gt 0 ]; do
	case $1 in
	--variants) VARIANTS=$2; shift ;;
	--ffmpeg) FF=$(readlink -f "$2"); shift ;;
	--fluster) FLUSTER=1 ;;
	--move-others) MOVE=1 ;;
	*) echo "unknown option $1" >&2; exit 2 ;;
	esac
	shift
done
KR=$(uname -r) UPD=/lib/modules/$(uname -r)/updates/opi5-hevc-rps MOVED=$OUT/moved-modules
SUM=$OUT/summary.txt
log() { echo "$*" | tee -a "$SUM"; }
die() { echo "FATAL: $*" | tee -a "$SUM" >&2; exit 1; }
: > "$SUM"

# --- the vectors ---------------------------------------------------------------
# Same resolution, same first SPS short-term set, different later sets (picked with
# tools/spsdump-all-JCT-VC-HEVC_V1.txt); SPSCHG_CTRL has identical sets in both halves.
SYNTH=("SPSCHG_A MVCLIP_A_qualcomm_3 TSCL_B_VIDYO_4" "SPSCHG_B TSCL_B_VIDYO_4 MVCLIP_A_qualcomm_3"
       "SPSCHG_C WP_A_Toshiba_3 VPSID_A_VIDYO_2" "SPSCHG_CTRL MVCLIP_A_qualcomm_3 MVEDGE_A_qualcomm_3")
# First SPS set empty (all-zero control element), more sets after it
EMPTY0="DELTAQP_A_BRCM_4 ENTP_A_Qualcomm_1 OPFLAG_B_Qualcomm_1"
# One empty SPS set, i.e. the control's default value; intra only
DEFAULT1="IPRED_A_docomo_2 ipcm_A_NEC_3 MAXBINS_A_TI_5"
COMPONENTS="MVCLIP_A_qualcomm_3 TSCL_B_VIDYO_4 WP_A_Toshiba_3 VPSID_A_VIDYO_2 MVEDGE_A_qualcomm_3"
CONTROLS="RPS_A_docomo_5 POC_A_Bossen_3"

bitstream() {	# bitstream NAME: path of the vector's bitstream
	local d
	d=$(find "$VEC" -mindepth 1 -maxdepth 1 -type d -iname "$1" | head -1)
	[ -n "$d" ] && find "$d" -path '*__MACOSX*' -prune -o \( -name '*.bit' -o -name '*.bin' \) -print | head -1
}
V2=$OUT/vec; mkdir -p "$V2"
for n in $EMPTY0 $DEFAULT1 $COMPONENTS $CONTROLS; do
	f=$(bitstream $n); [ -n "$f" ] || die "vector $n not found in $VEC"
	mkdir -p "$V2/$n"; ln -sf "$f" "$V2/$n/$n.bit"
done
for s in "${SYNTH[@]}"; do
	set -- $s; mkdir -p "$V2/$1"
	cat "$V2/$2/$2.bit" "$V2/$3/$3.bit" > "$V2/$1/$1.bit"
	echo "$1 = $2 + $3" >> "$V2/README"
done

# --- module handling -----------------------------------------------------------
sudo -n true || die "needs passwordless sudo"
for v in $VARIANTS; do
	[ -f "$HERE/modules/$v/rockchip-vdec.ko" ] || die "no modules/$v/rockchip-vdec.ko"
done
others=$(find /lib/modules/$KR/updates -name 'rockchip-vdec.ko*' ! -path "$UPD/*" 2>/dev/null)
if [ -n "$others" ]; then
	[ $MOVE = 1 ] || die "other rockchip-vdec drop-ins present (use --move-others): $others"
	mkdir -p "$MOVED"
	for m in $others; do
		echo "$m" >> "$MOVED/list"; sudo -n mv "$m" "$MOVED/$(echo "$m" | tr / _)"
	done
fi
restore() {
	sudo -n rm -rf "$UPD"
	if [ -f "$MOVED/list" ]; then
		while read -r m; do sudo -n mv "$MOVED/$(echo "$m" | tr / _)" "$m"; done < "$MOVED/list"
		rm -f "$MOVED/list"
	fi
	sudo -n depmod -a
	sudo -n modprobe -r rockchip_vdec && sudo -n modprobe rockchip_vdec
	log "restored: $(modinfo -n rockchip_vdec)"
}
trap restore EXIT
elem() {	# the v4l2codecs element of codec $1 on the rkvdec device
	local e dev
	for e in $(gst-inspect-1.0 v4l2codecs 2>/dev/null | grep -oE "v4l2sl[a-z0-9]*${1}dec" | sort -u); do
		dev=$(gst-inspect-1.0 $e 2>/dev/null | grep -oE '/dev/video[0-9]+' | head -1)
		[ -n "$dev" ] && grep -q rkvdec /sys/class/video4linux/$(basename $dev)/name && { echo $e; return 0; }
	done
	return 1
}
use_variant() {
	sudo -n mkdir -p "$UPD"
	sudo -n install -m644 "$HERE/modules/$1/rockchip-vdec.ko" "$UPD/rockchip-vdec.ko"
	sudo -n depmod -a
	sudo -n modprobe -r rockchip_vdec || die "rockchip_vdec is in use"
	sudo -n modprobe rockchip_vdec || die "loading the $1 module failed (see dmesg)"
	sleep 2
	[ "$(cat /sys/module/rockchip_vdec/srcversion)" = "$(modinfo -F srcversion "$HERE/modules/$1/rockchip-vdec.ko")" ] ||
		die "loaded rockchip_vdec is not the $1 module"
	ELEM=$(elem h265) || die "no v4l2codecs H.265 element on rkvdec"
	GST=(gst-launch-1.0 -q)
	GST_TAIL=(h265parse ! $ELEM ! videoconvert dither=none ! video/x-raw,format=I420 ! filesink)
	DEV=$(gst-inspect-1.0 $ELEM | grep -oE '/dev/video[0-9]+' | head -1)
}
kmsg_mark() { sudo -n dmesg | wc -l; }
kmsg_since() { sudo -n dmesg | tail -n +$(($1 + 1)); }
WARN='Long and short term RPS not set'

# --- one variant -----------------------------------------------------------------
cmp_frames() {	# cmp_frames SW HW FRAMESIZE -> "frames bad first_bad"
	python3 -I - "$@" <<'PY'
import sys
fs = int(sys.argv[3]); n = bad = 0; first = -1
with open(sys.argv[1], 'rb') as a, open(sys.argv[2], 'rb') as b:
    while True:
        x, y = a.read(fs), b.read(fs)
        if not x and not y:
            break
        if x != y:
            bad += 1
            first = n if first < 0 else first
        n += 1
print(n, bad, first)
PY
}
run_variant() {
	local v=$1 O=$OUT/$1 m n f wh fs r frames bad first nA so
	mkdir -p "$O"; : > "$O/results.txt"
	use_variant $v
	log "== $v: $(modinfo -n rockchip_vdec) srcversion $(cat /sys/module/rockchip_vdec/srcversion), $ELEM on $DEV"
	v4l2-ctl -d $DEV -l > "$O/ctrls.txt" 2>&1
	grep -iE 'short.term|long.term' "$O/ctrls.txt" | tee -a "$SUM"
	if command -v v4l2-compliance > /dev/null; then
		v4l2-compliance -d $DEV > "$O/v4l2-compliance.txt" 2>&1
		log "$v v4l2-compliance: $(grep -m1 '^Total' "$O/v4l2-compliance.txt")"
	fi

	# A: the default value counts as set (commit 2)
	m=$(kmsg_mark)
	for n in $DEFAULT1; do timeout 120 gst-launch-1.0 -q filesrc location=$V2/$n/$n.bit ! h265parse ! \
		$ELEM ! fakesink > /dev/null 2>&1; done
	log "A $v: '$WARN' warnings while decoding $DEFAULT1: $(kmsg_since $m | grep -c "$WARN")"

	# B: frame-exact decode of the SPS-change streams and the empty-set-0 vectors (commits 1, 5)
	m=$(kmsg_mark)
	for n in $COMPONENTS $CONTROLS "${SYNTH[@]%% *}" $EMPTY0; do
		f=$V2/$n/$n.bit
		wh=$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=p=0 "$f")
		fs=$(( ${wh%,*} * ${wh#*,} * 3 / 2 ))
		[ -s "$OUT/sw-$n.yuv" ] || ffmpeg -nostdin -v error -threads 1 -i "$f" -fps_mode passthrough \
			-pix_fmt yuv420p -f rawvideo "$OUT/sw-$n.yuv"
		so=""
		if command -v strace > /dev/null; then
			timeout 300 strace -f -qq -e trace=ioctl -o "$O/$n.strace" \
				"${GST[@]}" filesrc location="$f" ! "${GST_TAIL[@]}" location="$O/$n.yuv" > "$O/$n.log" 2>&1
			so=" STREAMON=$(grep -c 'VIDIOC_STREAMON' "$O/$n.strace")"
		else
			timeout 300 "${GST[@]}" filesrc location="$f" ! "${GST_TAIL[@]}" location="$O/$n.yuv" > "$O/$n.log" 2>&1
		fi
		read -r frames bad first < <(cmp_frames "$OUT/sw-$n.yuv" "$O/$n.yuv" $fs)
		[ "$bad" = 0 ] && [ "$(stat -c %s "$OUT/sw-$n.yuv")" = "$(stat -c %s "$O/$n.yuv")" ] && r=PASS || r=FAIL
		nA=""
		case $n in SPSCHG_*) set -- $(grep "^$n " "$V2/README")
			nA=" (first half: $(( $(stat -c %s "$OUT/sw-$3.yuv" 2>/dev/null || echo 0) / fs )) frames)" ;;
		esac
		echo "$r $n frames=$frames bad=$bad first_bad=$first$nA$so" | tee -a "$O/results.txt"
		rm -f "$O/$n.yuv"
	done
	log "B $v: $(grep -c ^PASS "$O/results.txt") pass, $(grep -c ^FAIL "$O/results.txt") fail"
	grep ^FAIL "$O/results.txt" >> "$SUM"

	# C: FFmpeg v4l2request with the RPS controls (patches/ffmpeg 0012)
	if [ -n "$FF" ]; then
		"$HERE/scripts/board-hevc-extsps.sh" "$FF" "$V2" "$O/ffmpeg" \
			"${SYNTH[@]%% *}" $EMPTY0 $DEFAULT1 $COMPONENTS $CONTROLS > /dev/null
		log "C $v: $(tail -2 "$O/ffmpeg/results.txt" | tr '\n' ' ')"
	fi

	# D: fluster, GStreamer, the whole suite
	if [ $FLUSTER = 1 ]; then
		(cd "$O" && OPI5_H265_RKVDEC=$ELEM PYTHONPATH=$HOME/cq/flpkg timeout 7200 python3 -c \
			'import sys; from fluster.main import fluster_main; sys.argv[0]="fluster"; sys.exit(fluster_main())' \
			run -d GStreamer-H.265-V4L2SL-RKVDEC -ts JCT-VC-HEVC_V1 -j 1 -t 90 -s -so fluster.md \
			> fluster.log 2>&1 < /dev/null)
		log "D $v: $(grep -m1 'Ran ' "$O/fluster.log")"
	fi

	kmsg_since $m > "$O/dmesg.txt"
	log "$v kernel log: $(grep -c "$WARN" "$O/dmesg.txt") RPS warnings," \
	    "$(grep -ciE 'WARNING:|BUG:|Oops|KASAN|Unable to handle|iommu.*fault' "$O/dmesg.txt") warnings/oopses/faults"
}

for v in $VARIANTS; do run_variant $v; done
if [ -f "$OUT/before/results.txt" ] && [ -f "$OUT/after/results.txt" ]; then
	log "== B before -> after"
	join <(awk '{print $2, $1}' "$OUT/before/results.txt" | sort) \
	     <(awk '{print $2, $1}' "$OUT/after/results.txt" | sort) | awk '{print $2 " -> " $3 "  " $1}' | tee -a "$SUM"
fi
