// SPDX-License-Identifier: GPL-2.0
/*
 * planetest - minimal atomic KMS plane bandwidth test (raw ioctls, no libdrm)
 *
 *   planetest [-c crtc] [-o conn] [-m WxH@R] [-t secs] [-s] P[:FMT[:WxH[:FBH]]][@X,Y,W,H] ...
 *
 * Every plane listed is placed full screen on the CRTC; every other plane
 * currently on that CRTC is disabled. Each plane gets two framebuffers with
 * different content and the commit flips between them every vblank (unless
 * -s: static). FBH is the allocated buffer height (e.g. 2176 for rkvdec NV12),
 * the source rectangle is WxH. Prints the achieved flip rate.
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
#include <drm/drm.h>
#include <drm/drm_mode.h>
#include <drm/drm_fourcc.h>

#define MAXP 8
#define MAXPROPS 64

static int fd;

static int xioctl(unsigned long req, void *arg)
{
	int r;

	do {
		r = ioctl(fd, req, arg);
	} while (r == -1 && (errno == EINTR || errno == EAGAIN));
	return r;
}

static uint32_t prop_id(uint32_t obj, uint32_t type, const char *name)
{
	uint32_t ids[MAXPROPS];
	uint64_t vals[MAXPROPS];
	struct drm_mode_obj_get_properties gp = {
		.props_ptr = (uintptr_t)ids, .prop_values_ptr = (uintptr_t)vals,
		.count_props = MAXPROPS, .obj_id = obj, .obj_type = type };

	if (xioctl(DRM_IOCTL_MODE_OBJ_GETPROPERTIES, &gp))
		return 0;
	for (unsigned int i = 0; i < gp.count_props && i < MAXPROPS; i++) {
		struct drm_mode_get_property p = { .prop_id = ids[i] };

		if (xioctl(DRM_IOCTL_MODE_GETPROPERTY, &p))
			continue;
		if (!strcmp(p.name, name))
			return ids[i];
	}
	return 0;
}

static uint64_t prop_val(uint32_t obj, uint32_t type, const char *name)
{
	uint32_t ids[MAXPROPS];
	uint64_t vals[MAXPROPS];
	struct drm_mode_obj_get_properties gp = {
		.props_ptr = (uintptr_t)ids, .prop_values_ptr = (uintptr_t)vals,
		.count_props = MAXPROPS, .obj_id = obj, .obj_type = type };

	if (xioctl(DRM_IOCTL_MODE_OBJ_GETPROPERTIES, &gp))
		return 0;
	for (unsigned int i = 0; i < gp.count_props && i < MAXPROPS; i++) {
		struct drm_mode_get_property p = { .prop_id = ids[i] };

		if (xioctl(DRM_IOCTL_MODE_GETPROPERTY, &p))
			continue;
		if (!strcmp(p.name, name))
			return vals[i];
	}
	return 0;
}

struct fb {
	uint32_t id;
	uint8_t *map;
	uint64_t size;
};

struct plane {
	uint32_t id;
	uint32_t fourcc;
	uint32_t w, h, fbh;
	uint32_t dx, dy, dw, dh;
	struct fb fb[2];
	uint32_t fbprop;
};

static void make_fb(struct plane *p, struct fb *f, int phase)
{
	struct drm_mode_create_dumb cd = { 0 };
	struct drm_mode_map_dumb md = { 0 };
	struct drm_mode_fb_cmd2 ac = { 0 };
	int nv12 = p->fourcc == DRM_FORMAT_NV12;

	cd.width = p->w;
	cd.height = nv12 ? p->fbh * 3 / 2 : p->fbh;
	cd.bpp = nv12 ? 8 : 32;
	if (xioctl(DRM_IOCTL_MODE_CREATE_DUMB, &cd)) {
		perror("create_dumb");
		exit(1);
	}
	md.handle = cd.handle;
	xioctl(DRM_IOCTL_MODE_MAP_DUMB, &md);
	f->size = cd.size;
	f->map = mmap(NULL, cd.size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, md.offset);
	if (f->map == MAP_FAILED) {
		perror("mmap");
		exit(1);
	}
	/* bars that move between the two buffers */
	for (uint32_t y = 0; y < p->fbh; y++) {
		if (nv12) {
			uint8_t *row = f->map + (uint64_t)y * cd.pitch;

			for (uint32_t x = 0; x < p->w; x++)
				row[x] = (uint8_t)(((x + phase * 256) >> 3) ^ (y >> 3));
		} else {
			uint32_t *row = (uint32_t *)(f->map + (uint64_t)y * cd.pitch);

			for (uint32_t x = 0; x < p->w; x++) {
				uint32_t v = ((x + phase * 256) >> 4) ^ (y >> 4);

				row[x] = 0xff000000 | (v & 0xff) << 16 | (v * 3 & 0xff) << 8 | (v * 7 & 0xff);
			}
		}
	}
	if (nv12)
		memset(f->map + (uint64_t)p->fbh * cd.pitch, 0x80 + phase * 0x20,
		       (uint64_t)p->fbh / 2 * cd.pitch);

	ac.width = p->w;
	ac.height = p->fbh;
	ac.pixel_format = p->fourcc;
	ac.handles[0] = cd.handle;
	ac.pitches[0] = cd.pitch;
	if (nv12) {
		ac.handles[1] = cd.handle;
		ac.pitches[1] = cd.pitch;
		ac.offsets[1] = cd.pitch * p->fbh;
	}
	if (xioctl(DRM_IOCTL_MODE_ADDFB2, &ac)) {
		perror("addfb2");
		exit(1);
	}
	f->id = ac.fb_id;
}

struct req {
	uint32_t objs[MAXP * 2 + 4];
	uint32_t cnt[MAXP * 2 + 4];
	uint32_t props[256];
	uint64_t vals[256];
	int nobj, nprop;
};

static void add(struct req *r, uint32_t obj, uint32_t prop, uint64_t val)
{
	if (!prop) {
		fprintf(stderr, "missing property on obj %u\n", obj);
		exit(1);
	}
	if (!r->nobj || r->objs[r->nobj - 1] != obj) {
		r->objs[r->nobj] = obj;
		r->cnt[r->nobj++] = 0;
	}
	r->cnt[r->nobj - 1]++;
	r->props[r->nprop] = prop;
	r->vals[r->nprop++] = val;
}

static int commit(struct req *r, uint32_t flags)
{
	struct drm_mode_atomic a = {
		.flags = flags, .count_objs = r->nobj,
		.objs_ptr = (uintptr_t)r->objs, .count_props_ptr = (uintptr_t)r->cnt,
		.props_ptr = (uintptr_t)r->props, .prop_values_ptr = (uintptr_t)r->vals };
	return ioctl(fd, DRM_IOCTL_MODE_ATOMIC, &a);
}

int main(int argc, char **argv)
{
	uint32_t crtc = 83, conn = 88, mw = 3840, mh = 2160, mr = 120;
	double secs = 10;
	int stat = 0, nplanes = 0, opt, nx = 0;
	uint32_t xpl[8];
	struct plane pl[MAXP];

	while ((opt = getopt(argc, argv, "c:o:m:t:sx:")) != -1) {
		switch (opt) {
		case 'c': crtc = atoi(optarg); break;
		case 'o': conn = atoi(optarg); break;
		case 'm': sscanf(optarg, "%ux%u@%u", &mw, &mh, &mr); break;
		case 't': secs = atof(optarg); break;
		case 's': stat = 1; break;
		case 'x': if (nx < 8) xpl[nx++] = atoi(optarg); break;
		default: return 2;
		}
	}
	for (; optind < argc && nplanes < MAXP; optind++) {
		struct plane *p = &pl[nplanes++];
		char fmt[8] = "XR24";

		memset(p, 0, sizeof(*p));
		p->w = mw;
		p->h = mh;
		p->fbh = 0;
		{
			char *at = strchr(argv[optind], '@');

			p->dw = mw;
			p->dh = mh;
			if (at) {
				*at = 0;
				sscanf(at + 1, "%u,%u,%u,%u", &p->dx, &p->dy, &p->dw, &p->dh);
			}
		}
		sscanf(argv[optind], "%u:%4[^:]:%ux%u:%u", &p->id, fmt, &p->w, &p->h, &p->fbh);
		if (!p->fbh)
			p->fbh = p->h;
		p->fourcc = !strcmp(fmt, "NV12") ? DRM_FORMAT_NV12 : DRM_FORMAT_XRGB8888;
	}

	fd = open("/dev/dri/card0", O_RDWR | O_CLOEXEC);
	if (fd < 0) {
		perror("open");
		return 1;
	}
	{
		struct drm_set_client_cap c1 = { DRM_CLIENT_CAP_UNIVERSAL_PLANES, 1 };
		struct drm_set_client_cap c2 = { DRM_CLIENT_CAP_ATOMIC, 1 };

		if (xioctl(DRM_IOCTL_SET_CLIENT_CAP, &c1) || xioctl(DRM_IOCTL_SET_CLIENT_CAP, &c2)) {
			perror("caps");
			return 1;
		}
		if (xioctl(DRM_IOCTL_SET_MASTER, NULL))
			perror("set_master (continuing)");
	}

	/* find mode */
	struct drm_mode_modeinfo modes[128], *mode = NULL;
	struct drm_mode_get_connector gc = { .connector_id = conn };

	xioctl(DRM_IOCTL_MODE_GETCONNECTOR, &gc);
	if (gc.count_modes > 128)
		gc.count_modes = 128;
	gc.modes_ptr = (uintptr_t)modes;
	gc.count_props = gc.count_encoders = 0;
	xioctl(DRM_IOCTL_MODE_GETCONNECTOR, &gc);
	for (unsigned int i = 0; i < gc.count_modes; i++)
		if (modes[i].hdisplay == mw && modes[i].vdisplay == mh && modes[i].vrefresh == mr) {
			mode = &modes[i];
			break;
		}
	if (!mode) {
		fprintf(stderr, "mode %ux%u@%u not found\n", mw, mh, mr);
		return 1;
	}
	struct drm_mode_create_blob cb = { .data = (uintptr_t)mode, .length = sizeof(*mode) };

	xioctl(DRM_IOCTL_MODE_CREATEPROPBLOB, &cb);

	for (int i = 0; i < nplanes; i++) {
		/* SHARE=1: planes with the same format/size scan out the same buffers */
		if (i && getenv("SHARE") && pl[i].fourcc == pl[0].fourcc &&
		    pl[i].w == pl[0].w && pl[i].fbh == pl[0].fbh) {
			pl[i].fb[0] = pl[0].fb[0];
			pl[i].fb[1] = pl[0].fb[1];
			continue;
		}
		make_fb(&pl[i], &pl[i].fb[0], 0);
		make_fb(&pl[i], &pl[i].fb[1], 1);
	}

	/* all planes */
	uint32_t pids[32];
	struct drm_mode_get_plane_res pr = { .plane_id_ptr = (uintptr_t)pids, .count_planes = 32 };

	xioctl(DRM_IOCTL_MODE_GETPLANERESOURCES, &pr);

	struct req r = { 0 };

	add(&r, conn, prop_id(conn, DRM_MODE_OBJECT_CONNECTOR, "CRTC_ID"), crtc);
	add(&r, crtc, prop_id(crtc, DRM_MODE_OBJECT_CRTC, "MODE_ID"), cb.blob_id);
	add(&r, crtc, prop_id(crtc, DRM_MODE_OBJECT_CRTC, "ACTIVE"), 1);
	for (unsigned int i = 0; i < pr.count_planes; i++) {
		int listed = 0;

		for (int j = 0; j < nplanes; j++)
			listed |= pl[j].id == pids[i];
		if (listed)
			continue;
		int extra = 0;

		for (int j = 0; j < nx; j++)
			extra |= xpl[j] == pids[i];
		if (extra || prop_val(pids[i], DRM_MODE_OBJECT_PLANE, "CRTC_ID") == crtc) {
			add(&r, pids[i], prop_id(pids[i], DRM_MODE_OBJECT_PLANE, "FB_ID"), 0);
			add(&r, pids[i], prop_id(pids[i], DRM_MODE_OBJECT_PLANE, "CRTC_ID"), 0);
			printf("disabling plane %u\n", pids[i]);
		}
	}
	for (int j = 0; j < nplanes; j++) {
		struct plane *p = &pl[j];
		uint32_t o = p->id;
		uint32_t zp = prop_id(o, DRM_MODE_OBJECT_PLANE, "zpos");

		p->fbprop = prop_id(o, DRM_MODE_OBJECT_PLANE, "FB_ID");
		add(&r, o, p->fbprop, p->fb[0].id);
		add(&r, o, prop_id(o, DRM_MODE_OBJECT_PLANE, "CRTC_ID"), crtc);
		add(&r, o, prop_id(o, DRM_MODE_OBJECT_PLANE, "SRC_X"), 0);
		add(&r, o, prop_id(o, DRM_MODE_OBJECT_PLANE, "SRC_Y"), 0);
		add(&r, o, prop_id(o, DRM_MODE_OBJECT_PLANE, "SRC_W"), (uint64_t)p->w << 16);
		add(&r, o, prop_id(o, DRM_MODE_OBJECT_PLANE, "SRC_H"), (uint64_t)p->h << 16);
		add(&r, o, prop_id(o, DRM_MODE_OBJECT_PLANE, "CRTC_X"), p->dx);
		add(&r, o, prop_id(o, DRM_MODE_OBJECT_PLANE, "CRTC_Y"), p->dy);
		add(&r, o, prop_id(o, DRM_MODE_OBJECT_PLANE, "CRTC_W"), p->dw);
		add(&r, o, prop_id(o, DRM_MODE_OBJECT_PLANE, "CRTC_H"), p->dh);
		if (zp)
			add(&r, o, zp, j);
	}
	if (commit(&r, DRM_MODE_ATOMIC_ALLOW_MODESET)) {
		perror("modeset commit");
		return 1;
	}
	printf("mode %ux%u@%u clock %u kHz, %d plane(s) on crtc %u\n", mw, mh, mr, mode->clock,
	       nplanes, crtc);

	struct timespec t0, t1;
	long frames = 0;
	double el = 0;

	clock_gettime(CLOCK_MONOTONIC, &t0);
	while (el < secs) {
		if (!stat) {
			struct req f = { 0 };

			for (int j = 0; j < nplanes; j++)
				add(&f, pl[j].id, pl[j].fbprop, pl[j].fb[(frames + 1) & 1].id);
			if (commit(&f, DRM_MODE_PAGE_FLIP_EVENT | DRM_MODE_ATOMIC_NONBLOCK)) {
				perror("flip");
				break;
			}
			struct pollfd pf = { .fd = fd, .events = POLLIN };
			char buf[256];

			if (poll(&pf, 1, 1000) <= 0) {
				fprintf(stderr, "flip timeout\n");
				break;
			}
			if (read(fd, buf, sizeof(buf)) < 0)
				break;
		} else {
			usleep(100000);
		}
		frames++;
		clock_gettime(CLOCK_MONOTONIC, &t1);
		el = (t1.tv_sec - t0.tv_sec) + (t1.tv_nsec - t0.tv_nsec) / 1e9;
	}
	if (!stat)
		printf("%ld flips in %.2f s = %.1f fps\n", frames, el, frames / el);
	return 0;
}
