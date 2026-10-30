struct v4l2_vp9_frame_mv_context {
	u8 joint[3];
	u8 sign[2];
	u8 classes[2][10];
	u8 class0_bit[2];
	u8 bits[2][10];
	u8 class0_fr[2][2][3];
	u8 fr[2][3];
	u8 class0_hp[2];
	u8 hp[2];
};
struct v4l2_vp9_frame_context {
	u8 tx8[2][1];
	u8 tx16[2][2];
	u8 tx32[2][3];
	u8 coef[4][2][2][6][6][3];
	u8 skip[3];
	u8 inter_mode[7][3];
	u8 interp_filter[4][2];
	u8 is_inter[4];
	u8 comp_mode[5];
	u8 single_ref[5][2];
	u8 comp_ref[5];
	u8 y_mode[4][9];
	u8 uv_mode[10][9];
	u8 partition[16][3];

	struct v4l2_vp9_frame_mv_context mv;
};
