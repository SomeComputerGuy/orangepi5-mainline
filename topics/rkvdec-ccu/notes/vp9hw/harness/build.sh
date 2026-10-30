#!/bin/bash
# Host harness: compares the VDPU381 VP9 probability tables written by the
# rkvdec backend with the ones of Rockchip MPP (hal_vp9d_com.c), for random
# compressed headers. MPP and kernel code are extracted at build time into
# gen/ (not distributed).
set -e
H=$(cd $(dirname $0); pwd)
W=${W:-~/orangepi5/work/rkvdec-ccu-vp9hw}
M=${M:-~/orangepi5/work/_downloads/rkvdec-ccu/mpp}
G=$H/gen; rm -rf $G; mkdir -p $G
C=$M/mpp/hal/rkdec/vp9d/hal_vp9d_com.c
# MPP: types + tables (prob_context .. kf tables), prob_default, prob_flag_delta
s1=$(grep -n '^typedef struct {' $C | head -1 | cut -d: -f1)
e1=$(grep -n '^const vp9_prob vp9_kf_partition_probs' $C | cut -d: -f1)
e1=$(awk -v s=$e1 'NR>s && /^};/ {print NR; exit}' $C)
s2=$(grep -n '^MPP_RET hal_vp9d_prob_default' $C | cut -d: -f1)
e2=$(grep -n '^MPP_RET hal_vp9d_prob_kf' $C | cut -d: -f1); e2=$((e2-1))
{ echo '#include "mpp_shim.h"'; sed -n "${s1},${e1}p" $C; sed -n "${s2},${e2}p" $C; } > $G/mpp_tbl.c
echo '#include "main_mpp.c"' >> $G/mpp_tbl.c
D=$M/mpp/codec/dec/vp9/vp9d_codec.c
{ echo '#include "mpp_shim.h"'; sed -n '/^static const RK_S32 inv_map_table/,/^};/p' $D; echo 'const RK_S32 *mpp_inv_map = inv_map_table;'; } > $G/invmap.c
cp $M/mpp/base/mpp_bitput.c $G/
sed -n '/^struct v4l2_vp9_frame_mv_context {/,/^};/p;/^struct v4l2_vp9_frame_context {/,/^};/p' $W/include/media/v4l2-vp9.h > $G/v4l2_vp9_types.h
# kernel: v4l2-vp9 tables, write_coeff_plane, the backend table writers
V=$W/drivers/media/v4l2-core/v4l2-vp9.c
e3=$(grep -n '^EXPORT_SYMBOL_GPL(v4l2_vp9_default_probs)' $V | cut -d: -f1)
{ echo '#include "kern_shim.h"'; sed -n "14,${e3}p" $V | grep -v EXPORT_SYMBOL; } > $G/v4l2_tbl.c
R=$W/drivers/media/platform/rockchip/rkvdec
{ echo '#include "kern_shim.h"'; sed -n '/^void write_coeff_plane/,/^}/p' $R/rkvdec-vp9-common.c; } > $G/coef.c
B=$R/rkvdec-vdpu381-vp9.c
s4=$(grep -n '^/\* Size of a probability table' $B | cut -d: -f1)
e4=$(grep -n '^struct rkvdec_vp9_frame_info' $B | cut -d: -f1); e4=$((e4-1))
s5=$(grep -n '^struct vdpu381_vp9_flag_writer' $B | cut -d: -f1)
e5=$(grep -n '^/\* Writes the update table of the frame' $B | cut -d: -f1); e5=$((e5-1))
s6=$(grep -n '^/\* The probabilities of a frame context that was reset' $B | cut -d: -f1)
e6=$(grep -n '^static void config_ref_registers' $B | cut -d: -f1); e6=$((e6-1))
{ echo '#include "kern_shim.h"'; sed -n "${s4},${e4}p;${s5},${e5}p;${s6},${e6}p" $B; echo '#include "main_kern.c"'; } > $G/kern_tbl.c
cd $G
MI="-I$H -I$G -I$M/inc -I$M/mpp/base/inc -I$M/mpp/common -I$M/osal/inc -I$W/include/uapi"
gcc -O1 -g -Wall -Wno-unused-function $MI -c mpp_tbl.c mpp_bitput.c invmap.c
gcc -O1 -g -Wall -Wno-unused-function -I$H -I$G -I$W/include/uapi -c v4l2_tbl.c coef.c kern_tbl.c
gcc -o $H/vp9tbl *.o
echo built $H/vp9tbl
