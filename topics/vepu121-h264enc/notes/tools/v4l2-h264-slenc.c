// SPDX-License-Identifier: GPL-2.0
/*
 * Minimal test client for the V4L2 H.264 stateless encoder uAPI
 * (V4L2_CID_STATELESS_H264_ENCODE_PARAMS, Paul Kocialkowski's v1 series),
 * as implemented by the hantro driver on the Rockchip VEPU2 / RK3588 VEPU121.
 *
 * Reads raw NV12 frames, encodes them through the media request API and
 * writes an Annex B H.264 elementary stream.
 *
 * Build: aarch64-linux-gnu-gcc -O2 -Wall -static -I<uapi headers> \
 *        -o v4l2-h264-slenc v4l2-h264-slenc.c
 */

#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <getopt.h>
#include <poll.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/sysmacros.h>
#include <time.h>
#include <unistd.h>

#include <linux/media.h>
#include <linux/videodev2.h>
#include <linux/v4l2-controls.h>

#define MAX_BUFS	8

struct buf {
	void *addr[2];
	size_t len[2];
	int req_fd;
	int busy;
	unsigned int frame;
};

static struct {
	const char *video, *media, *in, *out;
	unsigned int width, height, frames, gop, depth, fps;
	int qp_i, qp_p, qp_min, qp_max;
	int cabac, profile, level, rc, bitrate, quality, verbose, aud, t8x8;
	int deblock_off;
	int yuyv;
} opt = {
	.width = 1920, .height = 1080, .frames = 0, .gop = 30, .depth = 2,
	.fps = 30, .qp_i = 26, .qp_p = 28, .qp_min = 0, .qp_max = 51,
	.profile = 77, .level = 40,
};

static int xioctl(int fd, unsigned long req, void *arg, const char *name)
{
	int ret;

	do {
		ret = ioctl(fd, req, arg);
	} while (ret < 0 && errno == EINTR);
	if (ret < 0 && name)
		fprintf(stderr, "%s: %s\n", name, strerror(errno));
	return ret;
}

static double now(void)
{
	struct timespec ts;

	clock_gettime(CLOCK_MONOTONIC, &ts);
	return ts.tv_sec + ts.tv_nsec / 1e9;
}

static int is_encoder(int fd)
{
	struct v4l2_capability cap = { 0 };
	struct v4l2_fmtdesc fd_ = { .type = V4L2_BUF_TYPE_VIDEO_CAPTURE_MPLANE };

	if (ioctl(fd, VIDIOC_QUERYCAP, &cap))
		return 0;
	for (fd_.index = 0; !ioctl(fd, VIDIOC_ENUM_FMT, &fd_); fd_.index++)
		if (fd_.pixelformat == V4L2_PIX_FMT_H264_SLICE)
			return 1;
	return 0;
}

static int find_video(char *path, size_t len)
{
	char p[64];
	int i, fd;

	for (i = 0; i < 64; i++) {
		snprintf(p, sizeof(p), "/dev/video%d", i);
		fd = open(p, O_RDWR | O_NONBLOCK);
		if (fd < 0)
			continue;
		if (is_encoder(fd)) {
			close(fd);
			snprintf(path, len, "%s", p);
			return 0;
		}
		close(fd);
	}
	return -1;
}

/* Find the media device that has an interface for the video node. */
static int find_media(const char *video, char *path, size_t len)
{
	struct stat st;
	char p[64];
	int i;

	if (stat(video, &st))
		return -1;

	for (i = 0; i < 64; i++) {
		struct media_v2_topology topo = { 0 };
		struct media_v2_interface *ifs;
		int fd, found = 0;
		unsigned int j;

		snprintf(p, sizeof(p), "/dev/media%d", i);
		fd = open(p, O_RDWR);
		if (fd < 0)
			continue;
		if (ioctl(fd, MEDIA_IOC_G_TOPOLOGY, &topo)) {
			close(fd);
			continue;
		}
		ifs = calloc(topo.num_interfaces, sizeof(*ifs));
		topo.ptr_interfaces = (uintptr_t)ifs;
		if (!ioctl(fd, MEDIA_IOC_G_TOPOLOGY, &topo))
			for (j = 0; j < topo.num_interfaces; j++)
				if (ifs[j].devnode.major == major(st.st_rdev) &&
				    ifs[j].devnode.minor == minor(st.st_rdev))
					found = 1;
		free(ifs);
		close(fd);
		if (found) {
			snprintf(path, len, "%s", p);
			return 0;
		}
	}
	return -1;
}

static int set_ctrl(int fd, int req_fd, unsigned int id, int value)
{
	struct v4l2_ext_control c = { .id = id, .value = value };
	struct v4l2_ext_controls cs = { .count = 1, .controls = &c };

	if (req_fd >= 0) {
		cs.which = V4L2_CTRL_WHICH_REQUEST_VAL;
		cs.request_fd = req_fd;
	}
	return xioctl(fd, VIDIOC_S_EXT_CTRLS, &cs, NULL);
}

static int set_compound(int fd, int req_fd, unsigned int id, void *p,
			unsigned int size)
{
	struct v4l2_ext_control c = { .id = id, .size = size, .ptr = p };
	struct v4l2_ext_controls cs = { .count = 1, .controls = &c };

	if (req_fd >= 0) {
		cs.which = V4L2_CTRL_WHICH_REQUEST_VAL;
		cs.request_fd = req_fd;
	}
	return xioctl(fd, VIDIOC_S_EXT_CTRLS, &cs, "S_EXT_CTRLS compound");
}

static int get_compound(int fd, int req_fd, unsigned int id, void *p,
			unsigned int size)
{
	struct v4l2_ext_control c = { .id = id, .size = size, .ptr = p };
	struct v4l2_ext_controls cs = { .count = 1, .controls = &c };

	if (req_fd >= 0) {
		cs.which = V4L2_CTRL_WHICH_REQUEST_VAL;
		cs.request_fd = req_fd;
	}
	return xioctl(fd, VIDIOC_G_EXT_CTRLS, &cs, NULL);
}

static void usage(const char *name)
{
	fprintf(stderr,
		"Usage: %s -i in.nv12 -o out.h264 [options]\n"
		"  -d /dev/videoN    encoder node (auto)\n"
		"  -m /dev/mediaN    media node (auto)\n"
		"  -W width -H height (1920x1080), -n frames (all)\n"
		"  -g gop (30, 1 = all intra), -r fps (30), -D depth (2)\n"
		"  -q qp_i[:qp_p] (26:28), -l qp_min:qp_max\n"
		"  -b bitrate        CBR rate control, bits/s\n"
		"  -Q quality        CQ rate control, 0-100\n"
		"  -c                CABAC (Main/High)\n"
		"  -p profile_idc    66, 77 (default) or 100\n"
		"  -8                8x8 transform (High)\n"
		"  -L level_idc (40), -a AUD, -F disable deblocking, -v verbose\n"
		"  -Y                input is YUYV 4:2:2 (default NV12), '-' reads stdin\n",
		name);
}

int main(int argc, char **argv)
{
	char video[64], media[64];
	struct v4l2_format fmt_out = { 0 }, fmt_cap = { 0 };
	struct v4l2_requestbuffers rb = { 0 };
	struct buf out[MAX_BUFS] = { 0 }, cap[MAX_BUFS] = { 0 };
	struct v4l2_ctrl_h264_sps sps = { 0 };
	struct v4l2_ctrl_h264_pps pps = { 0 };
	unsigned int aw, ah, i, queued = 0, done = 0, next = 0, idr_id = 0;
	unsigned int frame_size, in_frames;
	unsigned long long total = 0, total_i = 0, n_i = 0;
	unsigned int qp_hist_min = 99, qp_hist_max = 0;
	unsigned char *frame;
	double t0, t1;
	FILE *fin, *fout;
	int vfd, mfd, c, type;
	struct stat st;

	while ((c = getopt(argc, argv, "d:m:i:o:W:H:n:g:r:D:q:l:b:Q:cp:8L:aFvhY")) != -1) {
		switch (c) {
		case 'd': opt.video = optarg; break;
		case 'm': opt.media = optarg; break;
		case 'i': opt.in = optarg; break;
		case 'o': opt.out = optarg; break;
		case 'W': opt.width = atoi(optarg); break;
		case 'H': opt.height = atoi(optarg); break;
		case 'n': opt.frames = atoi(optarg); break;
		case 'g': opt.gop = atoi(optarg); break;
		case 'r': opt.fps = atoi(optarg); break;
		case 'D': opt.depth = atoi(optarg); break;
		case 'q':
			opt.qp_i = opt.qp_p = atoi(optarg);
			if (strchr(optarg, ':'))
				opt.qp_p = atoi(strchr(optarg, ':') + 1);
			break;
		case 'l':
			opt.qp_min = atoi(optarg);
			if (strchr(optarg, ':'))
				opt.qp_max = atoi(strchr(optarg, ':') + 1);
			break;
		case 'b': opt.rc = 1; opt.bitrate = atoi(optarg); break;
		case 'Q': opt.rc = 2; opt.quality = atoi(optarg); break;
		case 'c': opt.cabac = 1; break;
		case 'p': opt.profile = atoi(optarg); break;
		case '8': opt.t8x8 = 1; break;
		case 'L': opt.level = atoi(optarg); break;
		case 'a': opt.aud = 1; break;
		case 'F': opt.deblock_off = 1; break;
		case 'v': opt.verbose++; break;
		case 'Y': opt.yuyv = 1; break;
		default: usage(argv[0]); return 1;
		}
	}
	if (!opt.in || !opt.out || opt.depth < 1 || opt.depth > MAX_BUFS || !opt.gop) {
		usage(argv[0]);
		return 1;
	}

	if (!opt.video) {
		if (find_video(video, sizeof(video))) {
			fprintf(stderr, "no H.264 stateless encoder found\n");
			return 1;
		}
		opt.video = video;
	}
	if (!opt.media) {
		if (find_media(opt.video, media, sizeof(media))) {
			fprintf(stderr, "no media device for %s\n", opt.video);
			return 1;
		}
		opt.media = media;
	}

	vfd = open(opt.video, O_RDWR | O_NONBLOCK);
	mfd = open(opt.media, O_RDWR);
	if (vfd < 0 || mfd < 0) {
		perror("open");
		return 1;
	}

	fin = strcmp(opt.in, "-") ? fopen(opt.in, "rb") : stdin;
	fout = fopen(opt.out, "wb");
	if (!fin || !fout) {
		perror("fopen");
		return 1;
	}
	frame_size = opt.width * opt.height * (opt.yuyv ? 2 : 3) / (opt.yuyv ? 1 : 2);
	fstat(fileno(fin), &st);
	in_frames = S_ISREG(st.st_mode) ? st.st_size / frame_size : ~0U;
	if (!opt.frames || opt.frames > in_frames)
		opt.frames = in_frames;
	frame = malloc(frame_size);

	aw = (opt.width + 15) & ~15;
	ah = (opt.height + 15) & ~15;

	/* Coded format first, then the raw format, then the crop. */
	fmt_cap.type = V4L2_BUF_TYPE_VIDEO_CAPTURE_MPLANE;
	fmt_cap.fmt.pix_mp.pixelformat = V4L2_PIX_FMT_H264_SLICE;
	fmt_cap.fmt.pix_mp.width = aw;
	fmt_cap.fmt.pix_mp.height = ah;
	fmt_cap.fmt.pix_mp.num_planes = 1;
	if (xioctl(vfd, VIDIOC_S_FMT, &fmt_cap, "S_FMT capture"))
		return 1;

	fmt_out.type = V4L2_BUF_TYPE_VIDEO_OUTPUT_MPLANE;
	fmt_out.fmt.pix_mp.pixelformat = opt.yuyv ? V4L2_PIX_FMT_YUYV :
						    V4L2_PIX_FMT_NV12M;
	fmt_out.fmt.pix_mp.width = aw;
	fmt_out.fmt.pix_mp.height = ah;
	fmt_out.fmt.pix_mp.num_planes = opt.yuyv ? 1 : 2;
	if (xioctl(vfd, VIDIOC_S_FMT, &fmt_out, "S_FMT output"))
		return 1;
	if (fmt_out.fmt.pix_mp.pixelformat != (opt.yuyv ? V4L2_PIX_FMT_YUYV : V4L2_PIX_FMT_NV12M) ||
	    fmt_out.fmt.pix_mp.width != aw || fmt_out.fmt.pix_mp.height != ah) {
		fprintf(stderr, "unexpected output format %ux%u\n",
			fmt_out.fmt.pix_mp.width, fmt_out.fmt.pix_mp.height);
		return 1;
	}

	if (aw != opt.width || ah != opt.height) {
		struct v4l2_selection sel = {
			.type = V4L2_BUF_TYPE_VIDEO_OUTPUT,
			.target = V4L2_SEL_TGT_CROP,
			.r = { 0, 0, opt.width, opt.height },
		};

		if (xioctl(vfd, VIDIOC_S_SELECTION, &sel, "S_SELECTION"))
			return 1;
	}

	{
		struct v4l2_streamparm parm = {
			.type = V4L2_BUF_TYPE_VIDEO_OUTPUT_MPLANE,
		};

		parm.parm.output.timeperframe.numerator = 1;
		parm.parm.output.timeperframe.denominator = opt.fps;
		xioctl(vfd, VIDIOC_S_PARM, &parm, "S_PARM");
	}

	/* Sequence and picture parameters. */
	sps.profile_idc = opt.profile;
	if (opt.profile == 66)
		sps.constraint_set_flags = 0x40 | 0x80; /* constrained baseline */
	sps.level_idc = opt.level;
	sps.chroma_format_idc = 1;
	sps.max_num_ref_frames = opt.gop > 1 ? 1 : 0;
	sps.log2_max_frame_num_minus4 = 12;
	sps.pic_order_cnt_type = 2;
	sps.flags = V4L2_H264_SPS_FLAG_FRAME_MBS_ONLY |
		    V4L2_H264_SPS_FLAG_DIRECT_8X8_INFERENCE;
	if (set_compound(vfd, -1, V4L2_CID_STATELESS_H264_SPS, &sps, sizeof(sps)))
		return 1;

	pps.pic_init_qp_minus26 = 0;
	pps.flags = V4L2_H264_PPS_FLAG_DEBLOCKING_FILTER_CONTROL_PRESENT;
	if (opt.cabac)
		pps.flags |= V4L2_H264_PPS_FLAG_ENTROPY_CODING_MODE;
	if (opt.t8x8)
		pps.flags |= V4L2_H264_PPS_FLAG_TRANSFORM_8X8_MODE;
	if (set_compound(vfd, -1, V4L2_CID_STATELESS_H264_PPS, &pps, sizeof(pps)))
		return 1;

	set_ctrl(vfd, -1, V4L2_CID_MPEG_VIDEO_AU_DELIMITER, opt.aud);
	set_ctrl(vfd, -1, V4L2_CID_MPEG_VIDEO_PREPEND_SPSPPS_TO_IDR, 1);
	set_ctrl(vfd, -1, V4L2_CID_MPEG_VIDEO_H264_MIN_QP, opt.qp_min);
	set_ctrl(vfd, -1, V4L2_CID_MPEG_VIDEO_H264_MAX_QP, opt.qp_max);
	set_ctrl(vfd, -1, V4L2_CID_MPEG_VIDEO_H264_I_FRAME_QP, opt.qp_i);
	set_ctrl(vfd, -1, V4L2_CID_MPEG_VIDEO_H264_P_FRAME_QP, opt.qp_p);
	set_ctrl(vfd, -1, V4L2_CID_MPEG_VIDEO_FRAME_RC_ENABLE, opt.rc != 0);
	if (opt.rc == 1) {
		set_ctrl(vfd, -1, V4L2_CID_MPEG_VIDEO_BITRATE_MODE,
			 V4L2_MPEG_VIDEO_BITRATE_MODE_CBR);
		set_ctrl(vfd, -1, V4L2_CID_MPEG_VIDEO_BITRATE, opt.bitrate);
	} else if (opt.rc == 2) {
		set_ctrl(vfd, -1, V4L2_CID_MPEG_VIDEO_BITRATE_MODE,
			 V4L2_MPEG_VIDEO_BITRATE_MODE_CQ);
		set_ctrl(vfd, -1, V4L2_CID_MPEG_VIDEO_CONSTANT_QUALITY,
			 opt.quality);
	}

	/* Buffers. */
	for (type = 0; type < 2; type++) {
		struct buf *bufs = type ? cap : out;
		unsigned int np = type || opt.yuyv ? 1 : 2;

		memset(&rb, 0, sizeof(rb));
		rb.count = opt.depth;
		rb.type = type ? V4L2_BUF_TYPE_VIDEO_CAPTURE_MPLANE :
				 V4L2_BUF_TYPE_VIDEO_OUTPUT_MPLANE;
		rb.memory = V4L2_MEMORY_MMAP;
		if (xioctl(vfd, VIDIOC_REQBUFS, &rb, "REQBUFS"))
			return 1;
		if (rb.count < opt.depth)
			opt.depth = rb.count;

		for (i = 0; i < opt.depth; i++) {
			struct v4l2_plane planes[2] = { 0 };
			struct v4l2_buffer b = {
				.type = rb.type, .memory = V4L2_MEMORY_MMAP,
				.index = i, .length = np, .m.planes = planes,
			};
			unsigned int p;

			if (xioctl(vfd, VIDIOC_QUERYBUF, &b, "QUERYBUF"))
				return 1;
			for (p = 0; p < np; p++) {
				bufs[i].len[p] = planes[p].length;
				bufs[i].addr[p] = mmap(NULL, planes[p].length,
						       PROT_READ | PROT_WRITE,
						       MAP_SHARED, vfd,
						       planes[p].m.mem_offset);
				if (bufs[i].addr[p] == MAP_FAILED) {
					perror("mmap");
					return 1;
				}
			}
			if (!type && xioctl(mfd, MEDIA_IOC_REQUEST_ALLOC,
					    &bufs[i].req_fd, "REQUEST_ALLOC"))
				return 1;
		}
	}

	type = V4L2_BUF_TYPE_VIDEO_OUTPUT_MPLANE;
	if (xioctl(vfd, VIDIOC_STREAMON, &type, "STREAMON out"))
		return 1;
	type = V4L2_BUF_TYPE_VIDEO_CAPTURE_MPLANE;
	if (xioctl(vfd, VIDIOC_STREAMON, &type, "STREAMON cap"))
		return 1;

	t0 = now();
	while (done < opt.frames) {
		/* Queue as many frames as there are free buffer pairs. */
		while (next < opt.frames && queued - done < opt.depth) {
			unsigned int bi = next % opt.depth;
			struct buf *ob = &out[bi];
			struct v4l2_ctrl_h264_encode_params ep = { 0 };
			struct v4l2_plane planes[2] = { 0 };
			struct v4l2_buffer b = { 0 };
			unsigned int pos = next % opt.gop, y;
			unsigned int bpl0 = fmt_out.fmt.pix_mp.plane_fmt[0].bytesperline;
			unsigned int bpl1 = fmt_out.fmt.pix_mp.plane_fmt[1].bytesperline;
			unsigned char *dst;

			if (fread(frame, 1, frame_size, fin) != frame_size) {
				if (in_frames != ~0U) {
					fprintf(stderr, "short read\n");
					return 1;
				}
				opt.frames = next; /* end of a stream */
				break;
			}
			/* Copy, and pad the bottom rows with the last row. */
			dst = ob->addr[0];
			if (opt.yuyv) {
				for (y = 0; y < ah; y++)
					memcpy(dst + y * bpl0,
					       frame + (y < opt.height ? y : opt.height - 1) * opt.width * 2,
					       opt.width * 2);
				goto copied;
			}
			for (y = 0; y < ah; y++)
				memcpy(dst + y * bpl0,
				       frame + (y < opt.height ? y : opt.height - 1) * opt.width,
				       opt.width);
			dst = ob->addr[1];
			for (y = 0; y < ah / 2; y++)
				memcpy(dst + y * bpl1,
				       frame + opt.width * opt.height +
				       (y < opt.height / 2 ? y : opt.height / 2 - 1) * opt.width,
				       opt.width);
copied:
			if (!pos) {
				ep.flags |= V4L2_H264_ENCODE_FLAG_IDR_PIC;
				ep.slice_type = V4L2_H264_SLICE_TYPE_I;
				ep.nal_ref_idc = 3;
				ep.idr_pic_id = idr_id++ & 0xf;
			} else {
				ep.slice_type = V4L2_H264_SLICE_TYPE_P;
				ep.nal_ref_idc = 2;
			}
			ep.frame_num = pos;
			ep.pic_order_cnt_lsb = 2 * pos;
			ep.disable_deblocking_filter_idc = opt.deblock_off;

			if (set_compound(vfd, ob->req_fd,
					 V4L2_CID_STATELESS_H264_ENCODE_PARAMS,
					 &ep, sizeof(ep)))
				return 1;

			b.type = V4L2_BUF_TYPE_VIDEO_OUTPUT_MPLANE;
			b.memory = V4L2_MEMORY_MMAP;
			b.index = bi;
			b.length = opt.yuyv ? 1 : 2;
			b.m.planes = planes;
			planes[0].bytesused = bpl0 * ah;
			planes[1].bytesused = bpl1 * ah / 2;
			b.flags = V4L2_BUF_FLAG_REQUEST_FD;
			b.request_fd = ob->req_fd;
			b.timestamp.tv_sec = next / 1000000;
			b.timestamp.tv_usec = next % 1000000;
			if (xioctl(vfd, VIDIOC_QBUF, &b, "QBUF out"))
				return 1;

			memset(&b, 0, sizeof(b));
			memset(planes, 0, sizeof(planes));
			b.type = V4L2_BUF_TYPE_VIDEO_CAPTURE_MPLANE;
			b.memory = V4L2_MEMORY_MMAP;
			b.index = bi;
			b.length = 1;
			b.m.planes = planes;
			if (xioctl(vfd, VIDIOC_QBUF, &b, "QBUF cap"))
				return 1;

			if (xioctl(ob->req_fd, MEDIA_REQUEST_IOC_QUEUE, NULL,
				   "REQUEST_QUEUE"))
				return 1;
			ob->frame = next;
			next++;
			queued++;
		}

		if (done >= opt.frames)
			break;

		/* Wait for the oldest frame. */
		{
			unsigned int bi = done % opt.depth;
			struct buf *ob = &out[bi];
			struct v4l2_plane planes[2] = { 0 };
			struct v4l2_buffer b = { 0 };
			struct pollfd pfd = { .fd = ob->req_fd, .events = POLLPRI };
			struct v4l2_ctrl_h264_encode_params ep = { 0 };
			int ret;

			ret = poll(&pfd, 1, 5000);
			if (ret <= 0) {
				fprintf(stderr, "frame %u: request timeout\n", done);
				return 1;
			}

			b.type = V4L2_BUF_TYPE_VIDEO_CAPTURE_MPLANE;
			b.memory = V4L2_MEMORY_MMAP;
			b.length = 1;
			b.m.planes = planes;
			pfd.fd = vfd;
			pfd.events = POLLIN;
			while (ioctl(vfd, VIDIOC_DQBUF, &b)) {
				if (errno != EAGAIN) {
					perror("DQBUF cap");
					return 1;
				}
				if (poll(&pfd, 1, 5000) <= 0) {
					fprintf(stderr, "frame %u: capture timeout\n", done);
					return 1;
				}
			}
			if (b.flags & V4L2_BUF_FLAG_ERROR || !planes[0].bytesused) {
				fprintf(stderr, "frame %u: encode error (flags %#x)\n",
					done, b.flags);
				return 2;
			}
			fwrite(cap[b.index].addr[0], 1, planes[0].bytesused, fout);
			total += planes[0].bytesused;
			if (b.flags & V4L2_BUF_FLAG_KEYFRAME) {
				total_i += planes[0].bytesused;
				n_i++;
			}

			/* Feedback: the encode parameters actually used. */
			if (!get_compound(vfd, ob->req_fd,
					  V4L2_CID_STATELESS_H264_ENCODE_PARAMS,
					  &ep, sizeof(ep))) {
				int qp = 26 + pps.pic_init_qp_minus26 +
					 ep.slice_qp_delta;

				if (qp < (int)qp_hist_min)
					qp_hist_min = qp;
				if (qp > (int)qp_hist_max)
					qp_hist_max = qp;
				if (opt.verbose)
					printf("frame %4u %c %7u bytes qp %2d frame_num %u ref_idc %u\n",
					       done,
					       b.flags & V4L2_BUF_FLAG_KEYFRAME ? 'I' : 'P',
					       planes[0].bytesused, qp, ep.frame_num,
					       ep.nal_ref_idc);
			}

			memset(&b, 0, sizeof(b));
			memset(planes, 0, sizeof(planes));
			b.type = V4L2_BUF_TYPE_VIDEO_OUTPUT_MPLANE;
			b.memory = V4L2_MEMORY_MMAP;
			b.length = opt.yuyv ? 1 : 2;
			b.m.planes = planes;
			while (ioctl(vfd, VIDIOC_DQBUF, &b)) {
				if (errno != EAGAIN) {
					perror("DQBUF out");
					return 1;
				}
				usleep(100);
			}
			if (xioctl(ob->req_fd, MEDIA_REQUEST_IOC_REINIT, NULL,
				   "REQUEST_REINIT"))
				return 1;
			done++;
		}
	}
	t1 = now();

	printf("%s: %u frames %ux%u in %.3f s: %.1f fps, %llu bytes, %.0f kbit/s at %u fps, I avg %llu bytes, qp %u-%u\n",
	       opt.out, done, opt.width, opt.height, t1 - t0, done / (t1 - t0),
	       total, total * 8.0 * opt.fps / done / 1000, opt.fps,
	       n_i ? total_i / n_i : 0, qp_hist_min, qp_hist_max);

	{
		struct v4l2_ctrl_h264_sps s2 = { 0 };

		if (!get_compound(vfd, -1, V4L2_CID_STATELESS_H264_SPS, &s2,
				  sizeof(s2)) && opt.verbose)
			printf("final SPS: profile %u level %u poc_type %u log2_max_frame_num %u refs %u\n",
			       s2.profile_idc, s2.level_idc, s2.pic_order_cnt_type,
			       s2.log2_max_frame_num_minus4 + 4,
			       s2.max_num_ref_frames);
	}

	type = V4L2_BUF_TYPE_VIDEO_OUTPUT_MPLANE;
	xioctl(vfd, VIDIOC_STREAMOFF, &type, "STREAMOFF out");
	type = V4L2_BUF_TYPE_VIDEO_CAPTURE_MPLANE;
	xioctl(vfd, VIDIOC_STREAMOFF, &type, "STREAMOFF cap");

	fclose(fout);
	fclose(fin);
	return 0;
}
