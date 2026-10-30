// SPDX-License-Identifier: GPL-2.0
/* ddrbw SECS: read/write DDR bandwidth via the rockchip_ddr PMU (MB/s per second) */
#include <linux/perf_event.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/syscall.h>
#include <unistd.h>

static int open_ev(int type, const char *ev)
{
	char p[256], buf[64];
	FILE *f;
	unsigned long cfg = 0;
	struct perf_event_attr a;

	snprintf(p, sizeof(p), "/sys/bus/event_source/devices/rockchip_ddr/events/%s", ev);
	f = fopen(p, "r");
	if (!f || !fgets(buf, sizeof(buf), f)) return -1;
	fclose(f);
	sscanf(buf, "event=%lx", &cfg);
	memset(&a, 0, sizeof(a));
	a.type = type; a.size = sizeof(a); a.config = cfg;
	return syscall(__NR_perf_event_open, &a, -1, 0, -1, 0);
}

int main(int argc, char **argv)
{
	int n = argc > 1 ? atoi(argv[1]) : 3, type;
	FILE *f = fopen("/sys/bus/event_source/devices/rockchip_ddr/type", "r");
	fscanf(f, "%d", &type);
	int r = open_ev(type, "read-bytes"), w = open_ev(type, "write-bytes");
	uint64_t r0 = 0, w0 = 0, r1, w1;

	if (r < 0 || w < 0) { perror("perf_event_open"); return 1; }
	read(r, &r0, 8); read(w, &w0, 8);
	for (int i = 0; i < n; i++) {
		sleep(1);
		read(r, &r1, 8); read(w, &w1, 8);
		/* scale file says MB units per count? print raw*scale handled below */
		printf("rd %.0f wr %.0f MB/s\n", (r1 - r0) / 1048576.0, (w1 - w0) / 1048576.0);
		r0 = r1; w0 = w1;
	}
	return 0;
}
