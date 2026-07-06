#ifndef GRAPHICS_MATH_H
#define GRAPHICS_MATH_H

#include "matrix_math.h"

extern const fixed_t fov_coeff_lut [46]; // values for FOVy between 45-90 (inclusive)

void persp_proj_mat(matrix_t dest, uint8_t fovy, fixed_t inverse_aspect, fixed_t far, fixed_t near);

void lookat_mat(matrix_t dest, vec3_t eye, vec3_t center, vec3_t up);

#endif // GRAPHICS_MATH_H
