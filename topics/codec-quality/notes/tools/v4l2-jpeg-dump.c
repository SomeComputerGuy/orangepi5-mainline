// SPDX-License-Identifier: GPL-2.0-only
/*
 * v4l2-jpeg-dump: decode one JPEG on a V4L2 m2m JPEG decoder (MMAP, mplane) and write the
 * complete CAPTURE plane (bytesused, padding included) so the memory layout can be checked
 * against G_FMT.  Usage: v4l2-jpeg-dump /dev/videoN in.jpg out.raw [fourcc]
 */
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <poll.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <linux/videodev2.h>

#define X(c) do { if ((c) < 0) { perror(#c); exit(1); } } while (0)
#define MP V4L2_BUF_TYPE_VIDEO_OUTPUT_MPLANE
#define CP V4L2_BUF_TYPE_VIDEO_CAPTURE_MPLANE

int main(int argc, char **argv)
{
	int fd = open(argv[1], O_RDWR), in = open(argv[2], O_RDONLY);
	static unsigned char jpg[16 << 20];
	ssize_t len = read(in, jpg, sizeof(jpg));
	struct v4l2_format f = { .type = MP };
	struct v4l2_requestbuffers rb = { .count = 1, .memory = V4L2_MEMORY_MMAP };
	struct v4l2_plane pl[VIDEO_MAX_PLANES];
	struct v4l2_buffer b;
	struct v4l2_selection sel = { .type = V4L2_BUF_TYPE_VIDEO_CAPTURE, .target = V4L2_SEL_TGT_COMPOSE };
	void *p;
	int t;

	X(fd); X(len);
	f.fmt.pix_mp.pixelformat = V4L2_PIX_FMT_JPEG;
	f.fmt.pix_mp.width = 16; f.fmt.pix_mp.height = 16; f.fmt.pix_mp.num_planes = 1;
	f.fmt.pix_mp.plane_fmt[0].sizeimage = len + 4096;
	X(ioctl(fd, VIDIOC_S_FMT, &f));
	rb.type = MP; X(ioctl(fd, VIDIOC_REQBUFS, &rb));
	memset(&b, 0, sizeof(b)); b.type = MP; b.memory = V4L2_MEMORY_MMAP; b.m.planes = pl; b.length = 1;
	X(ioctl(fd, VIDIOC_QUERYBUF, &b));
	p = mmap(NULL, pl[0].length, PROT_READ | PROT_WRITE, MAP_SHARED, fd, pl[0].m.mem_offset);
	memcpy(p, jpg, len); pl[0].bytesused = len;
	X(ioctl(fd, VIDIOC_QBUF, &b));
	t = MP; X(ioctl(fd, VIDIOC_STREAMON, &t));
	/* the header was parsed at QBUF; the decoder updated the CAPTURE format */
	memset(&f, 0, sizeof(f)); f.type = CP; X(ioctl(fd, VIDIOC_G_FMT, &f));
	if (argc > 4) {
		f.fmt.pix_mp.pixelformat = v4l2_fourcc(argv[4][0], argv[4][1], argv[4][2], argv[4][3]);
		X(ioctl(fd, VIDIOC_S_FMT, &f));
	}
	X(ioctl(fd, VIDIOC_G_SELECTION, &sel));
	fprintf(stderr, "CAPTURE %.4s %ux%u bpl %u sizeimage %u planes %u, compose %ux%u\n",
		(char *)&f.fmt.pix_mp.pixelformat, f.fmt.pix_mp.width, f.fmt.pix_mp.height,
		f.fmt.pix_mp.plane_fmt[0].bytesperline, f.fmt.pix_mp.plane_fmt[0].sizeimage,
		f.fmt.pix_mp.num_planes, sel.r.width, sel.r.height);
	rb.type = CP; X(ioctl(fd, VIDIOC_REQBUFS, &rb));
	memset(&b, 0, sizeof(b)); b.type = CP; b.memory = V4L2_MEMORY_MMAP; b.m.planes = pl; b.length = 1;
	X(ioctl(fd, VIDIOC_QUERYBUF, &b));
	p = mmap(NULL, pl[0].length, PROT_READ | PROT_WRITE, MAP_SHARED, fd, pl[0].m.mem_offset);
	memset(p, 0xee, pl[0].length);	/* poison: bytes the hardware never writes stay 0xee */
	X(ioctl(fd, VIDIOC_QBUF, &b));
	t = CP; X(ioctl(fd, VIDIOC_STREAMON, &t));
	struct pollfd pf = { .fd = fd, .events = POLLIN };
	X(poll(&pf, 1, 2000));
	memset(&b, 0, sizeof(b)); b.type = CP; b.memory = V4L2_MEMORY_MMAP; b.m.planes = pl; b.length = 1;
	X(ioctl(fd, VIDIOC_DQBUF, &b));
	fprintf(stderr, "dequeued: bytesused %u flags 0x%x (length %u)\n", pl[0].bytesused, b.flags, pl[0].length);
	FILE *o = fopen(argv[3], "wb");
	fwrite(p, 1, pl[0].bytesused, o); fclose(o);
	return 0;
}
