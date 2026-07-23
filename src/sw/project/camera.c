#include "camera.h"

#define CAMERA_LOOK_DISTANCE 0x00040000
#define CAMERA_NEAR    (FIXED_ONE / 4)
#define CAMERA_FAR     (16 * FIXED_ONE)
#define INVERSE_ASPECT 0x00009000

void init_camera(camera_t *cam) {
	cam->pos[0] = 0;
	cam->pos[1] = 0;
	cam->pos[2] = 0;
	cam->azimuth = 0;
	cam->elevation = 0;
}

void get_default_proj_mat(matrix_t dest) {
	fixed_t depth_range = CAMERA_FAR - CAMERA_NEAR;

	persp_proj_mat(
		dest,
		60u,
		INVERSE_ASPECT,
		CAMERA_FAR,
		CAMERA_NEAR
	);

	// Inverse Z depth testing requires flipping logic
	dest[2][2] = fixed_div(CAMERA_NEAR, depth_range);
	dest[2][3] = fixed_div(
		fixed_mul(CAMERA_NEAR, CAMERA_FAR), depth_range
	);
}

static void camera_get_target(const camera_t *cam, vec3_t out) {
	fixed_t sin_az = fixed_sin(cam->azimuth);
	fixed_t cos_az = fixed_cos(cam->azimuth);
	fixed_t sin_el = fixed_sin(cam->elevation);
	fixed_t cos_el = fixed_cos(cam->elevation);

	/* unit view direction, in spherical -> cartesian form */
	fixed_t dir_x = fixed_mul(cos_el, sin_az);
	fixed_t dir_y = sin_el;
	fixed_t dir_z = fixed_mul(cos_el, cos_az);

	out[0] = cam->pos[0] + fixed_mul(dir_x, CAMERA_LOOK_DISTANCE);
	out[1] = cam->pos[1] + fixed_mul(dir_y, CAMERA_LOOK_DISTANCE);
	out[2] = cam->pos[2] + fixed_mul(dir_z, CAMERA_LOOK_DISTANCE);
}


void get_camera_lookat(matrix_t dest, camera_t *cam) {
	vec3_t cam_target;
	camera_get_target(cam, cam_target);
	lookat_mat(dest, cam->pos, cam_target, (vec3_t){0x00000000, 0x00010000, 0x00000000});
}

void get_camera_matrix(matrix_t dest, camera_t *cam, matrix_t proj) {
	matrix_t lookat;
	get_camera_lookat(lookat, cam);
	mat_mat_mul(dest, proj, lookat);
}
