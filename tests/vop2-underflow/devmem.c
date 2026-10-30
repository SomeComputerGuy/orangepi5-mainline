// SPDX-License-Identifier: GPL-2.0
/* devmem ADDR [VAL]: 32-bit MMIO read/write through /dev/mem (debug only) */
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/mman.h>
#include <unistd.h>

int main(int argc, char **argv)
{
	unsigned long a = strtoul(argv[1], NULL, 0), pg = a & ~0xfffUL;
	int n = argc > 3 ? atoi(argv[3]) : 1;
	int fd = open("/dev/mem", O_RDWR | O_SYNC);
	volatile uint32_t *p;

	if (fd < 0) { perror("open"); return 1; }
	p = mmap(NULL, 0x2000, PROT_READ | PROT_WRITE, MAP_SHARED, fd, pg);
	if (p == MAP_FAILED) { perror("mmap"); return 1; }
	p += (a - pg) / 4;
	if (argc > 2 && argv[2][0] != '-')
		*p = strtoul(argv[2], NULL, 0);
	for (int i = 0; i < n; i++)
		printf("%08lx: %08x\n", a + 4 * i, p[i]);
	return 0;
}
