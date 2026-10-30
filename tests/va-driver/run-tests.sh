#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
# Board test for the V4L2 stateless VA-API driver. Runs from the unpacked bundle directory
# (e.g. ~/browser-hwdec) and installs nothing: the driver is loaded from ./dri through
# LIBVA_DRIVERS_PATH. Results go to ./results/<timestamp>/.
#
#   ./run-tests.sh [probe] [correct] [fluster] [perf] [gst] [av1]     (default: all but av1)
#
# Environment: CLIPS (default ~/vp9perf: 4k8.h264.mkv 4k8.hevc.mkv 4k8.webm 4k10.webm 1080p.webm),
# JOBS for fluster (default 2), RENDER (default /dev/dri/renderD128).
set -u
D=$(cd "$(dirname "$0")" && pwd)
export LIBVA_DRIVERS_PATH="$D/dri" LIBVA_DRIVER_NAME=v4l2_request
RENDER=${RENDER:-/dev/dri/renderD128}
CLIPS=${CLIPS:-$HOME/vp9perf}
JOBS=${JOBS:-2}
R="$D/results/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$R" "$D/clips"
STEPS=${*:-probe correct fluster perf gst}
SUMMARY="$R/SUMMARY.txt"
say() { echo "$*" | tee -a "$SUMMARY"; }
HW="-hwaccel vaapi -hwaccel_device $RENDER -hwaccel_output_format vaapi"

say "== $(date -Is) $(uname -rv)"
say "driver $(md5sum "$D/dri/v4l2_request_drv_video.so" | cut -c1-12) $(cat "$D/VERSION" 2>/dev/null)"
say "rkvdec module: $(modinfo -n rockchip_vdec 2>/dev/null)"
dmesg | tail -n 1 > "$R/dmesg.before" 2>/dev/null

# tmo SECS CMD...: run CMD with a deadline. On expiry, dump where every thread of the process
# tree sits (gdb backtraces when gdb exists, else /proc wchan/syscall/stack and open fds) into
# $R/hang-*.txt and SUMMARY, then kill it, so a hang reports itself instead of blocking the run.
tmo() {
	secs=$1; shift
	"$@" &
	pid=$!
	t=0
	while kill -0 $pid 2>/dev/null; do
		if [ $t -ge "$secs" ]; then
			h="$R/hang-$(basename "$1")-$pid.txt"
			say "HANG: '$*' still running after ${secs}s, state in $(basename "$h")"
			for p in $pid $(pgrep -P $pid 2>/dev/null); do
				{
					echo "=== pid $p: $(tr '\0' ' ' < /proc/$p/cmdline 2>/dev/null)"
					if command -v gdb >/dev/null 2>&1; then
						timeout 60 gdb -q -batch -ex 'thread apply all bt' -p $p 2>&1
					fi
					for t in /proc/$p/task/*; do
						echo "--- tid $(basename $t) wchan=$(cat $t/wchan 2>/dev/null) syscall=$(cat $t/syscall 2>/dev/null)"
						sudo -n cat $t/stack 2>/dev/null
					done
					echo "--- fds"; ls -l /proc/$p/fd 2>/dev/null | awk '{print $9, $10, $11}'
				} >> "$h" 2>&1
			done
			kill -TERM $pid 2>/dev/null; sleep 2; kill -KILL $pid 2>/dev/null
			wait $pid 2>/dev/null
			return 124
		fi
		sleep 1; t=$((t + 1))
	done
	wait $pid
}

clip() { # name -> path (generated clips in ./clips, the vp9perf clips in $CLIPS)
	for p in "$D/clips/$1" "$CLIPS/$1"; do [ -f "$p" ] && { echo "$p"; return 0; }; done
	return 1
}

gen_clips() {
	# 1080p B-frame clips (what most players/web content look like); ~1 min of CPU on the A76s
	[ -f "$D/clips/1080p.h264.mkv" ] || tmo 600 ffmpeg -v error -f lavfi -i testsrc2=size=1920x1080:rate=30 -t 10 \
		-c:v libx264 -preset fast -profile:v high -bf 3 -g 60 "$D/clips/1080p.h264.mkv"
	[ -f "$D/clips/1080p.hevc.mkv" ] || tmo 900 ffmpeg -v error -f lavfi -i testsrc2=size=1920x1080:rate=30 -t 10 \
		-c:v libx265 -preset fast -x265-params bframes=4:keyint=60:log-level=error "$D/clips/1080p.hevc.mkv"
	[ -f "$D/clips/1080p.vp9.webm" ] || tmo 900 ffmpeg -v error -f lavfi -i testsrc2=size=1920x1080:rate=30 -t 10 \
		-c:v libvpx-vp9 -deadline realtime -cpu-used 8 -b:v 4M "$D/clips/1080p.vp9.webm"
	[ -f "$D/clips/720p.vp8.webm" ] || tmo 600 ffmpeg -v error -f lavfi -i testsrc2=size=1280x720:rate=30 -t 10 \
		-c:v libvpx -deadline realtime -cpu-used 8 -b:v 2M "$D/clips/720p.vp8.webm"
}

step_probe() {
	say "== probe"
	tmo 60 "$D/bin/vaprobe" "$RENDER" > "$R/vaprobe.txt" 2>&1; rc=$?
	cat "$R/vaprobe.txt" | tee -a "$SUMMARY"
	[ $rc = 0 ] && say "PROBE PASS" || say "PROBE FAIL"
}

# Bit-exactness: hardware decode (frames downloaded from the VA surfaces) vs FFmpeg software.
# The hwdownload filter makes a silent software fallback fail instead of passing.
step_correct() {
	say "== correctness (framemd5 vs software)"
	gen_clips
	for c in 1080p.h264.mkv 1080p.hevc.mkv 1080p.vp9.webm 720p.vp8.webm 4k8.h264.mkv 4k8.hevc.mkv 4k8.webm 1080p.webm; do
		f=$(clip $c) || { say "SKIP $c (missing)"; continue; }
		tmo 300 ffmpeg -v error $HW -i "$f" -map 0:v -vf hwdownload,format=nv12 -f framemd5 "$R/$c.hw.md5" 2> "$R/$c.hw.log"
		hrc=$?
		tmo 600 ffmpeg -v error -i "$f" -map 0:v -pix_fmt nv12 -f framemd5 "$R/$c.sw.md5" 2> "$R/$c.sw.log"
		hw=$(grep -v '^#' "$R/$c.hw.md5" | awk -F, '{print $6}' | tr -d ' ' | md5sum | cut -c1-12)
		sw=$(grep -v '^#' "$R/$c.sw.md5" | awk -F, '{print $6}' | tr -d ' ' | md5sum | cut -c1-12)
		n=$(grep -vc '^#' "$R/$c.hw.md5")
		if [ $hrc = 0 ] && [ "$hw" = "$sw" ] && [ "$n" -gt 0 ]; then say "PASS $c ($n frames)"
		else say "FAIL $c (rc $hrc, $n frames, hw $hw sw $sw; see $c.hw.log)"; fi
	done
}

step_fluster() {
	say "== fluster (FFmpeg VAAPI decoders)"
	if [ -d "$D/fluster-resources/JCT-VC-HEVC_V1" ]; then
		mkdir -p "$HOME/.local/share/fluster/resources"
		[ -e "$HOME/.local/share/fluster/resources/JCT-VC-HEVC_V1" ] || \
			ln -s "$D/fluster-resources/JCT-VC-HEVC_V1" "$HOME/.local/share/fluster/resources/JCT-VC-HEVC_V1"
	fi
	for t in "FFmpeg-H.265-VAAPI JCT-VC-HEVC_V1" "FFmpeg-H.264-VAAPI JVT-AVC_V1" "FFmpeg-VP9-VAAPI VP9-TEST-VECTORS"; do
		set -- $t
		tmo 3600 fluster run -d "$1" -ts "$2" -j "$JOBS" -t 60 -s > "$R/fluster-$2.txt" 2>&1
		say "$1 $2: $(grep -E 'Ran [0-9]+/[0-9]+' -o "$R/fluster-$2.txt" | tail -1) $(grep -o '|[^|]*|$' "$R/fluster-$2.txt" | tail -1)"
	done
}

fps() { # frames and wall seconds from ffmpeg -benchmark output; flags a software fallback
	if grep -qE 'Failed setup for format vaapi|hwaccel initialisation returned error|No VA display' "$1"; then
		printf 'SOFTWARE FALLBACK '; fi
	awk '/frame=/{for(i=1;i<=NF;i++) if($i ~ /^frame=/){f=$i; sub("frame=","",f); if(f=="") f=$(i+1)}} /bench: utime/{u=$2;s=$3;r=$4} END {sub("utime=","",u);sub("stime=","",s);sub("rtime=","",r);sub("s","",u);sub("s","",s);sub("s","",r); if(r>0) printf "%d frames %.1f fps cpu %.0f%%", f, f/r, 100*(u+s)/r}' "$1"
}

# Throughput: decode only, frames stay in VA surfaces (no download, no display), like the
# GStreamer fakevideosink numbers. Pass bar: >= 90% of GStreamer v4l2codecs on the same clip.
step_perf() {
	say "== perf (ffmpeg -hwaccel vaapi -f null, 1 and 2 streams)"
	for c in 4k8.h264.mkv 4k8.hevc.mkv 4k8.webm 4k10.webm 1080p.h264.mkv 1080p.hevc.mkv 1080p.webm; do
		f=$(clip $c) || continue
		tmo 300 ffmpeg -hide_banner -nostats -benchmark $HW -i "$f" -map 0:v -f null - > "$R/perf-$c.1.log" 2>&1
		say "$c x1: $(fps "$R/perf-$c.1.log")"
		( tmo 300 ffmpeg -hide_banner -nostats -benchmark $HW -i "$f" -map 0:v -f null - > "$R/perf-$c.2a.log" 2>&1 & 
		  tmo 300 ffmpeg -hide_banner -nostats -benchmark $HW -i "$f" -map 0:v -f null - > "$R/perf-$c.2b.log" 2>&1 & wait )
		say "$c x2: $(fps "$R/perf-$c.2a.log") | $(fps "$R/perf-$c.2b.log")"
	done
}

step_gst() {
	say "== GStreamer va plugin"
	export GST_REGISTRY="$R/gst-registry.bin"
	gst-inspect-1.0 va > "$R/gst-va.txt" 2>&1
	say "va elements: $(grep -oE 'va[a-z0-9]+(dec|postproc)' "$R/gst-va.txt" | sort -u | tr '\n' ' ')"
	for t in "1080p.h264.mkv h264parse vah264dec" "4k8.hevc.mkv h265parse vah265dec" "4k8.webm vp9parse vavp9dec"; do
		set -- $t
		f=$(clip $1) || continue
		tmo 120 /usr/bin/time -f '%e s %P cpu' gst-launch-1.0 -q filesrc location="$f" ! parsebin ! $2 ! $3 ! fakevideosink sync=false > "$R/gst-$3.log" 2>&1
		say "$3 $1: rc $? $(tail -1 "$R/gst-$3.log")"
	done
	unset GST_REGISTRY
}

# AV1 on the RK3588 AV1 VPU: opt-in (another VA bridge saw a board reset on a 4K 8-tile-column
# stream; run attended). Uses AV1 clips that GStreamer v4l2slav1dec already decodes bit-exactly.
step_av1() {
	say "== AV1 (opt-in)"
	for f in $AV1_CLIPS; do
		c=$(basename "$f")
		tmo 300 ffmpeg -v error $HW -i "$f" -map 0:v -vf hwdownload,format=nv12 -f framemd5 "$R/$c.hw.md5" 2> "$R/$c.hw.log"
		tmo 600 ffmpeg -v error -i "$f" -map 0:v -pix_fmt nv12 -f framemd5 "$R/$c.sw.md5" 2>/dev/null
		cmp -s "$R/$c.hw.md5" "$R/$c.sw.md5" && say "PASS $c" || say "CHECK $c (diff framemd5)"
	done
}

for s in $STEPS; do "step_$s"; done
dmesg | awk -v l="$(cat "$R/dmesg.before")" 'f{print} $0==l{f=1}' > "$R/dmesg.new" 2>/dev/null
say "== kernel messages during the run: $(wc -l < "$R/dmesg.new") lines ($(grep -ciE 'timeout|fault|error' "$R/dmesg.new") timeout/fault/error)"
say "results: $R"
