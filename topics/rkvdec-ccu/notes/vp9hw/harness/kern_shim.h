/* Minimal environment for the extracted kernel table code */
#ifndef KERN_SHIM_H
#define KERN_SHIM_H
#include <stdint.h>
#include <stdbool.h>
#include <string.h>
#include <stdio.h>
#include <linux/v4l2-controls.h>
typedef uint8_t u8;
typedef uint16_t u16;
typedef uint32_t u32;
typedef uint64_t u64;
typedef int16_t s16;
#define __packed __attribute__((packed))
#define BIT(n) (1u << (n))
#define ALIGN(x, a) ((((x) + (a) - 1) / (a)) * (a))
#define SZ_4K 4096
#define ARRAY_SIZE(a) (sizeof(a) / sizeof((a)[0]))
#define WARN_ON(c) ({ int _c = !!(c); if (_c) fprintf(stderr, "WARN %s:%d\n", __FILE__, __LINE__); _c; })
#include "v4l2_vp9_types.h"
extern const u8 v4l2_vp9_kf_y_mode_prob[10][10][9];
extern const u8 v4l2_vp9_kf_partition_probs[16][3];
extern const u8 v4l2_vp9_kf_uv_mode_prob[10][9];
extern const struct v4l2_vp9_frame_context v4l2_vp9_default_probs;
struct rkvdec_vp9_intra_mode_probs {
	u8 y_mode[105];
	u8 uv_mode[23];
};
void write_coeff_plane(const u8 coef[6][6][3], u8 *coeff_plane);
#endif
