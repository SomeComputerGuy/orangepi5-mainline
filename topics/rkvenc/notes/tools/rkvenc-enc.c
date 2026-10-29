// SPDX-License-Identifier: GPL-2.0
/*
 * rkvenc-enc: minimal V4L2 stateless H.264 encoder client
 *
 * Drives the rockchip-venc (VEPU580) driver through the request API using
 * the H.264 stateless encode uAPI proposed by Paul Kocialkowski
 * (V4L2_CID_STATELESS_H264_ENCODE_PARAMS). Reads raw NV12 frames, writes an
 * Annex-B H.264 elementary stream.
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
#include <time.h>
#include <unistd.h>

#include <linux/media.h>
#include <linux/videodev2.h>
#include <linux/v4l2-controls.h>

#define MAX_BUFS	8
#define MAX_PLANES	3

struct buf {
	void *map[MAX_PLANES];
	size_t len[MAX_PLANES];
	bool queued;
	int req_fd;
	unsigned int frame;
};

struct opts {
	const char *in, *out, *dev, *mdev;
	unsigned int width, height, frames, gop, fps;
	unsigned int qp_i, qp_p, qp_min, qp_max;
	unsigned int bitrate, profile, level, inflight;
	bool cabac, cbr, verbose;
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
		"  -p PROF     66, 77 or 100 (default 100)\n"
		"  -l LEVEL    level_idc (default 51)\n"
		"  -c          CAVLC instead of CABAC\n"
		"  -j N        frames in flight (default 2)\n"
		"  -d DEV      video device (default: find rockchip-venc)\n"
		"  -v          per-frame statistics\n", prog);
	exit(1);
}

int main(int argc, char **argv)
{
	struct opts o = {
		.gop = 30, .fps = 30, .qp_i = 26, .qp_p = 26, .qp_min = 10,
		.qp_max = 51, .profile = 100, .level = 51, .cabac = true,
		.inflight = 2, .cq = -1,
	};
	char vpath[64], mpath[64];
	struct v4l2_format ofmt = { 0 }, cfmt = { 0 };
	struct v4l2_requestbuffers rb;
	struct v4l2_streamparm parm = { 0 };
	struct v4l2_ctrl_h264_sps sps = { 0 };
	struct v4l2_ctrl_h264_pps pps = { 0 };
	struct buf obufs[MAX_BUFS] = { 0 }, cbufs[MAX_BUFS] = { 0 };
	unsigned int nobufs, ncbufs, i, p;
	unsigned int submitted = 0, done = 0, idr_frame = 0, frame_num = 0;
	unsigned long long total_bytes = 0;
	size_t frame_size;
	uint8_t *frame;
	FILE *in, *out;
	int vfd, mfd, opt;
	double t0, t1;
	long fsize;

	while ((opt = getopt(argc, argv, "i:o:w:h:n:g:q:b:Q:f:p:l:cj:d:v")) != -1) {
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
		default: usage(argv[0]);
		}
	}

	if (!o.in || !o.out || !o.width || !o.height || !o.gop)
		usage(argv[0]);
	if (o.inflight < 1 || o.inflight > MAX_BUFS - 1)
		o.inflight = 2;
	if (o.profile == 66)
		o.cabac = false;

	frame_size = (size_t)o.width * o.height * 3 / 2;
	in = fopen(o.in, "rb");
	out = fopen(o.out, "wb");
	if (!in || !out) {
		perror("fopen");
		return 1;
	}
	fseek(in, 0, SEEK_END);
	fsize = ftell(in);
	fseek(in, 0, SEEK_SET);
	if (!o.frames || o.frames > fsize / frame_size)
		o.frames = fsize / frame_size;
	frame = malloc(frame_size);

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
	cfmt.fmt.pix_mp.pixelformat = V4L2_PIX_FMT_H264_SLICE;
	cfmt.fmt.pix_mp.width = o.width;
	cfmt.fmt.pix_mp.height = o.height;
	cfmt.fmt.pix_mp.num_planes = 1;
	CHECK(xioctl(vfd, VIDIOC_S_FMT, &cfmt));

	ofmt.type = V4L2_BUF_TYPE_VIDEO_OUTPUT_MPLANE;
	ofmt.fmt.pix_mp.pixelformat = V4L2_PIX_FMT_NV12;
	ofmt.fmt.pix_mp.width = o.width;
	ofmt.fmt.pix_mp.height = o.height;
	CHECK(xioctl(vfd, VIDIOC_S_FMT, &ofmt));
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
	rb.memory = V4L2_MEMORY_MMAP;
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

	t0 = now();
	while (done < o.frames) {
		/* Submit as many frames as allowed. */
		while (submitted < o.frames && submitted - done < o.inflight) {
			struct v4l2_ctrl_h264_encode_params ep = { 0 };
			struct v4l2_plane planes[MAX_PLANES] = { 0 };
			struct v4l2_buffer vb = { 0 };
			unsigned int bpl = ofmt.fmt.pix_mp.plane_fmt[0].bytesperline;
			unsigned int oi = submitted % nobufs;
			unsigned int ci = submitted % ncbufs;
			struct buf *ob = &obufs[oi];
			uint8_t *dst = ob->map[0];
			bool idr = !(submitted % o.gop);
			unsigned int y;

			if (fread(frame, 1, frame_size, in) != frame_size)
				break;
			for (y = 0; y < o.height; y++)
				memcpy(dst + y * bpl, frame + y * o.width, o.width);
			for (y = 0; y < o.height / 2; y++)
				memcpy(dst + bpl * o.height + y * bpl,
				       frame + o.width * o.height + y * o.width,
				       o.width);

			if (idr) {
				idr_frame = submitted;
				frame_num = 0;
			}
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

			vb.type = V4L2_BUF_TYPE_VIDEO_OUTPUT_MPLANE;
			vb.memory = V4L2_MEMORY_MMAP;
			vb.index = oi;
			vb.m.planes = planes;
			vb.length = ofmt.fmt.pix_mp.num_planes;
			planes[0].bytesused = ofmt.fmt.pix_mp.plane_fmt[0].sizeimage;
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
			total_bytes += planes[0].bytesused;

			qp = get_req_ctrl(vfd, V4L2_CID_MPEG_VIDEO_AVERAGE_QP,
					  ob->req_fd);
			if (o.verbose)
				fprintf(stderr, "frame %u: %c %u bytes avg qp %d\n",
					done,
					vb.flags & V4L2_BUF_FLAG_KEYFRAME ? 'I' : 'P',
					planes[0].bytesused, qp);

			memset(&vb, 0, sizeof(vb));
			memset(planes, 0, sizeof(planes));
			vb.type = V4L2_BUF_TYPE_VIDEO_OUTPUT_MPLANE;
			vb.memory = V4L2_MEMORY_MMAP;
			vb.m.planes = planes;
			vb.length = MAX_PLANES;
			CHECK(xioctl(vfd, VIDIOC_DQBUF, &vb));

			CHECK(xioctl(ob->req_fd, MEDIA_REQUEST_IOC_REINIT, NULL));
			done++;
		}
	}
	t1 = now();

	fprintf(stderr,
		"encoded %u frames in %.3f s: %.2f fps, %llu bytes, %.1f kbit/s at %u fps\n",
		done, t1 - t0, done / (t1 - t0), total_bytes,
		done ? total_bytes * 8.0 * o.fps / done / 1000 : 0, o.fps);

	fclose(out);
	fclose(in);
	close(mfd);
	close(vfd);
	return 0;
}
