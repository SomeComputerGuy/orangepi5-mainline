// SPDX-License-Identifier: GPL-2.0-only
/*
 * Dump the SPS short-term RPS sets of Annex-B HEVC streams, to pick stream
 * pairs for the rkvdec SPS-change test (TESTING.md, test C).
 *
 * For every distinct SPS: "name sps_id WxH bitdepth chroma nsets set0 all"
 * where set0 is the derived first set ("-" when there are none) and all is
 * an FNV-1a hash of every derived set; with SPSDUMP_ALL=1 every set is
 * printed as well. Built with tools/spsdump.sh against
 * the host libavcodec of the ffmpeg-hevc-extsps work.
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "config.h"
#include "libavutil/common.h"
#include "libavutil/mem.h"
#include "libavcodec/avcodec.h"
#include "libavcodec/h2645_parse.h"
#include "libavcodec/hevc/hevc.h"
#include "libavcodec/hevc/ps.h"

static uint32_t fnv(uint32_t h, const void *p, size_t n)
{
	const uint8_t *b = p;

	while (n--)
		h = (h ^ *b++) * 16777619u;
	return h;
}

static void set_str(const ShortTermRPS *r, char *s, size_t n)
{
	int len = snprintf(s, n, "n%dp%d:", r->num_negative_pics,
			   r->num_delta_pocs - r->num_negative_pics);

	for (int i = 0; i < r->num_delta_pocs && len < (int)n; i++)
		len += snprintf(s + len, n - len, "%s%d%s", i ? "," : "",
				r->delta_poc[i], (r->used >> i) & 1 ? "" : "u");
}

static void dump(const char *name, unsigned int id, const HEVCSPS *sps)
{
	uint32_t h = 2166136261u;
	char s0[256] = "-";

	for (unsigned int i = 0; i < sps->nb_st_rps; i++) {
		const ShortTermRPS *r = &sps->st_rps[i];
		int32_t v[3] = { r->num_negative_pics, r->num_delta_pocs, (int32_t)r->used };

		h = fnv(h, v, sizeof(v));
		h = fnv(h, r->delta_poc, r->num_delta_pocs * sizeof(r->delta_poc[0]));
	}
	if (sps->nb_st_rps)
		set_str(&sps->st_rps[0], s0, sizeof(s0));
	printf("%s %u %dx%d %d %d %u %s %08x\n", name, id, sps->width, sps->height,
	       sps->bit_depth, sps->chroma_format_idc, sps->nb_st_rps, s0,
	       sps->nb_st_rps ? h : 0);
	if (getenv("SPSDUMP_ALL"))
		for (unsigned int i = 0; i < sps->nb_st_rps; i++) {
			set_str(&sps->st_rps[i], s0, sizeof(s0));
			printf("  set %u %s\n", i, s0);
		}
}

int main(int argc, char **argv)
{
	AVCodecContext *avctx = avcodec_alloc_context3(NULL);

	av_log_set_level(AV_LOG_QUIET);
	for (int a = 1; a < argc; a++) {
		const HEVCSPS *seen[HEVC_MAX_SPS_COUNT] = { 0 };
		const char *name = strrchr(argv[a], '/') ? strrchr(argv[a], '/') + 1 : argv[a];
		HEVCParamSets ps = { 0 };
		H2645Packet pkt = { 0 };
		FILE *f = fopen(argv[a], "rb");
		uint8_t *buf;
		long len;

		if (!f) {
			perror(argv[a]);
			continue;
		}
		fseek(f, 0, SEEK_END);
		len = ftell(f);
		fseek(f, 0, SEEK_SET);
		buf = av_mallocz(len + AV_INPUT_BUFFER_PADDING_SIZE);
		if (!buf || fread(buf, 1, len, f) != (size_t)len) {
			fclose(f);
			av_free(buf);
			continue;
		}
		fclose(f);
		if (ff_h2645_packet_split(&pkt, buf, len, avctx, 0, AV_CODEC_ID_HEVC, 0) >= 0) {
			for (int i = 0; i < pkt.nb_nals; i++) {
				H2645NAL *nal = &pkt.nals[i];

				if (nal->nuh_layer_id)
					continue;
				if (nal->type == HEVC_NAL_VPS)
					ff_hevc_decode_nal_vps(&nal->gb, avctx, &ps);
				else if (nal->type == HEVC_NAL_SPS &&
					 ff_hevc_decode_nal_sps(&nal->gb, avctx, &ps, 0, 0) >= 0)
					for (unsigned int id = 0; id < HEVC_MAX_SPS_COUNT; id++)
						if (ps.sps_list[id] && ps.sps_list[id] != seen[id]) {
							seen[id] = ps.sps_list[id];
							dump(name, id, ps.sps_list[id]);
						}
			}
		}
		ff_h2645_packet_uninit(&pkt);
		ff_hevc_ps_uninit(&ps);
		av_free(buf);
	}
	avcodec_free_context(&avctx);
	return 0;
}
