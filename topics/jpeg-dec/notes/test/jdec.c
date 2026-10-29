// SPDX-License-Identifier: GPL-2.0-only
/*
 * jdec - minimal stateful V4L2 JPEG decoder client for testing rkjpegd.
 *
 * jdec -d /dev/videoN [-f NV12|NV16|NV24|GREY] [-o out.yuv] [-n loops]
 *      [-b capbufs] file...
 *
 * Each file is a JPEG or a concatenation of JPEGs (MJPEG). Frames are
 * decoded in order, -n repeats the whole list. Decoded frames are written
 * cropped to the visible size as planar I420/I422/I444/GRAY (chroma
 * deinterleaved), the layout ffmpeg's rawvideo output uses for
 * yuvj420p/yuvj422p/yuvj444p/gray.
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
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>
#include <linux/videodev2.h>

#define NOUT 4
#define MAXCAP 16

struct frame { const uint8_t *p; size_t len; };

static int fd;
static struct frame *frames;
static int nframes;
static void *outmap[NOUT];
static size_t outlen[NOUT];
static void *capmap[MAXCAP];
static size_t caplen[MAXCAP];
static int ncap = 4;
static struct v4l2_format capfmt;
static struct v4l2_rect vis;
static FILE *outf;
static uint32_t want_fourcc;
static int verbose = 1;

static void die(const char *m)
{
	fprintf(stderr, "jdec: %s: %s\n", m, strerror(errno));
	exit(2);
}

static void xioctl(unsigned long req, void *arg, const char *name)
{
	if (ioctl(fd, req, arg) < 0)
		die(name);
}

static double now(void)
{
	struct timespec ts;

	clock_gettime(CLOCK_MONOTONIC, &ts);
	return ts.tv_sec + ts.tv_nsec / 1e9;
}

/* split a buffer into JPEG frames on SOI ... EOI */
static void add_file(const char *path)
{
	struct stat st;
	uint8_t *buf;
	size_t i = 0, start;
	int f = open(path, O_RDONLY);

	if (f < 0 || fstat(f, &st))
		die(path);
	buf = malloc(st.st_size + 1);
	if (read(f, buf, st.st_size) != st.st_size)
		die("read");
	close(f);

	while (i + 1 < (size_t)st.st_size) {
		if (buf[i] != 0xff || buf[i + 1] != 0xd8) {
			i++;
			continue;
		}
		start = i;
		i += 2;
		while (i + 1 < (size_t)st.st_size &&
		       !(buf[i] == 0xff && buf[i + 1] == 0xd9))
			i++;
		i = i + 2 > (size_t)st.st_size ? st.st_size : i + 2;
		frames = realloc(frames, (nframes + 1) * sizeof(*frames));
		frames[nframes].p = buf + start;
		frames[nframes].len = i - start;
		nframes++;
	}
	/* a file without SOI (corrupt input test): send it as is */
	if (!nframes || frames[nframes - 1].p < buf) {
		frames = realloc(frames, (nframes + 1) * sizeof(*frames));
		frames[nframes].p = buf;
		frames[nframes].len = st.st_size;
		nframes++;
	}
}

static void setup_capture(void)
{
	struct v4l2_requestbuffers rb = { .type = V4L2_BUF_TYPE_VIDEO_CAPTURE_MPLANE,
					  .memory = V4L2_MEMORY_MMAP };
	struct v4l2_selection sel = { .type = V4L2_BUF_TYPE_VIDEO_CAPTURE,
				      .target = V4L2_SEL_TGT_COMPOSE };
	int type = V4L2_BUF_TYPE_VIDEO_CAPTURE_MPLANE;
	int i;

	capfmt.type = type;
	xioctl(VIDIOC_G_FMT, &capfmt, "G_FMT cap");
	if (want_fourcc && capfmt.fmt.pix_mp.pixelformat != want_fourcc) {
		capfmt.fmt.pix_mp.pixelformat = want_fourcc;
		xioctl(VIDIOC_S_FMT, &capfmt, "S_FMT cap");
	}
	xioctl(VIDIOC_G_SELECTION, &sel, "G_SELECTION");
	vis = sel.r;
	if (verbose)
		fprintf(stderr, "capture %.4s %ux%u bpl %u size %u visible %ux%u\n",
			(char *)&capfmt.fmt.pix_mp.pixelformat,
			capfmt.fmt.pix_mp.width, capfmt.fmt.pix_mp.height,
			capfmt.fmt.pix_mp.plane_fmt[0].bytesperline,
			capfmt.fmt.pix_mp.plane_fmt[0].sizeimage,
			vis.width, vis.height);

	rb.count = ncap;
	xioctl(VIDIOC_REQBUFS, &rb, "REQBUFS cap");
	ncap = rb.count;
	for (i = 0; i < ncap; i++) {
		struct v4l2_plane pl = {};
		struct v4l2_buffer b = { .type = type, .memory = V4L2_MEMORY_MMAP,
					 .index = i, .m.planes = &pl, .length = 1 };

		xioctl(VIDIOC_QUERYBUF, &b, "QUERYBUF cap");
		caplen[i] = pl.length;
		capmap[i] = mmap(NULL, pl.length, PROT_READ, MAP_SHARED, fd,
				 pl.m.mem_offset);
		if (capmap[i] == MAP_FAILED)
			die("mmap cap");
		xioctl(VIDIOC_QBUF, &b, "QBUF cap");
	}
	xioctl(VIDIOC_STREAMON, &type, "STREAMON cap");
}

static void teardown_capture(void)
{
	struct v4l2_requestbuffers rb = { .type = V4L2_BUF_TYPE_VIDEO_CAPTURE_MPLANE,
					  .memory = V4L2_MEMORY_MMAP };
	int type = V4L2_BUF_TYPE_VIDEO_CAPTURE_MPLANE;
	int i;

	xioctl(VIDIOC_STREAMOFF, &type, "STREAMOFF cap");
	for (i = 0; i < ncap; i++)
		munmap(capmap[i], caplen[i]);
	xioctl(VIDIOC_REQBUFS, &rb, "REQBUFS 0 cap");
}

static void write_frame(const uint8_t *p)
{
	struct v4l2_pix_format_mplane *f = &capfmt.fmt.pix_mp;
	unsigned int bpl = f->plane_fmt[0].bytesperline;
	unsigned int w = vis.width, h = vis.height, y, x;
	unsigned int cw, ch, cbpl;
	const uint8_t *c = p + bpl * f->height;
	uint8_t *row;

	for (y = 0; y < h; y++)
		fwrite(p + y * bpl, 1, w, outf);

	switch (f->pixelformat) {
	case V4L2_PIX_FMT_NV12:
		cw = (w + 1) / 2; ch = (h + 1) / 2; cbpl = bpl; break;
	case V4L2_PIX_FMT_NV16:
		cw = (w + 1) / 2; ch = h; cbpl = bpl; break;
	case V4L2_PIX_FMT_NV24:
		cw = w; ch = h; cbpl = 2 * bpl; break;
	default:
		return;
	}
	row = malloc(cw);
	for (x = 0; x < 2; x++) {
		for (y = 0; y < ch; y++) {
			unsigned int i;

			for (i = 0; i < cw; i++)
				row[i] = c[y * cbpl + 2 * i + x];
			fwrite(row, 1, cw, outf);
		}
	}
	free(row);
}

static int queue_out(int idx, int *next, int total)
{
	struct v4l2_plane pl = {};
	struct v4l2_buffer b = { .type = V4L2_BUF_TYPE_VIDEO_OUTPUT_MPLANE,
				 .memory = V4L2_MEMORY_MMAP, .index = idx,
				 .m.planes = &pl, .length = 1 };
	const struct frame *fr;

	if (*next >= total)
		return 0;
	fr = &frames[*next % nframes];
	if (fr->len > outlen[idx]) {
		fprintf(stderr, "frame %d too large (%zu)\n", *next, fr->len);
		exit(2);
	}
	memcpy(outmap[idx], fr->p, fr->len);
	pl.bytesused = fr->len;
	b.timestamp.tv_sec = *next;
	xioctl(VIDIOC_QBUF, &b, "QBUF out");
	(*next)++;
	return 1;
}

int main(int argc, char **argv)
{
	const char *dev = "/dev/video0", *out = NULL;
	struct v4l2_requestbuffers rb = { .type = V4L2_BUF_TYPE_VIDEO_OUTPUT_MPLANE,
					  .memory = V4L2_MEMORY_MMAP, .count = NOUT };
	struct v4l2_event_subscription sub = {};
	struct v4l2_format of = { .type = V4L2_BUF_TYPE_VIDEO_OUTPUT_MPLANE };
	int type, i, opt, loops = 1, next = 0, total, inflight = 0;
	int decoded = 0, errors = 0, outerr = 0, src_changes = 0, stopped = 0;
	int cap_on = 0, timeout_ms = 5000;
	size_t maxlen = 0;
	double t0, t1;

	while ((opt = getopt(argc, argv, "d:f:o:n:b:qt:")) != -1) {
		switch (opt) {
		case 'd': dev = optarg; break;
		case 'f': memcpy(&want_fourcc, optarg, 4); break;
		case 'o': out = optarg; break;
		case 'n': loops = atoi(optarg); break;
		case 'b': ncap = atoi(optarg); break;
		case 'q': verbose = 0; break;
		case 't': timeout_ms = atoi(optarg); break;
		default: return 2;
		}
	}
	for (i = optind; i < argc; i++)
		add_file(argv[i]);
	if (!nframes)
		return 2;
	total = nframes * loops;
	for (i = 0; i < nframes; i++)
		if (frames[i].len > maxlen)
			maxlen = frames[i].len;

	if (out) {
		outf = fopen(out, "wb");
		if (!outf)
			die(out);
	}

	fd = open(dev, O_RDWR | O_NONBLOCK);
	if (fd < 0)
		die(dev);

	sub.type = V4L2_EVENT_SOURCE_CHANGE;
	xioctl(VIDIOC_SUBSCRIBE_EVENT, &sub, "SUBSCRIBE src");
	sub.type = V4L2_EVENT_EOS;
	xioctl(VIDIOC_SUBSCRIBE_EVENT, &sub, "SUBSCRIBE eos");

	of.fmt.pix_mp.pixelformat = V4L2_PIX_FMT_JPEG;
	of.fmt.pix_mp.num_planes = 1;
	of.fmt.pix_mp.plane_fmt[0].sizeimage = maxlen;
	xioctl(VIDIOC_S_FMT, &of, "S_FMT out");
	xioctl(VIDIOC_REQBUFS, &rb, "REQBUFS out");
	for (i = 0; i < (int)rb.count; i++) {
		struct v4l2_plane pl = {};
		struct v4l2_buffer b = { .type = rb.type, .memory = V4L2_MEMORY_MMAP,
					 .index = i, .m.planes = &pl, .length = 1 };

		xioctl(VIDIOC_QUERYBUF, &b, "QUERYBUF out");
		outlen[i] = pl.length;
		outmap[i] = mmap(NULL, pl.length, PROT_READ | PROT_WRITE,
				 MAP_SHARED, fd, pl.m.mem_offset);
		if (outmap[i] == MAP_FAILED)
			die("mmap out");
		inflight += queue_out(i, &next, total);
	}
	type = V4L2_BUF_TYPE_VIDEO_OUTPUT_MPLANE;
	xioctl(VIDIOC_STREAMON, &type, "STREAMON out");

	t0 = now();
	for (;;) {
		struct pollfd pfd = { .fd = fd, .events = POLLIN | POLLOUT | POLLPRI };
		int r = poll(&pfd, 1, timeout_ms);

		if (r == 0) {
			fprintf(stderr, "TIMEOUT: decoded %d of %d, inflight %d\n",
				decoded, total, inflight);
			return 3;
		}
		if (r < 0)
			die("poll");

		if (pfd.revents & POLLPRI) {
			struct v4l2_event ev;

			while (!ioctl(fd, VIDIOC_DQEVENT, &ev)) {
				if (ev.type == V4L2_EVENT_SOURCE_CHANGE) {
					src_changes++;
					/* initial setup; later ones follow EPIPE */
					if (!cap_on) {
						setup_capture();
						cap_on = 1;
					}
				} else if (ev.type == V4L2_EVENT_EOS && verbose) {
					fprintf(stderr, "EOS event\n");
				}
			}
		}

		/* OUTPUT buffers coming back */
		for (;;) {
			struct v4l2_plane pl = {};
			struct v4l2_buffer b = { .type = V4L2_BUF_TYPE_VIDEO_OUTPUT_MPLANE,
						 .memory = V4L2_MEMORY_MMAP,
						 .m.planes = &pl, .length = 1 };

			if (ioctl(fd, VIDIOC_DQBUF, &b))
				break;
			inflight--;
			if (b.flags & V4L2_BUF_FLAG_ERROR) {
				outerr++;
				if (verbose)
					fprintf(stderr, "output buffer %ld returned with ERROR\n",
						(long)b.timestamp.tv_sec);
			}
			inflight += queue_out(b.index, &next, total);
		}
		if (next >= total && !stopped && cap_on) {
			struct v4l2_decoder_cmd cmd = { .cmd = V4L2_DEC_CMD_STOP };

			xioctl(VIDIOC_DECODER_CMD, &cmd, "DECODER_CMD stop");
			stopped = 1;
		}
		if (!cap_on) {
			if (inflight == 0 && next >= total) {
				fprintf(stderr, "no source change: all %d frames rejected\n",
					outerr);
				break;
			}
			continue;
		}

		/* CAPTURE buffers */
		for (;;) {
			struct v4l2_plane pl = {};
			struct v4l2_buffer b = { .type = V4L2_BUF_TYPE_VIDEO_CAPTURE_MPLANE,
						 .memory = V4L2_MEMORY_MMAP,
						 .m.planes = &pl, .length = 1 };

			if (ioctl(fd, VIDIOC_DQBUF, &b)) {
				if (errno == EPIPE) {
					/* resolution change or end of drain */
					if (stopped && next >= total)
						goto done;
					teardown_capture();
					setup_capture();
					continue;
				}
				break;
			}
			if (b.flags & V4L2_BUF_FLAG_ERROR) {
				errors++;
				if (verbose)
					fprintf(stderr, "capture buffer for frame %ld: ERROR\n",
						(long)b.timestamp.tv_sec);
			} else if (pl.bytesused) {
				decoded++;
				if (outf)
					write_frame(capmap[b.index]);
			}
			if (b.flags & V4L2_BUF_FLAG_LAST) {
				if (stopped && next >= total)
					goto done;
				/* LAST without drain: resolution change */
				continue;
			}
			xioctl(VIDIOC_QBUF, &b, "QBUF cap");
		}
	}
done:
	t1 = now();
	printf("frames=%d decoded=%d cap_errors=%d out_errors=%d src_changes=%d time=%.3f fps=%.1f\n",
	       total, decoded, errors, outerr, src_changes, t1 - t0,
	       decoded / (t1 - t0));
	if (outf)
		fclose(outf);
	close(fd);
	return (errors || outerr) ? 1 : 0;
}
