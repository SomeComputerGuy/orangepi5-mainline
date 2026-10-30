#include "kern_shim.h"
/* Size of a probability table, as the hardware reads and writes it */
#define VDPU381_VP9_PROB_TBL_SIZE	4864
/* Size of the symbol counts the hardware writes */
#define VDPU381_VP9_COUNT_TBL_SIZE	13208
/*
 * VP9 segmap size: ceil(width/64) * ceil(height/64) * 256 / 4
 * For 4K (3840x2160): 60 * 34 * 64 = 130,560 bytes
 * For 8K (7680x4320): 120 * 68 * 64 = 522,240 bytes
 * Use 8K-safe value to cover all supported resolutions.
 */
#define RKVDEC_VP9_MAX_SEGMAP_SIZE	524288

#define VDPU381_VP9_NUM_FRAME_CTXS	4

/*
 * Probability tables are made of 128-bit units. The coefficient probabilities
 * of a transform size and plane type (6 bands x 6 contexts x 3 nodes) take 27
 * bytes of every 32, in four rows: the same holds for their update flags,
 * 27 bits of every 32.
 */
#define VDPU381_VP9_COEF_ROW_LEN	27
#define VDPU381_VP9_COEF_ROW_SIZE	32
#define VDPU381_VP9_COEF_PLANE_SIZE	128

/* First 5 x 128 bits of the probability and update tables */
struct vdpu381_vp9_probs_head {
	u8 partition[16][3];
	u8 seg_pred[3];
	u8 seg_tree[7];
	u8 skip[3];
	u8 tx32[2][3];
	u8 tx16[2][2];
	u8 tx8[2][1];
	u8 is_inter[4];
	u8 reserved[3];
} __packed;

/*
 * The probabilities of a frame context, in the default table and in the
 * frame contexts the hardware saves. The update table of an inter frame
 * holds the updates in the same layout.
 */
struct vdpu381_vp9_frame_probs {
	struct vdpu381_vp9_probs_head head;
	u8 y_mode[4][9];
	u8 comp_mode[5];
	u8 comp_ref[5];
	u8 single_ref[5][2];
	u8 inter_mode[7][3];
	u8 interp_filter[4][2];
	u8 reserved0[11];
	/* [ref][tx size][plane type] */
	u8 coef[2][4][2][VDPU381_VP9_COEF_PLANE_SIZE];
	/* three modes per row, the last row holds mode 9 */
	u8 uv_mode[4][32];
	struct v4l2_vp9_frame_mv_context mv;
	u8 reserved1[27];
} __packed;

/* Bit flags telling which probabilities are updated, then the updates */
struct vdpu381_vp9_inter_updates {
	u8 flags[320];
	struct vdpu381_vp9_frame_probs delta;
} __packed;

/*
 * Intra frames code no mode probabilities: the update table holds the key
 * frame probabilities of the partition and intra modes instead.
 */
struct vdpu381_vp9_intra_updates {
	u8 flags[272];
	struct vdpu381_vp9_probs_head head;
	u8 coef_intra[4][2][VDPU381_VP9_COEF_PLANE_SIZE];
	struct rkvdec_vp9_intra_mode_probs intra_mode[10];
	u8 coef_inter[4][2][VDPU381_VP9_COEF_PLANE_SIZE];
} __packed;

union vdpu381_vp9_prob_tbl {
	struct vdpu381_vp9_frame_probs probs;
	u8 raw[ALIGN(VDPU381_VP9_PROB_TBL_SIZE, SZ_4K)];
};

/* Tables of a stream */
struct vdpu381_vp9_stream_tbl {
	union vdpu381_vp9_prob_tbl default_probs;
	/* Written by the hardware only */
	union vdpu381_vp9_prob_tbl ctx_probs[VDPU381_VP9_NUM_FRAME_CTXS];
	u8 segmap[2][RKVDEC_VP9_MAX_SEGMAP_SIZE];
};

/* Tables of a job, the hardware reads and writes them while it decodes */
struct vdpu381_vp9_job_tbl {
	union {
		struct vdpu381_vp9_inter_updates inter;
		struct vdpu381_vp9_intra_updates intra;
		u8 raw[ALIGN(VDPU381_VP9_PROB_TBL_SIZE, SZ_4K)];
	} updates;
	u8 counts[ALIGN(VDPU381_VP9_COUNT_TBL_SIZE, SZ_4K)];
};

struct vdpu381_vp9_flag_writer {
	u8 *flags;
	unsigned int pos;
};

static void vdpu381_vp9_skip_flags(struct vdpu381_vp9_flag_writer *fw,
				   unsigned int n)
{
	fw->pos += n;
}

static void vdpu381_vp9_set_flag(struct vdpu381_vp9_flag_writer *fw,
				 unsigned int pos)
{
	fw->flags[pos / 8] |= BIT(pos % 8);
}

/*
 * The compressed header codes the update of a probability as an index into
 * inv_map_table[] (spec 6.3.5). V4L2 passes the table entry, the hardware
 * wants the index back. The first 20 entries are 7 + 13 * i, the others are
 * the remaining values in increasing order.
 */
static u8 vdpu381_vp9_update_index(u8 v)
{
	if (v >= 7 && !((v - 7) % 13))
		return (v - 7) / 13;

	return 20 + v - 1 - (v + 6) / 13;
}

/*
 * Writes the flags of @n probabilities, and the updates to @delta in the
 * hardware form. A zero update means that the probability isn't updated,
 * and @upd is NULL if none of them can be. Motion vector updates are new
 * probabilities, which the hardware takes as they are (@mv).
 */
static void vdpu381_vp9_put_updates(struct vdpu381_vp9_flag_writer *fw,
				    u8 *delta, const u8 *upd, unsigned int n,
				    bool mv)
{
	unsigned int i;

	for (i = 0; upd && i < n; i++) {
		if (!upd[i])
			continue;

		vdpu381_vp9_set_flag(fw, fw->pos + i);
		if (delta)
			delta[i] = mv ? upd[i] : vdpu381_vp9_update_index(upd[i]);
	}

	vdpu381_vp9_skip_flags(fw, n);
}

/* The coefficient updates of one transform size and plane type */
static void vdpu381_vp9_put_coef_updates(struct vdpu381_vp9_flag_writer *fw,
					 u8 *plane, const u8 upd[6][6][3])
{
	const u8 *u = upd ? &upd[0][0][0] : NULL;
	unsigned int i, off;

	for (i = 0; u && i < 6 * 6 * 3; i++) {
		if (!u[i])
			continue;

		off = i / VDPU381_VP9_COEF_ROW_LEN * VDPU381_VP9_COEF_ROW_SIZE +
		      i % VDPU381_VP9_COEF_ROW_LEN;
		vdpu381_vp9_set_flag(fw, fw->pos + off);
		plane[off] = vdpu381_vp9_update_index(u[i]);
	}

	vdpu381_vp9_skip_flags(fw, VDPU381_VP9_COEF_PLANE_SIZE);
}

/*
 * The coefficient updates of all transform sizes and plane types, first those
 * of intra blocks, then those of inter blocks (@ref). The compressed header
 * codes no updates for the transform sizes the frame doesn't use (spec 6.3.7).
 */
static void vdpu381_vp9_put_coefs(struct vdpu381_vp9_flag_writer *fw,
				  u8 planes[4][2][VDPU381_VP9_COEF_PLANE_SIZE],
				  const struct v4l2_ctrl_vp9_compressed_hdr *hdr,
				  unsigned int ref)
{
	unsigned int i, j;

	for (i = 0; i < 4; i++) {
		bool coded = i <= hdr->tx_mode;

		for (j = 0; j < 2; j++)
			vdpu381_vp9_put_coef_updates(fw, planes[i][j],
						     coded ? hdr->coef[i][j][ref] : NULL);
	}
}

/* The skip and transform size updates, coded by intra and inter frames */
static void vdpu381_vp9_put_tx_skip(struct vdpu381_vp9_flag_writer *fw,
				    struct vdpu381_vp9_probs_head *head,
				    const struct v4l2_ctrl_vp9_compressed_hdr *hdr)
{
	bool tx_select = hdr->tx_mode == V4L2_VP9_TX_MODE_SELECT;

	vdpu381_vp9_put_updates(fw, head->skip, hdr->skip, 3, false);
	vdpu381_vp9_put_updates(fw, &head->tx32[0][0],
				tx_select ? &hdr->tx32[0][0] : NULL, 6, false);
	vdpu381_vp9_put_updates(fw, &head->tx16[0][0],
				tx_select ? &hdr->tx16[0][0] : NULL, 4, false);
	vdpu381_vp9_put_updates(fw, &head->tx8[0][0],
				tx_select ? &hdr->tx8[0][0] : NULL, 2, false);
}

static void vdpu381_vp9_put_seg_probs(struct vdpu381_vp9_probs_head *head,
				      const struct v4l2_ctrl_vp9_frame *dec_params)
{
	memcpy(head->seg_pred, dec_params->seg.pred_probs, sizeof(head->seg_pred));
	memcpy(head->seg_tree, dec_params->seg.tree_probs, sizeof(head->seg_tree));
}

static void vdpu381_vp9_write_intra_updates(struct vdpu381_vp9_intra_updates *tbl,
					    const struct v4l2_ctrl_vp9_frame *dec_params,
					    const struct v4l2_ctrl_vp9_compressed_hdr *hdr)
{
	struct vdpu381_vp9_flag_writer fw = { .flags = tbl->flags };
	unsigned int i, j, k, idx;

	/* No partition, segmentation and is_inter updates */
	vdpu381_vp9_skip_flags(&fw, 48 + 3 + 7);
	vdpu381_vp9_put_tx_skip(&fw, &tbl->head, hdr);
	vdpu381_vp9_skip_flags(&fw, 4 + 3);

	vdpu381_vp9_put_coefs(&fw, tbl->coef_intra, hdr, 0);
	vdpu381_vp9_put_coefs(&fw, tbl->coef_inter, hdr, 1);
	WARN_ON(fw.pos > sizeof(tbl->flags) * 8);

	memcpy(tbl->head.partition, v4l2_vp9_kf_partition_probs,
	       sizeof(tbl->head.partition));
	vdpu381_vp9_put_seg_probs(&tbl->head, dec_params);

	/* Rows of 27 probabilities, padded to 32 bytes */
	for (i = 0; i < ARRAY_SIZE(v4l2_vp9_kf_y_mode_prob); i++) {
		const u8 *p = &v4l2_vp9_kf_y_mode_prob[i][0][0];

		for (j = 0, idx = 0; j < sizeof(v4l2_vp9_kf_y_mode_prob[0]); j++) {
			tbl->intra_mode[i].y_mode[idx++] = p[j];
			if (!((j + 1) % VDPU381_VP9_COEF_ROW_LEN))
				idx += VDPU381_VP9_COEF_ROW_SIZE - VDPU381_VP9_COEF_ROW_LEN;
		}
	}

	/* 23 bytes in each of the first entries */
	for (k = 0; k < sizeof(v4l2_vp9_kf_uv_mode_prob); k++) {
		const u8 *p = &v4l2_vp9_kf_uv_mode_prob[0][0];

		tbl->intra_mode[k / 23].uv_mode[k % 23] = p[k];
	}
}

static void vdpu381_vp9_write_inter_updates(struct vdpu381_vp9_inter_updates *tbl,
					    const struct v4l2_ctrl_vp9_frame *dec_params,
					    const struct v4l2_ctrl_vp9_compressed_hdr *hdr)
{
	struct vdpu381_vp9_flag_writer fw = { .flags = tbl->flags };
	struct vdpu381_vp9_frame_probs *delta = &tbl->delta;
	struct v4l2_vp9_frame_mv_context *dmv = &delta->mv;
	const struct v4l2_vp9_mv_probs *mv = &hdr->mv;
	u8 ref_mode = dec_params->reference_mode;
	bool hp = dec_params->flags & V4L2_VP9_FRAME_FLAG_ALLOW_HIGH_PREC_MV;
	bool filter = dec_params->interpolation_filter ==
		      V4L2_VP9_INTERP_FILTER_SWITCHABLE;

	/* Same conditions as v4l2_vp9_fw_update_probs() */
	vdpu381_vp9_put_updates(&fw, &delta->head.partition[0][0],
				&hdr->partition[0][0], 48, false);
	vdpu381_vp9_skip_flags(&fw, 3 + 7);
	vdpu381_vp9_put_tx_skip(&fw, &delta->head, hdr);
	vdpu381_vp9_put_updates(&fw, delta->head.is_inter, hdr->is_inter, 4, false);
	vdpu381_vp9_skip_flags(&fw, 3);

	vdpu381_vp9_put_updates(&fw, &delta->y_mode[0][0], &hdr->y_mode[0][0],
				36, false);
	vdpu381_vp9_put_updates(&fw, delta->comp_mode,
				ref_mode == V4L2_VP9_REFERENCE_MODE_SELECT ?
				hdr->comp_mode : NULL, 5, false);
	vdpu381_vp9_put_updates(&fw, delta->comp_ref,
				ref_mode != V4L2_VP9_REFERENCE_MODE_SINGLE_REFERENCE ?
				hdr->comp_ref : NULL, 5, false);
	vdpu381_vp9_put_updates(&fw, &delta->single_ref[0][0],
				ref_mode != V4L2_VP9_REFERENCE_MODE_COMPOUND_REFERENCE ?
				&hdr->single_ref[0][0] : NULL, 10, false);
	vdpu381_vp9_put_updates(&fw, &delta->inter_mode[0][0],
				&hdr->inter_mode[0][0], 21, false);
	vdpu381_vp9_put_updates(&fw, &delta->interp_filter[0][0],
				filter ? &hdr->interp_filter[0][0] : NULL, 8, false);
	vdpu381_vp9_skip_flags(&fw, 11);

	vdpu381_vp9_put_coefs(&fw, delta->coef[0], hdr, 0);
	vdpu381_vp9_put_coefs(&fw, delta->coef[1], hdr, 1);

	/* The compressed header has no UV mode updates */
	vdpu381_vp9_skip_flags(&fw, 4 * 32);

	vdpu381_vp9_put_updates(&fw, dmv->joint, mv->joint, 3, true);
	vdpu381_vp9_put_updates(&fw, dmv->sign, mv->sign, 2, true);
	vdpu381_vp9_put_updates(&fw, &dmv->classes[0][0], &mv->classes[0][0],
				20, true);
	vdpu381_vp9_put_updates(&fw, dmv->class0_bit, mv->class0_bit, 2, true);
	vdpu381_vp9_put_updates(&fw, &dmv->bits[0][0], &mv->bits[0][0], 20, true);
	vdpu381_vp9_put_updates(&fw, &dmv->class0_fr[0][0][0],
				&mv->class0_fr[0][0][0], 12, true);
	vdpu381_vp9_put_updates(&fw, &dmv->fr[0][0], &mv->fr[0][0], 6, true);
	vdpu381_vp9_put_updates(&fw, dmv->class0_hp, hp ? mv->class0_hp : NULL,
				2, true);
	vdpu381_vp9_put_updates(&fw, dmv->hp, hp ? mv->hp : NULL, 2, true);
	WARN_ON(fw.pos > sizeof(tbl->flags) * 8);

	vdpu381_vp9_put_seg_probs(&delta->head, dec_params);
	/* The Rockchip MPP fills the unused part of the last UV mode row so */
	memset(&delta->uv_mode[3][9], 0xff, sizeof(delta->uv_mode[3]) - 9);
}

/* The probabilities of a frame context that was reset (spec 10.5). */
static void vdpu381_vp9_write_default_probs(struct vdpu381_vp9_frame_probs *probs)
{
	const struct v4l2_vp9_frame_context *def = &v4l2_vp9_default_probs;
	unsigned int i, j, k;

	memcpy(probs->head.partition, def->partition, sizeof(probs->head.partition));
	memcpy(probs->head.skip, def->skip, sizeof(probs->head.skip));
	memcpy(probs->head.tx32, def->tx32, sizeof(probs->head.tx32));
	memcpy(probs->head.tx16, def->tx16, sizeof(probs->head.tx16));
	memcpy(probs->head.tx8, def->tx8, sizeof(probs->head.tx8));
	memcpy(probs->head.is_inter, def->is_inter, sizeof(probs->head.is_inter));

	memcpy(probs->y_mode, def->y_mode, sizeof(probs->y_mode));
	memcpy(probs->comp_mode, def->comp_mode, sizeof(probs->comp_mode));
	memcpy(probs->comp_ref, def->comp_ref, sizeof(probs->comp_ref));
	memcpy(probs->single_ref, def->single_ref, sizeof(probs->single_ref));
	memcpy(probs->inter_mode, def->inter_mode, sizeof(probs->inter_mode));
	memcpy(probs->interp_filter, def->interp_filter,
	       sizeof(probs->interp_filter));

	for (i = 0; i < ARRAY_SIZE(def->coef); i++)
		for (j = 0; j < ARRAY_SIZE(def->coef[0]); j++)
			for (k = 0; k < ARRAY_SIZE(def->coef[0][0]); k++)
				write_coeff_plane(def->coef[i][j][k],
						  probs->coef[k][i][j]);

	for (i = 0; i < ARRAY_SIZE(def->uv_mode); i++)
		memcpy(&probs->uv_mode[i / 3][(i % 3) * 9], def->uv_mode[i],
		       sizeof(def->uv_mode[0]));

	probs->mv = def->mv;
}

#include "main_kern.c"
