// SPDX-License-Identifier: GPL-2.0
/* memhog THREADS SECS: memcpy 64 MiB buffers in a loop to load DDR */
#include <pthread.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

static double secs;

static void *run(void *a)
{
	size_t n = 64 << 20;
	char *s = malloc(n), *d = malloc(n);
	struct timespec t0, t;

	memset(s, 1, n); memset(d, 2, n);
	clock_gettime(CLOCK_MONOTONIC, &t0);
	do {
		memcpy(d, s, n);
		clock_gettime(CLOCK_MONOTONIC, &t);
	} while (t.tv_sec - t0.tv_sec + (t.tv_nsec - t0.tv_nsec) / 1e9 < secs);
	return a;
}

int main(int argc, char **argv)
{
	int n = atoi(argv[1]);
	pthread_t th[16];

	secs = atof(argv[2]);
	for (int i = 0; i < n && i < 16; i++)
		pthread_create(&th[i], NULL, run, NULL);
	for (int i = 0; i < n && i < 16; i++)
		pthread_join(th[i], NULL);
	return 0;
}
