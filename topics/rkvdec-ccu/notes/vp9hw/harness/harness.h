/* Interface between the MPP and the kernel side of the harness */
#include <stdint.h>
#include <linux/v4l2-controls.h>

/*
 * Updates in "spec" form, laid out like v4l2_ctrl_vp9_compressed_hdr: for the
 * non-MV probabilities the decoded delta index + 1 (0: no update), for the MV
 * probabilities the new probability (0: no update).
 */
void mpp_tables(const struct v4l2_ctrl_vp9_compressed_hdr *idx,
		const struct v4l2_ctrl_vp9_frame *f, uint8_t *delta, uint8_t *def);
extern const int *mpp_inv_map;
