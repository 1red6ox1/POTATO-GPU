#ifndef MATRIX_MATH_H
#define MATRIX_MATH_H

#include "vector_math.h"

// Convention: We use row-major matrices
typedef vec4_t matrix_t [4];

void mat_zero(matrix_t dest);

void mat_identity(matrix_t dest);

void mat_vec_mul(vec4_t dest, matrix_t mat, vec4_t src);

// dest may not be one of mat1, mat2
void mat_mat_mul(matrix_t dest, matrix_t mat1, matrix_t mat2);

void mat_print(matrix_t mat);

#endif // MATRIX_MATH_H
