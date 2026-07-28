#ifndef CAMERA_H
#define CAMERA_H

#include <stdint.h>

#include "graphics_math.h"

#define CAMERA_MOVE_SPEED 0x00008000

typedef struct {
    vec3_t pos;
    fixed_t azimuth;
    fixed_t elevation;
} camera_t;

void init_camera(camera_t *cam);

void get_default_proj_mat(matrix_t dest);

void get_camera_lookat(matrix_t dest, camera_t *cam);

void get_camera_matrix(matrix_t dest, camera_t *cam, matrix_t proj);

#endif // CAMERA_H
