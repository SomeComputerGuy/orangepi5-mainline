#include "kern_shim.h"
void write_coeff_plane(const u8 coef[6][6][3], u8 *coeff_plane)
{
	unsigned int idx = 0, byte_count = 0;
	int k, m, n;
	u8 p;

	for (k = 0; k < 6; k++) {
		for (m = 0; m < 6; m++) {
			for (n = 0; n < 3; n++) {
				p = coef[k][m][n];
				coeff_plane[idx++] = p;
				byte_count++;
				if (byte_count == 27) {
					idx += 5;
					byte_count = 0;
				}
			}
		}
	}
}
