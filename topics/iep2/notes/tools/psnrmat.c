// psnrmat A B w h framebytes n0 n1 : luma PSNR of A[i] vs B[j], j in [i-3, i+3]
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
int main(int c, char **v)
{
	FILE *a = fopen(v[1], "rb"), *b = fopen(v[2], "rb");
	long w = atol(v[3]), h = atol(v[4]), fb = atol(v[5]);
	int n0 = atoi(v[6]), n1 = atoi(v[7]), sc = c > 8 ? atoi(v[8]) : 1;
	unsigned char *x = malloc(w * h), *y = malloc(w * h);
	for (int i = n0; i < n1; i++) {
		fseek(a, i * fb, SEEK_SET);
		if (fread(x, 1, w * h, a) != (size_t)(w * h)) break;
		printf("A%02d:", i);
		for (int j = i * sc - 3; j <= i * sc + 3; j++) {
			if (j < 0) { printf("   -   "); continue; }
			fseek(b, j * fb, SEEK_SET);
			if (fread(y, 1, w * h, b) != (size_t)(w * h)) { printf("   -   "); continue; }
			double s = 0;
			for (long k = 0; k < w * h; k++) { double d = x[k] - y[k]; s += d * d; }
			s /= w * h;
			printf(" %6.2f", s ? 10 * log10(255.0 * 255 / s) : 99.0);
		}
		printf("\n");
	}
	return 0;
}
