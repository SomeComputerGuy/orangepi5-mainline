/* Kernel side and test driver */
#include <stdlib.h>
#include "harness.h"

static unsigned int rnd(unsigned int n) { return (unsigned int)random() % n; }

/* a random non-MV update: V4L2 value and the delta index + 1 for MPP */
static void upd(u8 *v4l2, u8 *idx, int prob)
{
	if (rnd(100) >= prob)
		return;
	int delp = rnd(254);	/* 0..253, see NOTES for 254 */
	*v4l2 = mpp_inv_map[delp];
	*idx = delp + 1;
}

static void upd_n(u8 *v4l2, u8 *idx, unsigned int n, int prob)
{
	for (unsigned int i = 0; i < n; i++)
		upd(&v4l2[i], &idx[i], prob);
}

static void mvupd_n(u8 *v4l2, u8 *idx, unsigned int n, int prob)
{
	for (unsigned int i = 0; i < n; i++)
		if (rnd(100) < prob)
			v4l2[i] = idx[i] = (rnd(128) << 1) | 1;
}

static int compare(const char *what, int iter, const u8 *a, const u8 *b, size_t n)
{
	for (size_t i = 0; i < n; i++)
		if (a[i] != b[i]) {
			printf("%s iter %d: first difference at byte %zu: kernel %02x mpp %02x\n",
			       what, iter, i, a[i], b[i]);
			return 1;
		}
	return 0;
}

int main(int argc, char **argv)
{
	static u8 kd[4864], md[4864], mdef[4864];
	static union vdpu381_vp9_prob_tbl kdef;
	int iters = argc > 1 ? atoi(argv[1]) : 2000, fails = 0;

	for (int d = 0; d < 254; d++)
		if (vdpu381_vp9_update_index(mpp_inv_map[d]) != d) {
			printf("update index of %d (value %d) is %d\n", d, mpp_inv_map[d],
			       vdpu381_vp9_update_index(mpp_inv_map[d]));
			fails++;
		}

	for (int it = 0; it < iters; it++) {
		struct v4l2_ctrl_vp9_compressed_hdr h = {}, ix = {};
		struct v4l2_ctrl_vp9_frame f = {};
		int prob = (int[]){ 0, 3, 30, 100 }[it % 4];
		int intra = it % 3 == 0;
		unsigned int i, j, k;

		srandom(it + 1);
		h.tx_mode = ix.tx_mode = rnd(5);
		if (intra)
			f.flags = rnd(2) ? V4L2_VP9_FRAME_FLAG_KEY_FRAME : V4L2_VP9_FRAME_FLAG_INTRA_ONLY;
		f.reference_mode = rnd(3);
		f.interpolation_filter = rnd(5);
		if (rnd(2))
			f.flags |= V4L2_VP9_FRAME_FLAG_ALLOW_HIGH_PREC_MV;
		for (i = 0; i < 3; i++)
			f.seg.pred_probs[i] = rnd(256);
		for (i = 0; i < 7; i++)
			f.seg.tree_probs[i] = rnd(256);

		/* only what the compressed header codes for this frame (spec 6.3) */
		if (h.tx_mode == V4L2_VP9_TX_MODE_SELECT) {
			upd_n(&h.tx8[0][0], &ix.tx8[0][0], 2, prob);
			upd_n(&h.tx16[0][0], &ix.tx16[0][0], 4, prob);
			upd_n(&h.tx32[0][0], &ix.tx32[0][0], 6, prob);
		}
		for (i = 0; i < 4 && (i == 0 || i - 1 < h.tx_mode); i++)
			for (j = 0; j < 2; j++)
				for (k = 0; k < 2; k++)
					for (unsigned int l = 0; l < 6; l++)
						for (unsigned int m = 0; m < (l ? 6 : 3); m++)
							upd_n(h.coef[i][j][k][l][m], ix.coef[i][j][k][l][m], 3, prob);
		upd_n(h.skip, ix.skip, 3, prob);
		if (!intra) {
			upd_n(&h.inter_mode[0][0], &ix.inter_mode[0][0], 21, prob);
			if (f.interpolation_filter == V4L2_VP9_INTERP_FILTER_SWITCHABLE)
				upd_n(&h.interp_filter[0][0], &ix.interp_filter[0][0], 8, prob);
			upd_n(h.is_inter, ix.is_inter, 4, prob);
			if (f.reference_mode == V4L2_VP9_REFERENCE_MODE_SELECT)
				upd_n(h.comp_mode, ix.comp_mode, 5, prob);
			if (f.reference_mode != V4L2_VP9_REFERENCE_MODE_COMPOUND_REFERENCE)
				upd_n(&h.single_ref[0][0], &ix.single_ref[0][0], 10, prob);
			if (f.reference_mode != V4L2_VP9_REFERENCE_MODE_SINGLE_REFERENCE)
				upd_n(h.comp_ref, ix.comp_ref, 5, prob);
			upd_n(&h.y_mode[0][0], &ix.y_mode[0][0], 36, prob);
			upd_n(&h.partition[0][0], &ix.partition[0][0], 48, prob);
			mvupd_n(h.mv.joint, ix.mv.joint, 3, prob);
			mvupd_n(h.mv.sign, ix.mv.sign, 2, prob);
			mvupd_n(&h.mv.classes[0][0], &ix.mv.classes[0][0], 20, prob);
			mvupd_n(h.mv.class0_bit, ix.mv.class0_bit, 2, prob);
			mvupd_n(&h.mv.bits[0][0], &ix.mv.bits[0][0], 20, prob);
			mvupd_n(&h.mv.class0_fr[0][0][0], &ix.mv.class0_fr[0][0][0], 12, prob);
			mvupd_n(&h.mv.fr[0][0], &ix.mv.fr[0][0], 6, prob);
			if (f.flags & V4L2_VP9_FRAME_FLAG_ALLOW_HIGH_PREC_MV) {
				mvupd_n(h.mv.class0_hp, ix.mv.class0_hp, 2, prob);
				mvupd_n(h.mv.hp, ix.mv.hp, 2, prob);
			}
		}

		memset(kd, 0, sizeof(kd));
		if (intra)
			vdpu381_vp9_write_intra_updates((void *)kd, &f, &h);
		else
			vdpu381_vp9_write_inter_updates((void *)kd, &f, &h);
		mpp_tables(&ix, &f, md, mdef);
		fails += compare(intra ? "intra updates" : "inter updates", it, kd, md, sizeof(kd));
	}

	memset(&kdef, 0, sizeof(kdef));
	vdpu381_vp9_write_default_probs(&kdef.probs);
	fails += compare("default probs", 0, kdef.raw, mdef, sizeof(mdef));

	printf("%d iterations, %d failures\n", iters, fails);
	return !!fails;
}
