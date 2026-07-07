#include "matrix_math.h"

void mat_zero(matrix_t dest) {
	for (int i = 0; i < 4; i++) {
		for (int j = 0; j < 4; j++) {
			dest[i][j] = 0;
		}
	}
}

void mat_identity(matrix_t dest) {
	mat_zero(dest);
	for (int i = 0; i < 4; i++) {
		dest[i][i] = 0x00010000; // 1.0
	}
}

void mat_vec_mul(vec4_t dest, matrix_t mat, vec4_t src) {
	for (int i = 0; i < 4; i++) {
		int64_t sum = 0;
		for (int j = 0; j < 4; j++) {
			sum += (int64_t)mat[i][j] * (int64_t)src[j];
		}
		dest[i] = (fixed_t)(sum >> 16);
	}
}

void mat_mat_mul(matrix_t dest, matrix_t mat1, matrix_t mat2) {
	for (int i = 0; i < 4; i++) {
		for (int j = 0; j < 4; j++) {
			int64_t sum = 0;
			for (int k = 0; k < 4; k++) {
				sum += (int64_t)mat1[i][k] * (int64_t)mat2[k][j];
			}
			dest[i][j] = (fixed_t)(sum >> 16);
		}
	}
}

void mat_print(matrix_t mat) {
	for (int row = 0; row < 4; row++) {
		vec4_print(mat[row]);
		printf("\n");
	}
}
