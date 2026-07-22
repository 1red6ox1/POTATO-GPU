#ifndef GRAPHICS_MATH_H
#define GRAPHICS_MATH_H

#include "matrix_math.h"

#define FIXED_ONE 0x00010000

#define CAMERA_RADIUS  (4 * FIXED_ONE)
#define CAMERA_HEIGHT  (2 * FIXED_ONE)
#define CAMERA_BOB     (FIXED_ONE / 2)
#define CAMERA_NEAR    (FIXED_ONE / 4)
#define CAMERA_FAR     (16 * FIXED_ONE)
#define INVERSE_ASPECT 0x00009000

extern const fixed_t fov_coeff_lut [46]; // values for FOVy between 45-90 (inclusive)

void persp_proj_mat(matrix_t dest, uint8_t fovy, fixed_t inverse_aspect, fixed_t far, fixed_t near);

void lookat_mat(matrix_t dest, vec3_t eye, vec3_t center, vec3_t up);

void make_camera_matrix(matrix_t view_projection, uint8_t camera_phase, vec3_t eye);

#endif // GRAPHICS_MATH_H
