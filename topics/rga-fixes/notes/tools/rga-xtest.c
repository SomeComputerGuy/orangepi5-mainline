// SPDX-License-Identifier: GPL-2.0-only
/*
 * V4L2 m2m test client for the Rockchip RGA (rga-fu package, from rga3-nv15).
 *
 * Converts frames of a raw file and writes the results. Input and output
 * files are "tight": rows without padding, planes one after the other, so the
 * judge doesn't depend on the driver's strides. The tool repacks them into the
 * driver's bytesperline layout.
 *
 * rga-xtest -d /dev/videoN -i in.raw -s WxH:FOURCC -t WxH:FOURCC -o out.raw
 *           [-n frames] [-r 0|90|180|270] [-H] [-V] [-e 601|709|2020]
 *           [-q lim|full] [-D extra_bytes -h /dev/dma_heap/NAME]
 *           [-c L,T,W,H] [-C L,T,W,H] [-b BPL0[,BPL1]] [-B BPL0[,BPL1]]
 *
 * -D: use imported DMA-BUFs (from the dma-heap -h) on both queues, each
 *     <extra_bytes> larger than the plane (rounded up to pages).
 * -c / -C: S_SELECTION crop on OUTPUT / compose on CAPTURE; the rectangle the
 *     driver kept is printed as "CROP l t w h" / "COMPOSE l t w h".
 * -b / -B: bytesperline asked for in S_FMT on OUTPUT / CAPTURE (per plane);
 *     the values the driver kept are in the "OUT ..." / "CAP ..." line.
 * The OUTPUT buffer is filled with 0xa5 before each frame (so a wrong stride
 * reads garbage), the CAPTURE buffer with 0x5a (outside a compose rectangle
 * it must stay 0x5a). The output file is the whole tight CAPTURE frame.
 * Exit: 0 all frames done, 1 setup error, 2 a job didn't come back in 10 s,
 *       3 QBUF refused, 4 a control was refused, 5 STREAMON refused,
 *       6 S_SELECTION refused.
 */
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>
#include <linux/dma-buf.h>
#include <linux/dma-heap.h>
#include <linux/videodev2.h>

#ifndef V4L2_PIX_FMT_NV15
#define V4L2_PIX_FMT_NV15 v4l2_fourcc('N', 'V', '1', '5')
#endif
#ifndef V4L2_PIX_FMT_NV20
#define V4L2_PIX_FMT_NV20 v4l2_fourcc('N', 'V', '2', '0')
#endif

static int fd;

static void die(const char *what)
{
	fprintf(stderr, "%s: %s\n", what, strerror(errno));
	exit(1);
}

static int xioctl(int f, unsigned long req, void *arg)
{
	int r;

	do {
		r = ioctl(f, req, arg);
	} while (r < 0 && errno == EINTR);
	return r;
}

static double now(void)
{
	struct timespec ts;

	clock_gettime(CLOCK_MONOTONIC, &ts);
	return ts.tv_sec + ts.tv_nsec / 1e9;
}

static void parse_fmt(const char *s, int *w, int *h, uint32_t *fcc)
{
	char f[5] = "    ";

	if (sscanf(s, "%dx%d:%4s", w, h, f) != 3) {
		fprintf(stderr, "bad format %s\n", s);
		exit(1);
	}
	*fcc = v4l2_fourcc(f[0], f[1], f[2], f[3]);
}

/* Tight layout: number of component planes, rows and bytes per row of each */
struct layout {
	int ncomp;
	int rows[2];
	int rowbytes[2];
};

static void get_layout(uint32_t fcc, int w, int h, struct layout *l)
{
	memset(l, 0, sizeof(*l));
	switch (fcc) {
	case V4L2_PIX_FMT_NV12: case V4L2_PIX_FMT_NV21:
	case V4L2_PIX_FMT_NV12M: case V4L2_PIX_FMT_NV21M:
		*l = (struct layout){ 2, { h, h / 2 }, { w, w } };
		break;
	case V4L2_PIX_FMT_NV16: case V4L2_PIX_FMT_NV61:
	case V4L2_PIX_FMT_NV16M: case V4L2_PIX_FMT_NV61M:
		*l = (struct layout){ 2, { h, h }, { w, w } };
		break;
	case V4L2_PIX_FMT_NV15:
		*l = (struct layout){ 2, { h, h / 2 }, { w * 5 / 4, w * 5 / 4 } };
		break;
	case V4L2_PIX_FMT_NV20:
		*l = (struct layout){ 2, { h, h }, { w * 5 / 4, w * 5 / 4 } };
		break;
	case V4L2_PIX_FMT_P010:
		*l = (struct layout){ 2, { h, h / 2 }, { w * 2, w * 2 } };
		break;
	case V4L2_PIX_FMT_RGB24: case V4L2_PIX_FMT_BGR24:
		*l = (struct layout){ 1, { h }, { w * 3 } };
		break;
	case V4L2_PIX_FMT_YUYV: case V4L2_PIX_FMT_UYVY:
	case V4L2_PIX_FMT_YVYU: case V4L2_PIX_FMT_VYUY:
	case V4L2_PIX_FMT_RGB565:
		*l = (struct layout){ 1, { h }, { w * 2 } };
		break;
	default: /* 32-bit RGB */
		*l = (struct layout){ 1, { h }, { w * 4 } };
		break;
	}
}

static size_t tight_size(const struct layout *l)
{
	size_t s = 0;
	int i;

	for (i = 0; i < l->ncomp; i++)
		s += (size_t)l->rows[i] * l->rowbytes[i];
	return s;
}

struct qbufs {
	enum v4l2_buf_type type;
	int memory;
	int nplanes;
	uint32_t bpl[2], sizeimage[2];
	void *addr[2];
	size_t len[2];
	int dmafd[2];
	struct layout l;
};

static int heap_alloc(const char *heap, size_t len)
{
	struct dma_heap_allocation_data a = {
		.len = len, .fd_flags = O_RDWR | O_CLOEXEC,
	};
	int h = open(heap, O_RDWR);

	if (h < 0)
		die(heap);
	if (xioctl(h, DMA_HEAP_IOCTL_ALLOC, &a))
		die("DMA_HEAP_IOCTL_ALLOC");
	close(h);
	return a.fd;
}

static void sync_buf(struct qbufs *q, int start, int write)
{
	struct dma_buf_sync s;
	int i;

	if (q->memory != V4L2_MEMORY_DMABUF)
		return;
	for (i = 0; i < q->nplanes; i++) {
		s.flags = (start ? DMA_BUF_SYNC_START : DMA_BUF_SYNC_END) |
			  (write ? DMA_BUF_SYNC_WRITE : DMA_BUF_SYNC_READ);
		if (xioctl(q->dmafd[i], DMA_BUF_IOCTL_SYNC, &s))
			die("DMA_BUF_IOCTL_SYNC");
	}
}

static void setup(struct qbufs *q, enum v4l2_buf_type type, int w, int h,
		  uint32_t fcc, int enc, int quant, long extra,
		  const char *heap, const uint32_t *want_bpl)
{
	struct v4l2_format f = { .type = type };
	struct v4l2_requestbuffers rb = { .count = 1, .type = type };
	struct v4l2_plane pl[2];
	struct v4l2_buffer qb = { .type = type, .index = 0,
				  .m.planes = pl, .length = 2 };
	int i;

	memset(q, 0, sizeof(*q));
	q->type = type;
	q->memory = extra >= 0 ? V4L2_MEMORY_DMABUF : V4L2_MEMORY_MMAP;
	f.fmt.pix_mp.width = w;
	f.fmt.pix_mp.height = h;
	f.fmt.pix_mp.pixelformat = fcc;
	if (want_bpl[0]) {
		f.fmt.pix_mp.num_planes = want_bpl[1] ? 2 : 1;
		f.fmt.pix_mp.plane_fmt[0].bytesperline = want_bpl[0];
		f.fmt.pix_mp.plane_fmt[1].bytesperline = want_bpl[1];
	}
	if (enc) {
		/*
		 * The V4L2 core resets ycbcr_enc and quantization to DEFAULT
		 * when the colorspace is DEFAULT, so name a matching one.
		 */
		f.fmt.pix_mp.colorspace =
			enc == V4L2_YCBCR_ENC_709 ? V4L2_COLORSPACE_REC709 :
			enc == V4L2_YCBCR_ENC_BT2020 ? V4L2_COLORSPACE_BT2020 :
			V4L2_COLORSPACE_SMPTE170M;
		f.fmt.pix_mp.ycbcr_enc = enc;
		f.fmt.pix_mp.quantization = quant;
		if (V4L2_TYPE_IS_CAPTURE(type))
			f.fmt.pix_mp.flags = V4L2_PIX_FMT_FLAG_SET_CSC;
	}
	if (xioctl(fd, VIDIOC_S_FMT, &f))
		die("S_FMT");
	if (f.fmt.pix_mp.pixelformat != fcc || f.fmt.pix_mp.width != (unsigned)w ||
	    f.fmt.pix_mp.height != (unsigned)h) {
		fprintf(stderr, "format not taken: %ux%u %.4s\n",
			f.fmt.pix_mp.width, f.fmt.pix_mp.height,
			(char *)&f.fmt.pix_mp.pixelformat);
		exit(1);
	}
	if (enc && (f.fmt.pix_mp.ycbcr_enc != (unsigned)enc ||
		    f.fmt.pix_mp.quantization != (unsigned)quant)) {
		fprintf(stderr, "colorimetry not taken: enc %u quant %u\n",
			f.fmt.pix_mp.ycbcr_enc, f.fmt.pix_mp.quantization);
		exit(1);
	}
	q->nplanes = f.fmt.pix_mp.num_planes;
	for (i = 0; i < q->nplanes; i++) {
		q->bpl[i] = f.fmt.pix_mp.plane_fmt[i].bytesperline;
		q->sizeimage[i] = f.fmt.pix_mp.plane_fmt[i].sizeimage;
	}
	get_layout(fcc, w, h, &q->l);
	printf("%s %dx%d %.4s planes %d bpl %u %u size %u %u enc %u quant %u mem %s\n",
	       V4L2_TYPE_IS_OUTPUT(type) ? "OUT" : "CAP", w, h, (char *)&fcc,
	       q->nplanes, q->bpl[0], q->bpl[1], q->sizeimage[0], q->sizeimage[1],
	       f.fmt.pix_mp.ycbcr_enc, f.fmt.pix_mp.quantization,
	       q->memory == V4L2_MEMORY_DMABUF ? "dmabuf" : "mmap");
	rb.memory = q->memory;
	if (xioctl(fd, VIDIOC_REQBUFS, &rb) || rb.count < 1)
		die("REQBUFS");
	if (q->memory == V4L2_MEMORY_DMABUF) {
		for (i = 0; i < q->nplanes; i++) {
			size_t len = (q->sizeimage[i] + extra + 4095) & ~4095UL;

			q->dmafd[i] = heap_alloc(heap, len);
			q->len[i] = len;
			q->addr[i] = mmap(NULL, len, PROT_READ | PROT_WRITE,
					  MAP_SHARED, q->dmafd[i], 0);
			if (q->addr[i] == MAP_FAILED)
				die("mmap dmabuf");
			printf("%s plane %d dmabuf %zu bytes (plane %u)\n",
			       V4L2_TYPE_IS_OUTPUT(type) ? "OUT" : "CAP", i,
			       len, q->sizeimage[i]);
		}
		return;
	}
	qb.memory = V4L2_MEMORY_MMAP;
	qb.length = q->nplanes;
	if (xioctl(fd, VIDIOC_QUERYBUF, &qb))
		die("QUERYBUF");
	for (i = 0; i < q->nplanes; i++) {
		q->len[i] = pl[i].length;
		q->addr[i] = mmap(NULL, pl[i].length, PROT_READ | PROT_WRITE,
				  MAP_SHARED, fd, pl[i].m.mem_offset);
		if (q->addr[i] == MAP_FAILED)
			die("mmap");
	}
}

/* Copy between a tight frame and the buffer, to_buf selects the direction */
static void repack(struct qbufs *q, uint8_t *tight, int to_buf)
{
	int c, r;

	for (c = 0; c < q->l.ncomp; c++) {
		uint8_t *base;
		uint32_t bpl;

		if (q->nplanes > 1) {
			base = q->addr[c];
			bpl = q->bpl[c];
		} else {
			base = (uint8_t *)q->addr[0] +
			       (c ? (size_t)q->bpl[0] * q->l.rows[0] : 0);
			bpl = q->bpl[0];
		}
		for (r = 0; r < q->l.rows[c]; r++) {
			if (to_buf)
				memcpy(base + (size_t)r * bpl, tight, q->l.rowbytes[c]);
			else
				memcpy(tight, base + (size_t)r * bpl, q->l.rowbytes[c]);
			tight += q->l.rowbytes[c];
		}
	}
}

static int qbuf(struct qbufs *q, uint64_t ts)
{
	struct v4l2_plane pl[2];
	struct v4l2_buffer b = { .type = q->type, .index = 0,
				 .memory = q->memory, .m.planes = pl,
				 .length = q->nplanes };
	int i;

	memset(pl, 0, sizeof(pl));
	for (i = 0; i < q->nplanes; i++) {
		if (V4L2_TYPE_IS_OUTPUT(q->type))
			pl[i].bytesused = q->sizeimage[i];
		if (q->memory == V4L2_MEMORY_DMABUF) {
			pl[i].m.fd = q->dmafd[i];
			pl[i].length = q->len[i];
		}
	}
	b.timestamp.tv_sec = ts;
	if (xioctl(fd, VIDIOC_QBUF, &b)) {
		printf("QBUF %s refused: %s\n",
		       V4L2_TYPE_IS_OUTPUT(q->type) ? "OUT" : "CAP", strerror(errno));
		return -1;
	}
	return 0;
}

static int dqbuf(struct qbufs *q, uint32_t *flags)
{
	struct v4l2_plane pl[2];
	struct v4l2_buffer b = { .type = q->type, .memory = q->memory,
				 .m.planes = pl, .length = q->nplanes };

	if (xioctl(fd, VIDIOC_DQBUF, &b))
		return -1;
	*flags = b.flags;
	return 0;
}

static int parse_rect(const char *s, struct v4l2_rect *r)
{
	if (sscanf(s, "%d,%d,%u,%u", &r->left, &r->top, &r->width, &r->height) != 4) {
		fprintf(stderr, "bad rectangle %s\n", s);
		exit(1);
	}
	return 1;
}

static void parse_bpl(const char *s, uint32_t *b)
{
	b[1] = 0;
	if (sscanf(s, "%u,%u", &b[0], &b[1]) < 1) {
		fprintf(stderr, "bad bytesperline %s\n", s);
		exit(1);
	}
}

static int set_sel(enum v4l2_buf_type type, uint32_t target, struct v4l2_rect *r,
		   const char *name)
{
	struct v4l2_selection sel = { .type = type, .target = target, .r = *r };

	if (xioctl(fd, VIDIOC_S_SELECTION, &sel)) {
		printf("SEL %s %d,%d,%u,%u refused: %s\n", name, r->left, r->top,
		       r->width, r->height, strerror(errno));
		return -1;
	}
	memset(&sel.r, 0, sizeof(sel.r));
	if (xioctl(fd, VIDIOC_G_SELECTION, &sel))
		die("G_SELECTION");
	printf("%s %d %d %u %u\n", name, sel.r.left, sel.r.top, sel.r.width,
	       sel.r.height);
	return 0;
}

static int set_ctrl(uint32_t id, int val, const char *name)
{
	struct v4l2_control c = { .id = id, .value = val };

	if (xioctl(fd, VIDIOC_S_CTRL, &c)) {
		printf("CTRL %s=%d refused: %s\n", name, val, strerror(errno));
		return -1;
	}
	printf("CTRL %s=%d\n", name, val);
	return 0;
}

int main(int argc, char **argv)
{
	const char *dev = NULL, *in = NULL, *out = NULL, *heap = NULL;
	enum v4l2_buf_type ot = V4L2_BUF_TYPE_VIDEO_OUTPUT_MPLANE;
	enum v4l2_buf_type ct = V4L2_BUF_TYPE_VIDEO_CAPTURE_MPLANE;
	int sw = 0, sh = 0, dw = 0, dh = 0, n = 1, rot = -1, hf = 0, vf = 0;
	int enc = 0, quant = V4L2_QUANTIZATION_LIM_RANGE, opt, i, errors = 0;
	long extra = -1;
	uint32_t sf = 0, df = 0;
	struct qbufs ob, cb;
	FILE *fi, *fo;
	size_t isz, osz;
	uint8_t *iframe, *oframe;
	long nin;
	struct v4l2_rect crop, compose;
	int has_crop = 0, has_compose = 0;
	uint32_t obpl[2] = { 0, 0 }, cbpl[2] = { 0, 0 };

	while ((opt = getopt(argc, argv, "d:i:o:s:t:n:r:HVe:q:D:h:c:C:b:B:")) != -1) {
		switch (opt) {
		case 'd': dev = optarg; break;
		case 'i': in = optarg; break;
		case 'o': out = optarg; break;
		case 's': parse_fmt(optarg, &sw, &sh, &sf); break;
		case 't': parse_fmt(optarg, &dw, &dh, &df); break;
		case 'n': n = atoi(optarg); break;
		case 'r': rot = atoi(optarg); break;
		case 'H': hf = 1; break;
		case 'V': vf = 1; break;
		case 'e':
			enc = !strcmp(optarg, "709") ? V4L2_YCBCR_ENC_709 :
			      !strcmp(optarg, "2020") ? V4L2_YCBCR_ENC_BT2020 :
			      V4L2_YCBCR_ENC_601;
			break;
		case 'q':
			quant = !strcmp(optarg, "full") ? V4L2_QUANTIZATION_FULL_RANGE :
				V4L2_QUANTIZATION_LIM_RANGE;
			break;
		case 'D': extra = atol(optarg); break;
		case 'h': heap = optarg; break;
		case 'c': has_crop = parse_rect(optarg, &crop); break;
		case 'C': has_compose = parse_rect(optarg, &compose); break;
		case 'b': parse_bpl(optarg, obpl); break;
		case 'B': parse_bpl(optarg, cbpl); break;
		default:
			fprintf(stderr, "usage: see source\n");
			return 1;
		}
	}
	if (!dev || !in || !out || !sf || !df || (extra >= 0 && !heap)) {
		fprintf(stderr, "-d -i -o -s -t required (-h with -D)\n");
		return 1;
	}
	fd = open(dev, O_RDWR | O_NONBLOCK);
	if (fd < 0)
		die(dev);
	setup(&ob, ot, sw, sh, sf, enc, quant, extra, heap, obpl);
	setup(&cb, ct, dw, dh, df, 0, 0, extra, heap, cbpl);
	/* S_FMT resets the rectangles, so they come after the formats */
	if (has_crop && set_sel(ot, V4L2_SEL_TGT_CROP, &crop, "CROP"))
		return 6;
	if (has_compose && set_sel(ct, V4L2_SEL_TGT_COMPOSE, &compose, "COMPOSE"))
		return 6;
	/* the controls after the formats: the rotation check needs the input format */
	if (rot >= 0 && set_ctrl(V4L2_CID_ROTATE, rot, "rotate"))
		return 4;
	if (hf && set_ctrl(V4L2_CID_HFLIP, 1, "hflip"))
		return 4;
	if (vf && set_ctrl(V4L2_CID_VFLIP, 1, "vflip"))
		return 4;
	isz = tight_size(&ob.l);
	osz = tight_size(&cb.l);
	fi = fopen(in, "rb");
	if (!fi)
		die(in);
	fseek(fi, 0, SEEK_END);
	nin = ftell(fi) / isz;
	if (nin < 1) {
		fprintf(stderr, "input smaller than one %zu byte frame\n", isz);
		return 1;
	}
	fo = fopen(out, "wb");
	if (!fo)
		die(out);
	iframe = malloc(isz);
	oframe = malloc(osz);
	if (xioctl(fd, VIDIOC_STREAMON, &ot) || xioctl(fd, VIDIOC_STREAMON, &ct)) {
		printf("STREAMON refused: %s\n", strerror(errno));
		return 5;
	}
	printf("dev %s input frames %ld tight in %zu out %zu\n", dev, nin, isz, osz);
	for (i = 0; i < n; i++) {
		struct pollfd p = { .fd = fd, .events = POLLIN };
		uint32_t oflags = 0, cflags = 0;
		double t0, t1;
		int got = 0;

		fseek(fi, (long)(i % nin) * isz, SEEK_SET);
		if (fread(iframe, 1, isz, fi) != isz)
			die("fread");
		sync_buf(&ob, 1, 1);
		memset(ob.addr[0], 0xa5, ob.len[0]);
		if (ob.nplanes > 1)
			memset(ob.addr[1], 0xa5, ob.len[1]);
		repack(&ob, iframe, 1);
		sync_buf(&ob, 0, 1);
		sync_buf(&cb, 1, 1);
		memset(cb.addr[0], 0x5a, cb.len[0]);
		if (cb.nplanes > 1)
			memset(cb.addr[1], 0x5a, cb.len[1]);
		sync_buf(&cb, 0, 1);
		t0 = now();
		if (qbuf(&cb, 0) || qbuf(&ob, i + 1))
			return 3;
		while (got != 3) {
			if (poll(&p, 1, 10000) <= 0) {
				printf("frame %d HANG: no buffer after 10 s\n", i);
				fflush(stdout);
				return 2;
			}
			if (!(got & 1) && !dqbuf(&ob, &oflags))
				got |= 1;
			if (!(got & 2) && !dqbuf(&cb, &cflags))
				got |= 2;
		}
		t1 = now();
		if (cflags & V4L2_BUF_FLAG_ERROR)
			errors++;
		sync_buf(&cb, 1, 0);
		repack(&cb, oframe, 0);
		sync_buf(&cb, 0, 0);
		fwrite(oframe, 1, osz, fo);
		printf("frame %d %s src_err %d time_ms %.2f\n", i,
		       cflags & V4L2_BUF_FLAG_ERROR ? "ERROR" : "ok",
		       !!(oflags & V4L2_BUF_FLAG_ERROR), (t1 - t0) * 1000);
		fflush(stdout);
	}
	xioctl(fd, VIDIOC_STREAMOFF, &ot);
	xioctl(fd, VIDIOC_STREAMOFF, &ct);
	fclose(fo);
	printf("done frames %d errors %d\n", n, errors);
	return 0;
}
