// vblwait: wait N consecutive vblanks on a CRTC index (no DRM master needed) and print the
// kernel's vblank timestamp and the CLOCK_MONOTONIC wake-up time for each.
// usage: vblwait <crtc-index> <count>      build: gcc -O2 -o vblwait vblwait.c (uapi headers only)
#include <stdio.h>
#include <stdlib.h>
#include <fcntl.h>
#include <time.h>
#include <sys/ioctl.h>
#include <drm/drm.h>
int main(int argc, char **argv)
{
	int crtc = atoi(argv[1]), n = atoi(argv[2]);
	int fd = open("/dev/dri/card0", O_RDWR | O_CLOEXEC);
	if (fd < 0) { perror("open"); return 1; }
	for (int i = 0; i < n; i++) {
		union drm_wait_vblank v = { .request = { .type = _DRM_VBLANK_RELATIVE |
			((crtc << _DRM_VBLANK_HIGH_CRTC_SHIFT) & _DRM_VBLANK_HIGH_CRTC_MASK), .sequence = 1 } };
		struct timespec ts;
		if (ioctl(fd, DRM_IOCTL_WAIT_VBLANK, &v)) { perror("DRM_IOCTL_WAIT_VBLANK"); return 1; }
		clock_gettime(CLOCK_MONOTONIC, &ts);
		printf("%u %ld.%06ld %ld.%09ld\n", v.reply.sequence, v.reply.tval_sec, v.reply.tval_usec,
		       ts.tv_sec, ts.tv_nsec);
	}
	return 0;
}
