/* MPP side: fills DXVA_PicParams_VP9 like vp9d_parser.c and calls the MPP table writers */
#include "harness.h"

void mpp_tables(const struct v4l2_ctrl_vp9_compressed_hdr *u,
		const struct v4l2_ctrl_vp9_frame *f, uint8_t *delta, uint8_t *def)
{
	static DXVA_PicParams_VP9 pp;
	DXVA_prob_vp9 *fl = &pp.prob_flag_delta.p_flag, *dl = &pp.prob_flag_delta.p_delta;
	int i, j, k, n;

	memset(&pp, 0, sizeof(pp));
	pp.frame_type = !(f->flags & V4L2_VP9_FRAME_FLAG_KEY_FRAME);
	pp.intra_only = !!(f->flags & V4L2_VP9_FRAME_FLAG_INTRA_ONLY);
	memcpy(pp.stVP9Segments.pred_probs, f->seg.pred_probs, 3);
	memcpy(pp.stVP9Segments.tree_probs, f->seg.tree_probs, 7);

#define NM(dst_f, dst_d, src, cnt) do {						\
		const uint8_t *_s = (const uint8_t *)(src);			\
		uint8_t *_f = (uint8_t *)(dst_f), *_d = (uint8_t *)(dst_d);	\
		for (n = 0; n < (cnt); n++)					\
			if (_s[n]) { _f[n] = 1; _d[n] = _s[n] - 1; }		\
	} while (0)
#define MV(dst_f, dst_d, src) do { if (src) { dst_f = 1; dst_d = src; } } while (0)

	NM(fl->tx8p, dl->tx8p, u->tx8, 2);
	NM(fl->tx16p, dl->tx16p, u->tx16, 4);
	NM(fl->tx32p, dl->tx32p, u->tx32, 6);
	NM(pp.prob_flag_delta.coef_flag, pp.prob_flag_delta.coef_delta, u->coef,
	   sizeof(u->coef));
	NM(fl->skip, dl->skip, u->skip, 3);
	NM(fl->mv_mode, dl->mv_mode, u->inter_mode, 21);
	NM(fl->filter, dl->filter, u->interp_filter, 8);
	NM(fl->intra, dl->intra, u->is_inter, 4);
	NM(fl->comp, dl->comp, u->comp_mode, 5);
	NM(fl->single_ref, dl->single_ref, u->single_ref, 10);
	NM(fl->comp_ref, dl->comp_ref, u->comp_ref, 5);
	NM(fl->y_mode, dl->y_mode, u->y_mode, 36);
	/* hardware (= spec) order, see vp9d_fill_picparams() */
	NM(fl->partition, dl->partition, u->partition, 48);
	for (i = 0; i < 3; i++)
		MV(fl->mv_joint[i], dl->mv_joint[i], u->mv.joint[i]);
	for (i = 0; i < 2; i++) {
		MV(fl->mv_comp[i].sign, dl->mv_comp[i].sign, u->mv.sign[i]);
		for (j = 0; j < 10; j++)
			MV(fl->mv_comp[i].classes[j], dl->mv_comp[i].classes[j], u->mv.classes[i][j]);
		MV(fl->mv_comp[i].class0, dl->mv_comp[i].class0, u->mv.class0_bit[i]);
		for (j = 0; j < 10; j++)
			MV(fl->mv_comp[i].bits[j], dl->mv_comp[i].bits[j], u->mv.bits[i][j]);
		for (j = 0; j < 2; j++)
			for (k = 0; k < 3; k++)
				MV(fl->mv_comp[i].class0_fp[j][k], dl->mv_comp[i].class0_fp[j][k],
				   u->mv.class0_fr[i][j][k]);
		for (j = 0; j < 3; j++)
			MV(fl->mv_comp[i].fp[j], dl->mv_comp[i].fp[j], u->mv.fr[i][j]);
		MV(fl->mv_comp[i].class0_hp, dl->mv_comp[i].class0_hp, u->mv.class0_hp[i]);
		MV(fl->mv_comp[i].hp, dl->mv_comp[i].hp, u->mv.hp[i]);
	}
	hal_vp9d_prob_flag_delta(delta, &pp);

	/* default table, written on an intra frame from the default context */
	memset(&pp, 0, sizeof(pp));
	memcpy(pp.prob.y_mode, vp9_default_probs.y_mode, sizeof(pp.prob.y_mode));
	/* ffmpeg intra mode order to hardware order, as TRANS_TO_HW_STYLE() */
	for (i = 0; i < 10; i++) {
		static const int ff[10] = { 2, 0, 1, 3, 4, 5, 6, 8, 7, 9 };

		memcpy(pp.prob.uv_mode[i], vp9_default_probs.uv_mode[ff[i]], 9);
	}
	memcpy(pp.prob.filter, vp9_default_probs.filter, sizeof(pp.prob.filter));
	memcpy(pp.prob.mv_mode, vp9_default_probs.mv_mode, sizeof(pp.prob.mv_mode));
	memcpy(pp.prob.intra, vp9_default_probs.intra, sizeof(pp.prob.intra));
	memcpy(pp.prob.comp, vp9_default_probs.comp, sizeof(pp.prob.comp));
	memcpy(pp.prob.single_ref, vp9_default_probs.single_ref, sizeof(pp.prob.single_ref));
	memcpy(pp.prob.comp_ref, vp9_default_probs.comp_ref, sizeof(pp.prob.comp_ref));
	memcpy(pp.prob.mv_joint, vp9_default_probs.mv_joint, sizeof(pp.prob.mv_joint));
	memcpy(pp.prob.mv_comp, vp9_default_probs.mv_comp, sizeof(pp.prob.mv_comp));
	/* ffmpeg order (64x64 first) to hardware order, as vp9d_fill_picparams() */
	for (i = 0; i < 4; i++)
		memcpy(pp.prob.partition[i], vp9_default_probs.partition[3 - i],
		       sizeof(pp.prob.partition[0]));
	pp.frame_type = 0;
	hal_vp9d_prob_default(def, &pp);
}
