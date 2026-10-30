// SPDX-License-Identifier: GPL-2.0
/*
 * venc-cycle: rkvenc-enc (maxout/tools) plus the reopen-fix test options:
 * -r loop the input, -k N STREAMOFF/STREAMON every N frames, -a N exit
 * with jobs in flight after N frames, -T per-frame completion times.
 *
 * rkvenc-enc: minimal V4L2 stateless H.264 / HEVC encoder client
 *
 * Drives the rockchip-venc (VEPU580) driver through the request API using
 * the H.264 stateless encode uAPI proposed by Paul Kocialkowski
 * (V4L2_CID_STATELESS_H264_ENCODE_PARAMS) or the proposed HEVC stateless
 * encode uAPI (V4L2_CID_STATELESS_HEVC_ENCODE_PARAMS, -e hevc). Reads raw
 * NV12 frames, writes an Annex-B H.264 or H.265 elementary stream.
 *
 * Build: aarch64-linux-gnu-gcc -O2 -Wall -I<kernel uapi headers> -o rkvenc-enc rkvenc-enc.c
 */

#include <errno.h>
#include <fcntl.h>
#include <getopt.h>
#include <poll.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <time.h>
#include <unistd.h>

#include <linux/media.h>
#include <linux/videodev2.h>
#include <linux/v4l2-controls.h>

#define MAX_BUFS	8

/* H.265 Table 7-1 */
#define HEVC_NAL_TRAIL_R	1
#define HEVC_NAL_IDR_W_RADL	19
#define MAX_PLANES	3

struct buf {
	int dmabuf_fd;			/* -s: imported frame, -1 if none */
	uint64_t id;			/* -s: sender's frame id */
	void *map[MAX_PLANES];
	size_t len[MAX_PLANES];
	bool queued;
	int req_fd;
	unsigned int frame;
};

struct opts {
	const char *in, *out, *dev, *mdev, *sock;
	unsigned int width, height, frames, gop, fps;
	unsigned int qp_i, qp_p, qp_min, qp_max;
	unsigned int bitrate, profile, level, inflight;
	bool cabac, cbr, verbose, hevc, tmvp, sao, lt, loop, times, realtime;
	unsigned int cycle, abort_after;
	unsigned long long pps_or;
	int cq;
};

static int xioctl(int fd, unsigned long req, void *arg)
{
	int ret;

	do {
		ret = ioctl(fd, req, arg);
	} while (ret < 0 && errno == EINTR);

	return ret;
}

#define CHECK(x) do { if ((x) < 0) { fprintf(stderr, "%s:%d: %s: %s\n", \
	__FILE__, __LINE__, #x, strerror(errno)); exit(1); } } while (0)

/* FNV-1a, to compare each coded frame with a reference run. */
static uint64_t fnv1a(const uint8_t *p, size_t n)
{
	uint64_t h = 0xcbf29ce484222325ULL;

	while (n--)
		h = (h ^ *p++) * 0x100000001b3ULL;
	return h;
}

static double now(void)
{
	struct timespec ts;

	clock_gettime(CLOCK_MONOTONIC, &ts);
	return ts.tv_sec + ts.tv_nsec / 1e9;
}

static int find_device(char *path, size_t len)
{
	struct v4l2_capability cap;
	int i, fd;

	for (i = 0; i < 64; i++) {
		snprintf(path, len, "/dev/video%d", i);
		fd = open(path, O_RDWR | O_NONBLOCK);
		if (fd < 0)
			continue;
		if (!xioctl(fd, VIDIOC_QUERYCAP, &cap) &&
		    !strcmp((char *)cap.driver, "rockchip-venc"))
			return fd;
		close(fd);
	}

	return -1;
}

static int find_media(int vfd, char *path, size_t len)
{
	struct media_device_info info;
	struct v4l2_capability cap;
	int i, fd;

	CHECK(xioctl(vfd, VIDIOC_QUERYCAP, &cap));
	for (i = 0; i < 64; i++) {
		snprintf(path, len, "/dev/media%d", i);
		fd = open(path, O_RDWR);
		if (fd < 0)
			continue;
		if (!xioctl(fd, MEDIA_IOC_DEVICE_INFO, &info) &&
		    (!strcmp(info.bus_info, (char *)cap.bus_info) ||
		     !strcmp(info.model, (char *)cap.driver)))
			return fd;
		close(fd);
	}

	return -1;
}

static void set_ctrl(int fd, uint32_t id, int64_t val)
{
	struct v4l2_ext_control c = { .id = id, .value64 = val };
	struct v4l2_ext_controls cs = {
		.which = V4L2_CTRL_WHICH_CUR_VAL, .count = 1, .controls = &c,
	};

	c.value = val;
	if (xioctl(fd, VIDIOC_S_EXT_CTRLS, &cs) < 0)
		fprintf(stderr, "warning: control %#x = %lld: %s\n", id,
			(long long)val, strerror(errno));
}

static void set_compound(int fd, uint32_t id, void *p, uint32_t size, int req_fd)
{
	struct v4l2_ext_control c = { .id = id, .size = size, .ptr = p };
	struct v4l2_ext_controls cs = {
		.which = req_fd >= 0 ? V4L2_CTRL_WHICH_REQUEST_VAL :
				       V4L2_CTRL_WHICH_CUR_VAL,
		.count = 1, .controls = &c, .request_fd = req_fd,
	};

	CHECK(xioctl(fd, VIDIOC_S_EXT_CTRLS, &cs));
}

static int get_req_ctrl(int fd, uint32_t id, int req_fd)
{
	struct v4l2_ext_control c = { .id = id };
	struct v4l2_ext_controls cs = {
		.which = V4L2_CTRL_WHICH_REQUEST_VAL, .count = 1,
		.controls = &c, .request_fd = req_fd,
	};

	if (xioctl(fd, VIDIOC_G_EXT_CTRLS, &cs) < 0)
		return -1;
	return c.value;
}

/* The vb2 timestamp of the OUTPUT buffer of frame n, in nanoseconds */
static uint64_t ts_ns(unsigned int n, unsigned int fps)
{
	return (uint64_t)(n / fps) * 1000000000ULL +
	       (uint64_t)((n % fps) * 1000000ULL / fps) * 1000ULL;
}

static int get_feedback(int fd, int req_fd,
			struct v4l2_ctrl_hevc_encode_feedback *fb)
{
	struct v4l2_ext_control c = {
		.id = V4L2_CID_STATELESS_HEVC_ENCODE_FEEDBACK,
		.size = sizeof(*fb), .ptr = fb,
	};
	struct v4l2_ext_controls cs = {
		.which = V4L2_CTRL_WHICH_REQUEST_VAL, .count = 1,
		.controls = &c, .request_fd = req_fd,
	};

	return xioctl(fd, VIDIOC_G_EXT_CTRLS, &cs);
}

/*
 * -s: one message per frame, with the dma-buf fd as SCM_RIGHTS ancillary data.
 * The frame is NV12 with the configured width/height and the encoder's stride
 * (UV plane at offset + stride * height). The answer is the id alone, once the
 * encoder has dequeued the buffer.
 */
struct frame_msg {
	uint32_t magic;		/* FRAME_MAGIC */
	uint32_t offset;	/* Y plane offset in the dma-buf */
	uint32_t stride;	/* must equal the encoder's bytesperline */
	uint32_t size;		/* dma-buf size */
	uint64_t id;
};
#define FRAME_MAGIC 0x4e563132	/* "NV12" */

static int recv_frame(int sfd, struct buf *b, unsigned int bpl, unsigned int h)
{
	struct frame_msg m;
	char cbuf[CMSG_SPACE(sizeof(int))];
	struct iovec iov = { .iov_base = &m, .iov_len = sizeof(m) };
	struct msghdr mh = { .msg_iov = &iov, .msg_iovlen = 1,
			     .msg_control = cbuf, .msg_controllen = sizeof(cbuf) };
	struct cmsghdr *c;
	ssize_t n;

	n = recvmsg(sfd, &mh, MSG_CMSG_CLOEXEC);
	if (n <= 0)
		return -1;
	c = CMSG_FIRSTHDR(&mh);
	if (n != sizeof(m) || m.magic != FRAME_MAGIC || !c ||
	    c->cmsg_type != SCM_RIGHTS) {
		fprintf(stderr, "bad frame message\n");
		return -1;
	}
	memcpy(&b->dmabuf_fd, CMSG_DATA(c), sizeof(int));
	if (m.stride != bpl || (uint64_t)m.offset + (uint64_t)bpl * h * 3 / 2 > m.size) {
		fprintf(stderr, "frame %llu: stride %u (want %u) / size %u don't fit\n",
			(unsigned long long)m.id, m.stride, bpl, m.size);
		close(b->dmabuf_fd);
		b->dmabuf_fd = -1;
		return -1;
	}
	b->id = m.id;
	b->len[0] = m.size;
	b->len[1] = m.offset;
	return 0;
}

static void release_frame(int sfd, struct buf *b)
{
	if (b->dmabuf_fd < 0)
		return;
	if (send(sfd, &b->id, sizeof(b->id), MSG_NOSIGNAL) < 0)
		perror("send");
	close(b->dmabuf_fd);
	b->dmabuf_fd = -1;
}

static void usage(const char *prog)
{
	fprintf(stderr,
		"usage: %s -i in.nv12 -o out.h264 -w W -h H [options]\n"
		"  -n N        frames to encode (default: whole file)\n"
		"  -g N        IDR period / GOP length (1 = intra only, default 30)\n"
		"  -q QP       I and P QP for fixed QP (default 26)\n"
		"  -b BPS      CBR target bitrate (enables frame RC)\n"
		"  -Q N        constant quality 1..100 (enables frame RC, CQ mode)\n"
		"  -f FPS      frame rate (default 30)\n"
		"  -p PROF     H.264: 66, 77 or 100 (default 100)\n"
		"  -l LEVEL    level_idc (default 51)\n"
		"  -c          CAVLC instead of CABAC (H.264)\n"
		"  -e CODEC    h264 (default) or hevc\n"
		"  -t          HEVC: temporal MV prediction\n"
		"  -S          HEVC: no SAO\n"
		"  -P FLAGS    HEVC: extra PPS flags (debugging)\n"
		"  -L          HEVC: keep the IDR as a long-term reference, and predict\n"
		"              every other P picture from it\n"
		"  -j N        frames in flight (default 2)\n"
		"  -d DEV      video device (default: find rockchip-venc)\n"
		"  -s PATH     zero-copy input: listen on unix socket PATH (SOCK_SEQPACKET) for\n"
		"              NV12 frames as dma-buf fds (struct frame_msg + SCM_RIGHTS), import\n"
		"              them (V4L2_MEMORY_DMABUF) and answer each with its id once the\n"
		"              encoder is done with it; -i is not used, encodes until the peer closes\n"
		"  -v          per-frame statistics\n", prog);
	exit(1);
}

int main(int argc, char **argv)
{
	struct opts o = {
		.gop = 30, .fps = 30, .qp_i = 26, .qp_p = 26, .qp_min = 10,
		.qp_max = 51, .profile = 100, .level = 51, .cabac = true,
		.inflight = 2, .cq = -1, .sao = true,
	};
	struct v4l2_ctrl_hevc_sps hsps = { 0 };
	struct v4l2_ctrl_hevc_pps hpps = { 0 };
	char vpath[64], mpath[64];
	struct v4l2_format ofmt = { 0 }, cfmt = { 0 };
	struct v4l2_requestbuffers rb;
	struct v4l2_streamparm parm = { 0 };
	struct v4l2_ctrl_h264_sps sps = { 0 };
	struct v4l2_ctrl_h264_pps pps = { 0 };
	struct buf obufs[MAX_BUFS] = { 0 }, cbufs[MAX_BUFS] = { 0 };
	unsigned int nobufs, ncbufs, i, p;
	unsigned int submitted = 0, done = 0, idr_frame = 0, frame_num = 0;
	unsigned int last_cycle = 0, cycles = 0, cbytes = 0;
	uint64_t chash = 0;
	unsigned long long total_bytes = 0;
	unsigned int feedback_errors = 0;
	size_t frame_size;
	uint8_t *frame = NULL;
	FILE *in = NULL, *out;
	int sfd = -1;
	int vfd, mfd, opt;
	double t0, t1;
	long fsize;

	while ((opt = getopt(argc, argv, "i:o:w:h:n:g:q:b:Q:f:p:l:cj:d:ve:tSLP:s:rk:a:TR")) != -1) {
		switch (opt) {
		case 'i': o.in = optarg; break;
		case 'o': o.out = optarg; break;
		case 'w': o.width = atoi(optarg); break;
		case 'h': o.height = atoi(optarg); break;
		case 'n': o.frames = atoi(optarg); break;
		case 'g': o.gop = atoi(optarg); break;
		case 'q': o.qp_i = o.qp_p = atoi(optarg); break;
		case 'b': o.bitrate = atoi(optarg); o.cbr = true; break;
		case 'Q': o.cq = atoi(optarg); break;
		case 'f': o.fps = atoi(optarg); break;
		case 'p': o.profile = atoi(optarg); break;
		case 'l': o.level = atoi(optarg); break;
		case 'c': o.cabac = false; break;
		case 'j': o.inflight = atoi(optarg); break;
		case 'd': o.dev = optarg; break;
		case 'v': o.verbose = true; break;
		case 'e': o.hevc = !strcmp(optarg, "hevc") || !strcmp(optarg, "h265"); break;
		case 't': o.tmvp = true; break;
		case 'S': o.sao = false; break;
		case 'L': o.lt = true; break;
		case 'P': o.pps_or = strtoull(optarg, NULL, 0); break;
		case 's': o.sock = optarg; break;
		case 'r': o.loop = true; break;
		case 'k': o.cycle = atoi(optarg); break;
		case 'a': o.abort_after = atoi(optarg); break;
		case 'T': o.times = true; break;
		case 'R': o.realtime = true; break;
		default: usage(argv[0]);
		}
	}

	if ((!o.in && !o.sock) || !o.out || !o.width || !o.height || !o.gop)
		usage(argv[0]);
	if (o.inflight < 1 || o.inflight > MAX_BUFS - 1)
		o.inflight = 2;
	if (o.profile == 66)
		o.cabac = false;

	frame_size = (size_t)o.width * o.height * 3 / 2;
	out = fopen(o.out, "wb");
	if (!out) {
		perror("fopen");
		return 1;
	}
	if (o.sock) {
		struct sockaddr_un sa = { .sun_family = AF_UNIX };
		int lfd = socket(AF_UNIX, SOCK_SEQPACKET, 0);

		CHECK(lfd);
		snprintf(sa.sun_path, sizeof(sa.sun_path), "%s", o.sock);
		unlink(o.sock);
		CHECK(bind(lfd, (struct sockaddr *)&sa, sizeof(sa)));
		CHECK(listen(lfd, 1));
		fprintf(stderr, "waiting for a frame source on %s\n", o.sock);
		sfd = accept(lfd, NULL, NULL);
		CHECK(sfd);
		close(lfd);
		if (!o.frames)
			o.frames = UINT32_MAX;
	} else {
		in = fopen(o.in, "rb");
		if (!in) {
			perror("fopen");
			return 1;
		}
		fseek(in, 0, SEEK_END);
		fsize = ftell(in);
		fseek(in, 0, SEEK_SET);
		if (!o.frames || (!o.loop && o.frames > fsize / frame_size))
			o.frames = o.loop && !o.frames ? UINT32_MAX : (o.frames ? o.frames : fsize / frame_size);
		if (!o.loop && o.frames > fsize / frame_size)
			o.frames = fsize / frame_size;
		frame = malloc(frame_size);
	}

	if (o.dev) {
		snprintf(vpath, sizeof(vpath), "%s", o.dev);
		vfd = open(vpath, O_RDWR | O_NONBLOCK);
	} else {
		vfd = find_device(vpath, sizeof(vpath));
	}
	CHECK(vfd);
	mfd = find_media(vfd, mpath, sizeof(mpath));
	CHECK(mfd);
	fprintf(stderr, "using %s and %s\n", vpath, mpath);

	/* Coded format first, then raw format. */
	cfmt.type = V4L2_BUF_TYPE_VIDEO_CAPTURE_MPLANE;
	cfmt.fmt.pix_mp.pixelformat = o.hevc ? V4L2_PIX_FMT_HEVC_SLICE :
					       V4L2_PIX_FMT_H264_SLICE;
	cfmt.fmt.pix_mp.width = o.width;
	cfmt.fmt.pix_mp.height = o.height;
	cfmt.fmt.pix_mp.num_planes = 1;
	CHECK(xioctl(vfd, VIDIOC_S_FMT, &cfmt));
	if (cfmt.fmt.pix_mp.pixelformat != (o.hevc ? V4L2_PIX_FMT_HEVC_SLICE :
						     V4L2_PIX_FMT_H264_SLICE)) {
		fprintf(stderr, "coded format not supported\n");
		return 1;
	}

	ofmt.type = V4L2_BUF_TYPE_VIDEO_OUTPUT_MPLANE;
	ofmt.fmt.pix_mp.pixelformat = V4L2_PIX_FMT_NV12;
	ofmt.fmt.pix_mp.width = o.width;
	ofmt.fmt.pix_mp.height = o.height;
	CHECK(xioctl(vfd, VIDIOC_S_FMT, &ofmt));
	if (ofmt.fmt.pix_mp.pixelformat != V4L2_PIX_FMT_NV12) {
		/* Some encoders (VPU121) only take the two-plane variant. */
		ofmt.fmt.pix_mp.pixelformat = V4L2_PIX_FMT_NV12M;
		ofmt.fmt.pix_mp.width = o.width;
		ofmt.fmt.pix_mp.height = o.height;
		CHECK(xioctl(vfd, VIDIOC_S_FMT, &ofmt));
		if (ofmt.fmt.pix_mp.pixelformat != V4L2_PIX_FMT_NV12M) {
			fprintf(stderr, "neither NV12 nor NV12M accepted\n");
			return 1;
		}
	}
	CHECK(xioctl(vfd, VIDIOC_G_FMT, &cfmt));
	fprintf(stderr, "raw %ux%u stride %u size %u, coded %ux%u buffer %u\n",
		ofmt.fmt.pix_mp.width, ofmt.fmt.pix_mp.height,
		ofmt.fmt.pix_mp.plane_fmt[0].bytesperline,
		ofmt.fmt.pix_mp.plane_fmt[0].sizeimage,
		cfmt.fmt.pix_mp.width, cfmt.fmt.pix_mp.height,
		cfmt.fmt.pix_mp.plane_fmt[0].sizeimage);

	parm.type = V4L2_BUF_TYPE_VIDEO_OUTPUT_MPLANE;
	parm.parm.output.timeperframe.numerator = 1;
	parm.parm.output.timeperframe.denominator = o.fps;
	CHECK(xioctl(vfd, VIDIOC_S_PARM, &parm));

	/* Sequence and picture parameters */
	if (o.hevc) {
		hsps.chroma_format_idc = 1;
		hsps.log2_max_pic_order_cnt_lsb_minus4 = 4;
		hsps.sps_max_dec_pic_buffering_minus1 = o.lt ? 2 : 1;
		hsps.log2_diff_max_min_luma_coding_block_size = 3;
		hsps.log2_diff_max_min_luma_transform_block_size = 3;
		hsps.max_transform_hierarchy_depth_inter = 0;
		hsps.max_transform_hierarchy_depth_intra = 0;
		hsps.flags = V4L2_HEVC_SPS_FLAG_STRONG_INTRA_SMOOTHING_ENABLED;
		if (o.sao)
			hsps.flags |= V4L2_HEVC_SPS_FLAG_SAMPLE_ADAPTIVE_OFFSET;
		if (o.tmvp)
			hsps.flags |= V4L2_HEVC_SPS_FLAG_SPS_TEMPORAL_MVP_ENABLED;
		if (o.lt)
			hsps.flags |= V4L2_HEVC_SPS_FLAG_LONG_TERM_REF_PICS_PRESENT;
		set_compound(vfd, V4L2_CID_STATELESS_HEVC_SPS, &hsps, sizeof(hsps), -1);

		hpps.flags = V4L2_HEVC_PPS_FLAG_PPS_LOOP_FILTER_ACROSS_SLICES_ENABLED |
			     V4L2_HEVC_PPS_FLAG_CU_QP_DELTA_ENABLED | o.pps_or;
		set_compound(vfd, V4L2_CID_STATELESS_HEVC_PPS, &hpps, sizeof(hpps), -1);

		set_ctrl(vfd, V4L2_CID_MPEG_VIDEO_PREPEND_SPSPPS_TO_IDR, 1);
		set_ctrl(vfd, V4L2_CID_MPEG_VIDEO_HEVC_I_FRAME_QP, o.qp_i);
		set_ctrl(vfd, V4L2_CID_MPEG_VIDEO_HEVC_P_FRAME_QP, o.qp_p);
		set_ctrl(vfd, V4L2_CID_MPEG_VIDEO_HEVC_MIN_QP, o.qp_min);
		set_ctrl(vfd, V4L2_CID_MPEG_VIDEO_HEVC_MAX_QP, o.qp_max);
	} else {
		sps.profile_idc = o.profile;
		sps.level_idc = o.level;
		sps.chroma_format_idc = 1;
		sps.log2_max_frame_num_minus4 = 12;
		sps.pic_order_cnt_type = 0;
		sps.log2_max_pic_order_cnt_lsb_minus4 = 12;
		sps.max_num_ref_frames = 1;
		sps.flags = V4L2_H264_SPS_FLAG_FRAME_MBS_ONLY |
			    V4L2_H264_SPS_FLAG_DIRECT_8X8_INFERENCE;
		if (o.profile == 66)
			sps.constraint_set_flags = 0x40 | 0x80; /* constrained baseline */
		set_compound(vfd, V4L2_CID_STATELESS_H264_SPS, &sps, sizeof(sps), -1);

		pps.pic_init_qp_minus26 = 0;
		pps.flags = V4L2_H264_PPS_FLAG_DEBLOCKING_FILTER_CONTROL_PRESENT;
		if (o.cabac)
			pps.flags |= V4L2_H264_PPS_FLAG_ENTROPY_CODING_MODE;
		if (o.profile == 100)
			pps.flags |= V4L2_H264_PPS_FLAG_TRANSFORM_8X8_MODE;
		set_compound(vfd, V4L2_CID_STATELESS_H264_PPS, &pps, sizeof(pps), -1);

		set_ctrl(vfd, V4L2_CID_MPEG_VIDEO_PREPEND_SPSPPS_TO_IDR, 1);
		set_ctrl(vfd, V4L2_CID_MPEG_VIDEO_H264_I_FRAME_QP, o.qp_i);
		set_ctrl(vfd, V4L2_CID_MPEG_VIDEO_H264_P_FRAME_QP, o.qp_p);
		set_ctrl(vfd, V4L2_CID_MPEG_VIDEO_H264_MIN_QP, o.qp_min);
		set_ctrl(vfd, V4L2_CID_MPEG_VIDEO_H264_MAX_QP, o.qp_max);
	}

	if (o.cbr) {
		set_ctrl(vfd, V4L2_CID_MPEG_VIDEO_FRAME_RC_ENABLE, 1);
		set_ctrl(vfd, V4L2_CID_MPEG_VIDEO_BITRATE_MODE,
			 V4L2_MPEG_VIDEO_BITRATE_MODE_CBR);
		set_ctrl(vfd, V4L2_CID_MPEG_VIDEO_BITRATE, o.bitrate);
	} else if (o.cq > 0) {
		set_ctrl(vfd, V4L2_CID_MPEG_VIDEO_FRAME_RC_ENABLE, 1);
		set_ctrl(vfd, V4L2_CID_MPEG_VIDEO_BITRATE_MODE,
			 V4L2_MPEG_VIDEO_BITRATE_MODE_CQ);
		set_ctrl(vfd, V4L2_CID_MPEG_VIDEO_CONSTANT_QUALITY, o.cq);
	} else {
		set_ctrl(vfd, V4L2_CID_MPEG_VIDEO_FRAME_RC_ENABLE, 0);
	}

	/* Buffers */
	memset(&rb, 0, sizeof(rb));
	rb.count = o.inflight + 1;
	rb.type = V4L2_BUF_TYPE_VIDEO_OUTPUT_MPLANE;
	rb.memory = o.sock ? V4L2_MEMORY_DMABUF : V4L2_MEMORY_MMAP;
	CHECK(xioctl(vfd, VIDIOC_REQBUFS, &rb));
	nobufs = rb.count > MAX_BUFS ? MAX_BUFS : rb.count;

	memset(&rb, 0, sizeof(rb));
	rb.count = o.inflight + 1;
	rb.type = V4L2_BUF_TYPE_VIDEO_CAPTURE_MPLANE;
	rb.memory = V4L2_MEMORY_MMAP;
	CHECK(xioctl(vfd, VIDIOC_REQBUFS, &rb));
	ncbufs = rb.count > MAX_BUFS ? MAX_BUFS : rb.count;

	for (i = 0; i < nobufs + ncbufs; i++) {
		bool isout = i < nobufs;
		struct buf *b = isout ? &obufs[i] : &cbufs[i - nobufs];
		struct v4l2_plane planes[MAX_PLANES] = { 0 };
		struct v4l2_buffer vb = { 0 };

		vb.type = isout ? V4L2_BUF_TYPE_VIDEO_OUTPUT_MPLANE :
				  V4L2_BUF_TYPE_VIDEO_CAPTURE_MPLANE;
		b->dmabuf_fd = -1;
		b->req_fd = -1;
		if (isout && o.sock) {	/* imported per frame, nothing to map */
			CHECK(xioctl(mfd, MEDIA_IOC_REQUEST_ALLOC, &b->req_fd));
			continue;
		}
		vb.memory = V4L2_MEMORY_MMAP;
		vb.index = isout ? i : i - nobufs;
		vb.m.planes = planes;
		vb.length = MAX_PLANES;
		CHECK(xioctl(vfd, VIDIOC_QUERYBUF, &vb));
		for (p = 0; p < vb.length; p++) {
			b->len[p] = planes[p].length;
			b->map[p] = mmap(NULL, planes[p].length,
					 PROT_READ | PROT_WRITE, MAP_SHARED,
					 vfd, planes[p].m.mem_offset);
			if (b->map[p] == MAP_FAILED) {
				perror("mmap");
				return 1;
			}
		}
		b->req_fd = -1;
		if (isout)
			CHECK(xioctl(mfd, MEDIA_IOC_REQUEST_ALLOC, &b->req_fd));
	}

	{
		int type = V4L2_BUF_TYPE_VIDEO_OUTPUT_MPLANE;

		CHECK(xioctl(vfd, VIDIOC_STREAMON, &type));
		type = V4L2_BUF_TYPE_VIDEO_CAPTURE_MPLANE;
		CHECK(xioctl(vfd, VIDIOC_STREAMON, &type));
	}

	if (o.cycle)	/* restart only at a GOP boundary */
		o.cycle = (o.cycle + o.gop - 1) / o.gop * o.gop;
	t0 = now();
	while (done < o.frames) {
		if (o.cycle && done && done == submitted && !(done % o.cycle) && done != last_cycle) {
			int type = V4L2_BUF_TYPE_VIDEO_OUTPUT_MPLANE;

			CHECK(xioctl(vfd, VIDIOC_STREAMOFF, &type));
			type = V4L2_BUF_TYPE_VIDEO_CAPTURE_MPLANE;
			CHECK(xioctl(vfd, VIDIOC_STREAMOFF, &type));
			CHECK(xioctl(vfd, VIDIOC_STREAMON, &type));
			type = V4L2_BUF_TYPE_VIDEO_OUTPUT_MPLANE;
			CHECK(xioctl(vfd, VIDIOC_STREAMON, &type));
			last_cycle = done;
			cycles++;
		}
		/* Submit as many frames as allowed. */
		while (submitted < o.frames && submitted - done < o.inflight &&
		       !(o.cycle && submitted != done && !(submitted % o.cycle))) {
			struct v4l2_ctrl_h264_encode_params ep = { 0 };
			struct v4l2_ctrl_hevc_encode_params hp = { 0 };
			struct v4l2_plane planes[MAX_PLANES] = { 0 };
			struct v4l2_buffer vb = { 0 };
			unsigned int bpl = ofmt.fmt.pix_mp.plane_fmt[0].bytesperline;
			unsigned int oi = submitted % nobufs;
			unsigned int ci = submitted % ncbufs;
			struct buf *ob = &obufs[oi];
			uint8_t *dst = ob->map[0];
			bool idr = !(submitted % o.gop);
			unsigned int y;

			/* -R: submit frame n no earlier than n / fps after the start. */
			while (o.realtime && now() < t0 + (double)submitted / o.fps)
				usleep(1000);

			if (o.sock) {
				if (recv_frame(sfd, ob, bpl, o.height) < 0) {
					o.frames = submitted;	/* peer closed: drain */
					break;
				}
			} else {
				if (fread(frame, 1, frame_size, in) != frame_size) {
					if (!o.loop)
						break;
					fseek(in, 0, SEEK_SET);
					if (fread(frame, 1, frame_size, in) != frame_size)
						break;
				}
				for (y = 0; y < o.height; y++)
					memcpy(dst + y * bpl, frame + y * o.width, o.width);
				/* NV12M (two planes, e.g. the VPU121 encoder) or NV12 */
				if (ofmt.fmt.pix_mp.num_planes > 1)
					for (y = 0; y < o.height / 2; y++)
						memcpy((uint8_t *)ob->map[1] +
						       y * ofmt.fmt.pix_mp.plane_fmt[1].bytesperline,
						       frame + o.width * o.height + y * o.width,
						       o.width);
				else
				for (y = 0; y < o.height / 2; y++)
					memcpy(dst + bpl * o.height + y * bpl,
					       frame + o.width * o.height + y * o.width,
					       o.width);
			}

			if (idr) {
				idr_frame = submitted;
				frame_num = 0;
			}
			if (o.hevc) {
				unsigned int poc = submitted - idr_frame;
				bool use_lt = o.lt && poc > 1 && !(poc % 2);

				hp.nuh_temporal_id_plus1 = 1;
				hp.pic_order_cnt_val = poc;
				hp.five_minus_max_num_merge_cand = 3;
				hp.flags = V4L2_HEVC_ENCODE_FLAG_REFERENCE;
				if (o.sao)
					hp.flags |= V4L2_HEVC_ENCODE_FLAG_SLICE_SAO_LUMA |
						    V4L2_HEVC_ENCODE_FLAG_SLICE_SAO_CHROMA;
				if (idr) {
					hp.nal_unit_type = HEVC_NAL_IDR_W_RADL;
					hp.slice_type = V4L2_HEVC_SLICE_TYPE_I;
				} else {
					hp.nal_unit_type = HEVC_NAL_TRAIL_R;
					hp.slice_type = V4L2_HEVC_SLICE_TYPE_P;
					hp.num_refs = 1;
					hp.refs[0].timestamp = ts_ns(submitted - 1, o.fps);
					hp.refs[0].flags = use_lt ? 0 :
						V4L2_HEVC_ENCODE_REF_FLAG_USED_BY_CURR_PIC;
					/* The IDR stays in the DPB as a long-term picture. */
					if (o.lt && poc > 1) {
						hp.num_refs = 2;
						hp.refs[1].timestamp = ts_ns(idr_frame, o.fps);
						hp.refs[1].flags = V4L2_HEVC_ENCODE_REF_FLAG_LONG_TERM;
						if (use_lt)
							hp.refs[1].flags |=
								V4L2_HEVC_ENCODE_REF_FLAG_USED_BY_CURR_PIC;
					}
					if (o.tmvp)
						hp.flags |= V4L2_HEVC_ENCODE_FLAG_SLICE_TEMPORAL_MVP_ENABLED;
				}
				set_compound(vfd, V4L2_CID_STATELESS_HEVC_ENCODE_PARAMS,
					     &hp, sizeof(hp), ob->req_fd);
			} else {
				ep.slice_type = idr ? V4L2_H264_SLICE_TYPE_I :
						      V4L2_H264_SLICE_TYPE_P;
				ep.nal_ref_idc = 1;
				ep.frame_num = frame_num;
				ep.idr_pic_id = (idr_frame / o.gop) & 0xffff;
				ep.pic_order_cnt_lsb = ((submitted - idr_frame) * 2) & 0xffff;
				ep.disable_deblocking_filter_idc = 0;
				ep.flags = idr ? V4L2_H264_ENCODE_FLAG_IDR_PIC : 0;
				frame_num = (frame_num + 1) & 0xffff;
				set_compound(vfd, V4L2_CID_STATELESS_H264_ENCODE_PARAMS,
					     &ep, sizeof(ep), ob->req_fd);

			}

			vb.type = V4L2_BUF_TYPE_VIDEO_OUTPUT_MPLANE;
			vb.memory = o.sock ? V4L2_MEMORY_DMABUF : V4L2_MEMORY_MMAP;
			vb.index = oi;
			vb.m.planes = planes;
			vb.length = ofmt.fmt.pix_mp.num_planes;
			planes[0].bytesused = ofmt.fmt.pix_mp.plane_fmt[0].sizeimage;
			if (ofmt.fmt.pix_mp.num_planes > 1)
				planes[1].bytesused = ofmt.fmt.pix_mp.plane_fmt[1].sizeimage;
			if (o.sock) {
				planes[0].m.fd = ob->dmabuf_fd;
				planes[0].length = ob->len[0];
				planes[0].data_offset = ob->len[1];	/* Y offset in the dma-buf */
				planes[0].bytesused = ob->len[1] +
					ofmt.fmt.pix_mp.plane_fmt[0].sizeimage;
				if (planes[0].bytesused > planes[0].length)
					planes[0].bytesused = planes[0].length;
			}
			vb.timestamp.tv_sec = submitted / o.fps;
			vb.timestamp.tv_usec = (submitted % o.fps) * 1000000ULL / o.fps;
			vb.flags = V4L2_BUF_FLAG_REQUEST_FD;
			vb.request_fd = ob->req_fd;
			CHECK(xioctl(vfd, VIDIOC_QBUF, &vb));
			ob->frame = submitted;

			memset(&vb, 0, sizeof(vb));
			memset(planes, 0, sizeof(planes));
			vb.type = V4L2_BUF_TYPE_VIDEO_CAPTURE_MPLANE;
			vb.memory = V4L2_MEMORY_MMAP;
			vb.index = ci;
			vb.m.planes = planes;
			vb.length = 1;
			CHECK(xioctl(vfd, VIDIOC_QBUF, &vb));

			CHECK(xioctl(ob->req_fd, MEDIA_REQUEST_IOC_QUEUE, NULL));
			submitted++;
		}

		/* Leave with jobs in flight and buffers queued. */
		if (o.abort_after && done >= o.abort_after) {
			fprintf(stderr, "aborting after %u frames, %u in flight\n", done, submitted - done);
			_exit(3);
		}

		if (submitted == done)
			break;

		/* Wait for the oldest frame. */
		{
			struct pollfd pfd = { .fd = obufs[done % nobufs].req_fd,
					      .events = POLLPRI };
			struct v4l2_plane planes[MAX_PLANES] = { 0 };
			struct v4l2_buffer vb = { 0 };
			struct buf *ob = &obufs[done % nobufs];
			int ret, qp;

			ret = poll(&pfd, 1, 5000);
			if (ret <= 0) {
				fprintf(stderr, "timeout waiting for frame %u\n", done);
				return 1;
			}

			vb.type = V4L2_BUF_TYPE_VIDEO_CAPTURE_MPLANE;
			vb.memory = V4L2_MEMORY_MMAP;
			vb.m.planes = planes;
			vb.length = 1;
			CHECK(xioctl(vfd, VIDIOC_DQBUF, &vb));
			if (vb.flags & V4L2_BUF_FLAG_ERROR) {
				fprintf(stderr, "frame %u: encode error\n", done);
				return 1;
			}
			fwrite(cbufs[vb.index].map[0], 1, planes[0].bytesused, out);
			cbytes = planes[0].bytesused;
			if (o.times)
				chash = fnv1a(cbufs[vb.index].map[0], cbytes);
			total_bytes += planes[0].bytesused;

			qp = get_req_ctrl(vfd, V4L2_CID_MPEG_VIDEO_AVERAGE_QP,
					  ob->req_fd);
			if (o.verbose)
				fprintf(stderr, "frame %u: %c %u bytes avg qp %d\n",
					done,
					vb.flags & V4L2_BUF_FLAG_KEYFRAME ? 'I' : 'P',
					planes[0].bytesused, qp);
			if (o.hevc) {
				struct v4l2_ctrl_hevc_encode_feedback fb = { 0 };
				int poc = done % o.gop;

				if (get_feedback(vfd, ob->req_fd, &fb) < 0) {
					fprintf(stderr, "frame %u: no feedback: %s\n",
						done, strerror(errno));
					feedback_errors++;
				} else if (fb.timestamp != ts_ns(done, o.fps) ||
					   fb.pic_order_cnt_val != poc ||
					   (poc && (fb.num_ref_idx_l0_active != 1 ||
						    fb.ref_idx_l0[0] != (o.lt && poc > 1 && !(poc % 2))))) {
					fprintf(stderr, "frame %u: unexpected feedback: ts %llu poc %d l0 %u [%u]\n",
						done, (unsigned long long)fb.timestamp,
						fb.pic_order_cnt_val, fb.num_ref_idx_l0_active,
						fb.ref_idx_l0[0]);
					feedback_errors++;
				}
				if (o.verbose)
					fprintf(stderr,
						"  feedback: poc %d nal %u type %u qp %d l0 %u [%u] hdr %u qp %u/%u [%d..%d] sse %llu intra %u inter %u flags %#x\n",
						fb.pic_order_cnt_val, fb.nal_unit_type,
						fb.slice_type, fb.slice_qp,
						fb.num_ref_idx_l0_active, fb.ref_idx_l0[0],
						fb.stats.header_size, fb.stats.qp_sum,
						fb.stats.qp_count, fb.stats.qp_min,
						fb.stats.qp_max,
						(unsigned long long)fb.stats.sse_luma,
						fb.stats.num_intra_blocks,
						fb.stats.num_inter_blocks,
						(unsigned int)fb.flags);
			}

			memset(&vb, 0, sizeof(vb));
			memset(planes, 0, sizeof(planes));
			vb.type = V4L2_BUF_TYPE_VIDEO_OUTPUT_MPLANE;
			vb.memory = o.sock ? V4L2_MEMORY_DMABUF : V4L2_MEMORY_MMAP;
			vb.m.planes = planes;
			vb.length = MAX_PLANES;
			CHECK(xioctl(vfd, VIDIOC_DQBUF, &vb));
			if (o.sock)	/* the encoder is done with it: hand it back */
				release_frame(sfd, &obufs[vb.index]);

			CHECK(xioctl(ob->req_fd, MEDIA_REQUEST_IOC_REINIT, NULL));
			if (o.times)
				fprintf(stderr, "F %u %.6f %u %016llx\n", done, now(), cbytes,
					(unsigned long long)chash);
			done++;
		}
	}
	t1 = now();

	fprintf(stderr,
		"encoded %u frames in %.3f s: %.2f fps, %llu bytes, %.1f kbit/s at %u fps\n",
		done, t1 - t0, done / (t1 - t0), total_bytes,
		done ? total_bytes * 8.0 * o.fps / done / 1000 : 0, o.fps);

	if (o.hevc)
		fprintf(stderr, "feedback errors: %u\n", feedback_errors);
	if (o.cycle)
		fprintf(stderr, "stream restarts: %u\n", cycles);

	fclose(out);
	if (in)
		fclose(in);
	if (sfd >= 0)
		close(sfd);
	close(mfd);
	close(vfd);
	return 0;
}
