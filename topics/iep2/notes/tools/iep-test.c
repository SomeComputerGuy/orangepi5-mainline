// SPDX-License-Identifier: GPL-2.0-only
/*
 * Minimal V4L2 m2m test client for the rockchip-iep deinterlacer.
 *
 * iep-test -d /dev/videoN -i in.yuv -o out.yuv -w W -h H [-f nv12|nv16]
 *          [-F tb|bt|none] [-m bob|ma] [-r] [-n frames] [-b bufs]
 *          [-c cycles] [-l loops]
 *
 * -r: field rate (two CAPTURE buffers per OUTPUT buffer)
 * -c: run the whole stream <cycles> times with STREAMOFF/STREAMON in between
 * -l: feed the input file <loops> times (throughput measurement)
 * -o -: don't write output
 */
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>
#include <linux/videodev2.h>

#define CID_BASE		(V4L2_CID_USER_BASE + 0x1260)
#define CID_DEINT_MODE		(CID_BASE + 0)
#define CID_FIELD_RATE		(CID_BASE + 1)
#define MAXBUF			16

struct buf {
	void *addr;
	size_t len;
};

static int fd;
static struct buf obuf[MAXBUF], cbuf[MAXBUF];

static void die(const char *what)
{
	fprintf(stderr, "%s: %s\n", what, strerror(errno));
	exit(1);
}

static int xioctl(unsigned long req, void *arg)
{
	int r;

	do {
		r = ioctl(fd, req, arg);
	} while (r < 0 && errno == EINTR);
	return r;
}

static void set_ctrl(uint32_t id, int val)
{
	struct v4l2_control c = { .id = id, .value = val };

	if (xioctl(VIDIOC_S_CTRL, &c))
		die("S_CTRL");
}

static void qbuf(enum v4l2_buf_type type, int idx, uint32_t used,
		 uint32_t field, uint64_t ts_us)
{
	struct v4l2_plane pl = { 0 };
	struct v4l2_buffer b = { 0 };

	b.type = type;
	b.memory = V4L2_MEMORY_MMAP;
	b.index = idx;
	b.m.planes = &pl;
	b.length = 1;
	if (type == V4L2_BUF_TYPE_VIDEO_OUTPUT_MPLANE) {
		pl.bytesused = used;
		b.field = field;
		b.timestamp.tv_sec = ts_us / 1000000;
		b.timestamp.tv_usec = ts_us % 1000000;
	}
	if (xioctl(VIDIOC_QBUF, &b))
		die("QBUF");
}

static int dqbuf(enum v4l2_buf_type type, struct v4l2_buffer *b,
		 struct v4l2_plane *pl)
{
	memset(b, 0, sizeof(*b));
	b->type = type;
	b->memory = V4L2_MEMORY_MMAP;
	b->m.planes = pl;
	b->length = 1;
	return xioctl(VIDIOC_DQBUF, b);
}

static int reqbufs(enum v4l2_buf_type type, int n, struct buf *bufs)
{
	struct v4l2_requestbuffers rb = { .count = n, .type = type,
					  .memory = V4L2_MEMORY_MMAP };
	int i;

	for (i = 0; i < MAXBUF; i++) {
		if (bufs[i].addr)
			munmap(bufs[i].addr, bufs[i].len);
		bufs[i].addr = NULL;
	}
	if (xioctl(VIDIOC_REQBUFS, &rb))
		die("REQBUFS");
	for (i = 0; i < (int)rb.count; i++) {
		struct v4l2_plane pl = { 0 };
		struct v4l2_buffer b = { .type = type, .index = i,
					 .memory = V4L2_MEMORY_MMAP,
					 .m.planes = &pl, .length = 1 };

		if (xioctl(VIDIOC_QUERYBUF, &b))
			die("QUERYBUF");
		bufs[i].len = pl.length;
		bufs[i].addr = mmap(NULL, pl.length, PROT_READ | PROT_WRITE,
				    MAP_SHARED, fd, pl.m.mem_offset);
		if (bufs[i].addr == MAP_FAILED)
			die("mmap");
	}
	return rb.count;
}

static double now(void)
{
	struct timespec t;

	clock_gettime(CLOCK_MONOTONIC, &t);
	return t.tv_sec + t.tv_nsec / 1e9;
}

int main(int argc, char **argv)
{
	const char *dev = "/dev/video0", *in = NULL, *out = "-";
	int w = 720, h = 576, nframes = 0, nb = 4, cycles = 1, loops = 1;
	int mode = 1, frate = 0, opt, i;
	uint32_t fourcc = V4L2_PIX_FMT_NV12, field = V4L2_FIELD_INTERLACED_TB;
	enum v4l2_buf_type ot = V4L2_BUF_TYPE_VIDEO_OUTPUT_MPLANE;
	enum v4l2_buf_type ct = V4L2_BUF_TYPE_VIDEO_CAPTURE_MPLANE;
	struct v4l2_format f = { 0 };
	FILE *fin, *fout = NULL;
	size_t fsize, isize;
	unsigned char *data;
	long total_in = 0, total_out = 0, errs = 0;
	double t0, t1;

	while ((opt = getopt(argc, argv, "d:i:o:w:h:f:F:m:rn:b:c:l:")) != -1) {
		switch (opt) {
		case 'd': dev = optarg; break;
		case 'i': in = optarg; break;
		case 'o': out = optarg; break;
		case 'w': w = atoi(optarg); break;
		case 'h': h = atoi(optarg); break;
		case 'f':
			fourcc = !strcmp(optarg, "nv16") ? V4L2_PIX_FMT_NV16 :
				 !strcmp(optarg, "nv21") ? V4L2_PIX_FMT_NV21 :
				 !strcmp(optarg, "nv61") ? V4L2_PIX_FMT_NV61 :
				 V4L2_PIX_FMT_NV12;
			break;
		case 'F':
			field = !strcmp(optarg, "bt") ? V4L2_FIELD_INTERLACED_BT :
				!strcmp(optarg, "none") ? V4L2_FIELD_NONE :
				V4L2_FIELD_INTERLACED_TB;
			break;
		case 'm': mode = strcmp(optarg, "bob") ? 1 : 0; break;
		case 'r': frate = 1; break;
		case 'n': nframes = atoi(optarg); break;
		case 'b': nb = atoi(optarg); break;
		case 'c': cycles = atoi(optarg); break;
		case 'l': loops = atoi(optarg); break;
		default: return 2;
		}
	}
	if (!in)
		return 2;

	fd = open(dev, O_RDWR);
	if (fd < 0)
		die("open");

	f.type = ot;
	f.fmt.pix_mp.width = w;
	f.fmt.pix_mp.height = h;
	f.fmt.pix_mp.pixelformat = fourcc;
	f.fmt.pix_mp.field = field;
	f.fmt.pix_mp.num_planes = 1;
	if (xioctl(VIDIOC_S_FMT, &f))
		die("S_FMT out");
	if (f.fmt.pix_mp.width != (unsigned)w ||
	    f.fmt.pix_mp.height != (unsigned)h ||
	    f.fmt.pix_mp.plane_fmt[0].bytesperline != (unsigned)w) {
		fprintf(stderr, "unexpected format %ux%u bpl %u\n",
			f.fmt.pix_mp.width, f.fmt.pix_mp.height,
			f.fmt.pix_mp.plane_fmt[0].bytesperline);
		return 1;
	}
	/* frame size, without the driver's tail padding */
	isize = (size_t)w * h * (fourcc == V4L2_PIX_FMT_NV16 ||
				 fourcc == V4L2_PIX_FMT_NV61 ? 2 : 1.5);
	if (isize > f.fmt.pix_mp.plane_fmt[0].sizeimage)
		return 1;
	f.type = ct;
	if (xioctl(VIDIOC_G_FMT, &f))
		die("G_FMT cap");
	if (xioctl(VIDIOC_S_FMT, &f))
		die("S_FMT cap");

	set_ctrl(CID_DEINT_MODE, mode);
	set_ctrl(CID_FIELD_RATE, frate);

	fin = fopen(in, "rb");
	if (!fin)
		die("fopen in");
	fseek(fin, 0, SEEK_END);
	fsize = ftell(fin);
	rewind(fin);
	data = malloc(fsize);
	if (!data || fread(data, 1, fsize, fin) != fsize)
		die("read in");
	fclose(fin);
	if (!nframes || (size_t)nframes > fsize / isize)
		nframes = fsize / isize;
	if (strcmp(out, "-")) {
		fout = fopen(out, "wb");
		if (!fout)
			die("fopen out");
	}

	t0 = now();
	for (int cyc = 0; cyc < cycles; cyc++) {
		int nob, ncb, sent = 0, done = 0, outq = 0, total;
		int ofree[MAXBUF], nfree = 0;
		uint64_t last_cap_ts = 0;

		nob = reqbufs(ot, nb, obuf);
		ncb = reqbufs(ct, frate ? 2 * nb : nb, cbuf);
		for (i = 0; i < ncb; i++)
			qbuf(ct, i, 0, 0, 0);
		for (i = 0; i < nob; i++)
			ofree[nfree++] = i;
		if (xioctl(VIDIOC_STREAMON, &ot) || xioctl(VIDIOC_STREAMON, &ct))
			die("STREAMON");

		total = nframes * loops;
		while (done < total * (frate && field != V4L2_FIELD_NONE ? 2 : 1)) {
			struct v4l2_buffer b;
			struct v4l2_plane pl[1];
			fd_set rfds;
			struct timeval tv = { 2, 0 };

			while (nfree && sent < total) {
				int idx = ofree[--nfree];

				memcpy(obuf[idx].addr,
				       data + (size_t)(sent % nframes) * isize, isize);
				/* 25 Hz frame timestamps */
				qbuf(ot, idx, isize, field, 1000000 + sent * 40000ULL);
				sent++;
				outq++;
			}

			FD_ZERO(&rfds);
			FD_SET(fd, &rfds);
			if (select(fd + 1, &rfds, NULL, NULL, &tv) <= 0) {
				fprintf(stderr, "timeout: sent %d done %d\n",
					sent, done);
				return 1;
			}

			while (!dqbuf(ct, &b, pl)) {
				uint64_t ts = b.timestamp.tv_sec * 1000000ULL +
					      b.timestamp.tv_usec;

				if (b.flags & V4L2_BUF_FLAG_ERROR)
					errs++;
				if (done && ts <= last_cap_ts)
					fprintf(stderr, "non-monotonic ts %llu after %llu\n",
						(unsigned long long)ts,
						(unsigned long long)last_cap_ts);
				last_cap_ts = ts;
				if (fout && cyc == 0)
					fwrite(cbuf[b.index].addr, 1,
					       pl[0].bytesused, fout);
				done++;
				total_out++;
				qbuf(ct, b.index, 0, 0, 0);
				if (!(fcntl(fd, F_GETFL) & O_NONBLOCK))
					break;
			}
			fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK);
			while (!dqbuf(ot, &b, pl)) {
				ofree[nfree++] = b.index;
				outq--;
				total_in++;
			}
			fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) & ~O_NONBLOCK);
		}
		if (xioctl(VIDIOC_STREAMOFF, &ot) || xioctl(VIDIOC_STREAMOFF, &ct))
			die("STREAMOFF");
	}
	t1 = now();

	printf("in %ld out %ld errors %ld time %.3f s: %.1f in/s, %.1f out/s\n",
	       (long)nframes * loops * cycles, total_out, errs, t1 - t0,
	       nframes * loops * cycles / (t1 - t0), total_out / (t1 - t0));
	if (fout)
		fclose(fout);
	reqbufs(ot, 0, obuf);
	reqbufs(ct, 0, cbuf);
	close(fd);
	return errs ? 1 : 0;
}
