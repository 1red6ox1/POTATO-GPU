#include "graphics_math.h"

void persp_proj_mat(matrix_t dest, uint8_t fovy, fixed_t inverse_aspect, fixed_t far, fixed_t near) {
	mat_zero(dest);
	if (fovy < 45) fovy = 45;
	if (fovy > 90) fovy = 90;
	fixed_t y_scale = fov_coeff_lut[fovy - 45];
	fixed_t x_scale = fixed_mul(y_scale, inverse_aspect);
	fixed_t two_f_n = 2 * fixed_mul(far, near);
	dest[0][0] = x_scale;
	dest[1][1] = y_scale;
	dest[2][2] = -fixed_div(far + near, far - near);
	dest[3][2] = -0x00010000; // -1.0
	dest[2][3] = -fixed_div(two_f_n, far - near);
}

// Inspired by https://github.com/g-truc/glm/blob/6f14f4792a0cde5d0cf2c910506724d61cb95834/glm/ext/matrix_transform.inl#L153
void lookat_mat(matrix_t dest, vec3_t eye, vec3_t center, vec3_t up) {
	vec3_t eye_to_center;
	vec3_t cross_f_up;
	// Orthonormal basis vectors
	vec3_t f;
	vec3_t s;
	vec3_t u;

	vec3_sub(eye_to_center, center, eye);
	vec3_normalize(f, eye_to_center);
	vec3_cross(cross_f_up, f, up);
	vec3_normalize(s, cross_f_up);
	vec3_cross(u, s, f);

	dest[0][0] = s[0];
	dest[0][1] = s[1];
	dest[0][2] = s[2];
	dest[0][3] = -vec3_dot(s, eye);
	dest[1][0] = u[0];
	dest[1][1] = u[1];
	dest[1][2] = u[2];
	dest[1][3] = -vec3_dot(u, eye);
	dest[2][0] = -f[0];
	dest[2][1] = -f[1];
	dest[2][2] = -f[2];
	dest[2][3] = vec3_dot(f, eye);
	dest[3][0] = 0x00000000;
	dest[3][1] = 0x00000000;
	dest[3][2] = 0x00000000;
	dest[3][3] = 0x00010000;
}

void make_camera_matrix(matrix_t view_projection, uint8_t camera_phase, vec3_t eye) {
	matrix_t view;
	matrix_t projection;
	vec3_t center = {0, 0, 0};
	vec3_t up = {0, FIXED_ONE, 0};
	fixed_t sin_phase = (fixed_t)(sin_q14(camera_phase) * 4);
	fixed_t cos_phase = (fixed_t)(cos_q14(camera_phase) * 4);
	fixed_t bob_phase =
		(fixed_t)(sin_q14((uint8_t)(camera_phase * 2u)) * 4);
	fixed_t depth_range = CAMERA_FAR - CAMERA_NEAR;

	eye[0] = fixed_mul(CAMERA_RADIUS, sin_phase);
	eye[1] = CAMERA_HEIGHT + fixed_mul(CAMERA_BOB, bob_phase);
	eye[2] = fixed_mul(CAMERA_RADIUS, cos_phase);

	lookat_mat(view, eye, center, up);
	persp_proj_mat(
		projection,
		60u,
		INVERSE_ASPECT,
		CAMERA_FAR,
		CAMERA_NEAR
	);

	// The rasterizer accepts a fragment when its depth is larger than the
	// stored value. Replace the conventional projection depth with reversed Z:
	// the near plane maps to one and the far plane maps to zero.
	projection[2][2] = fixed_div(CAMERA_NEAR, depth_range);
	projection[2][3] = fixed_div(
		fixed_mul(CAMERA_NEAR, CAMERA_FAR), depth_range
	);

	mat_mat_mul(view_projection, projection, view);
}
