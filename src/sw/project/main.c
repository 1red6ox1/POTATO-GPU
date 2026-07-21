/* SPDX-License-Identifier: CC0-1.0
 * SPDX-FileCopyrightText: 2026 RVLab Contributors
 */

#include <stdint.h>
#include <stdio.h>
#include <rvlab.h>

#include "graphics_math.h"

#define FIXED_ONE 0x00010000

#define CPU_CLOCK_HZ 50000000u

#define COLOR_BUFFER_COUNT 3u
#define DEPTH_BUFFER_COUNT 2u
#define TRIANGLE_COUNT     12u

#define BACKGROUND_COLOR 0x02040cu
#define TRIANGLE_ID_MASK  0x7ffu

#define CAMERA_RADIUS  (5 * FIXED_ONE)
#define CAMERA_HEIGHT  (2 * FIXED_ONE)
#define CAMERA_BOB     (FIXED_ONE / 2)
#define CAMERA_NEAR    (FIXED_ONE / 4)
#define CAMERA_FAR     (16 * FIXED_ONE)
#define INVERSE_ASPECT 0x00009000

typedef struct {
	fixed_t x;
	fixed_t y;
	fixed_t z;
} vertex_t;

typedef struct {
	uint8_t a;
	uint8_t b;
	uint8_t c;
} triangle_t;

static const vertex_t cube_vertices[8] = {
	{-FIXED_ONE, -FIXED_ONE, -FIXED_ONE},
	{ FIXED_ONE, -FIXED_ONE, -FIXED_ONE},
	{ FIXED_ONE,  FIXED_ONE, -FIXED_ONE},
	{-FIXED_ONE,  FIXED_ONE, -FIXED_ONE},
	{-FIXED_ONE, -FIXED_ONE,  FIXED_ONE},
	{ FIXED_ONE, -FIXED_ONE,  FIXED_ONE},
	{ FIXED_ONE,  FIXED_ONE,  FIXED_ONE},
	{-FIXED_ONE,  FIXED_ONE,  FIXED_ONE},
};

static const triangle_t cube_triangles[TRIANGLE_COUNT] = {
	{0, 1, 2}, {0, 2, 3},
	{4, 6, 5}, {4, 7, 6},
	{0, 3, 7}, {0, 7, 4},
	{1, 5, 6}, {1, 6, 2},
	{0, 4, 5}, {0, 5, 1},
	{3, 2, 6}, {3, 6, 7},
};

static uint32_t cycle_count(void) {
	return (uint32_t)read_csr("mcycle");
}

// Input phase 0..255 represents 0..2*pi. The result is signed Q2.14.
static int32_t sin_q14(uint8_t phase) {
	uint32_t half_phase = phase & 0x7fu;
	uint32_t x = half_phase <= 64u ? half_phase : 128u - half_phase;
	int32_t value = (int32_t)(x * (128u - x) * 4u);

	return (phase & 0x80u) ? -value : value;
}

static int32_t cos_q14(uint8_t phase) {
	return sin_q14((uint8_t)(phase + 64u));
}

static uint32_t vertex_address(
	uint32_t triangle,
	uint32_t vertex,
	uint32_t lane
) {
	return VERTEX_DATA0_BASE_ADDR
		| (triangle << 6)
		| (vertex << 4)
		| (lane << 2);
}

static void cmd_upload_geometry(void) {
	for (uint32_t triangle = 0; triangle < TRIANGLE_COUNT; triangle++) {
		const triangle_t *indices = &cube_triangles[triangle];
		const uint8_t vertex_indices[3] = {
			indices->a, indices->b, indices->c
		};

		for (uint32_t vertex = 0; vertex < 3; vertex++) {
			const vertex_t *position = &cube_vertices[vertex_indices[vertex]];

			REG32(vertex_address(triangle, vertex, 0)) = position->x;
			REG32(vertex_address(triangle, vertex, 1)) = position->y;
			REG32(vertex_address(triangle, vertex, 2)) = position->z;
			REG32(vertex_address(triangle, vertex, 3)) = FIXED_ONE;
		}

		REG32(LOAD_TEXTURE0_BASE_ADDR
		      + ((triangle & TRIANGLE_ID_MASK) << 2)) = triangle;
	}

	// The register contains the last triangle ID, not the number of triangles.
	REG32(VERTEX_PROCESSOR_TRIANGLE_COUNT(0)) = TRIANGLE_COUNT - 1u;
}

static void cmd_clear_color(uint8_t color_buffer) {
	REG32(FRAMECLEAR_DMA_FBID(0)) = color_buffer;
	REG32(FRAMECLEAR_DMA_CLEAR_COLOR(0)) = BACKGROUND_COLOR;
	REG32(FRAMECLEAR_DMA_MODE(0)) = 0u;
	REG32(FRAMECLEAR_DMA_STATUS(0)) = 1u;

	while (REG32(FRAMECLEAR_DMA_STATUS(0))) {
	}
}

static void cmd_clear_depth(uint8_t depth_buffer) {
	REG32(FRAMECLEAR_DMA_FBID(0)) = depth_buffer;
	REG32(FRAMECLEAR_DMA_MODE(0)) = 1u;
	REG32(FRAMECLEAR_DMA_STATUS(0)) = 1u;

	while (REG32(FRAMECLEAR_DMA_STATUS(0))) {
	}
}

static void make_camera_matrix(
	matrix_t view_projection,
	uint8_t camera_phase,
	vec3_t eye
) {
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

static void cmd_upload_matrix(matrix_t matrix) {
	for (uint32_t row = 0; row < 4; row++) {
		for (uint32_t column = 0; column < 4; column++) {
			uint32_t index = row * 4u + column;

			REG32(VERTEX_CFG0_BASE_ADDR + (index << 2)) =
				(uint32_t)matrix[row][column];
		}
	}
}

static void cmd_render_frame(
	uint8_t color_buffer,
	uint8_t depth_buffer
) {
	cmd_clear_color(color_buffer);
	cmd_clear_depth(depth_buffer);

	// STATUS is write-one-to-clear. Clear the previous completion before
	// launching the vertex processor's real triangles and completion marker.
	REG32(RASTERIZER_STATUS_STATUS(0)) =
		RASTERIZER_STATUS_STATUS_VALID_MASK;
	REG32(TRIANGLE_INPUT_FBID_COLOR(0)) = color_buffer;
	REG32(TRIANGLE_INPUT_FBID_DEPTH(0)) = depth_buffer;
	REG32(VERTEX_PROCESSOR_START_RENDER(0)) = 1u;

	while (!(REG32(RASTERIZER_STATUS_STATUS(0))
	         & RASTERIZER_STATUS_STATUS_VALID_MASK)) {
	}
}

static void report_fps(
	uint32_t frame,
	uint32_t frame_cycles,
	uint8_t color_buffer,
	uint8_t depth_buffer,
	vec3_t eye
) {
	uint32_t fps_x100 = (uint32_t)(
		((uint64_t)CPU_CLOCK_HZ * 100u + frame_cycles / 2u)
		/ frame_cycles
	);

	printf(
		"frame %u: work %u cycles, fps %u.%02u, color %u, depth %u, "
		"camera (%d, %d, %d)\n",
		frame,
		frame_cycles,
		fps_x100 / 100u,
		fps_x100 % 100u,
		color_buffer,
		depth_buffer,
		eye[0],
		eye[1],
		eye[2]
	);
}

int main(void) {
	matrix_t camera_matrix;
	vec3_t camera_eye;
	uint8_t draw_color = 1u;
	uint8_t draw_depth = 0u;
	uint8_t camera_phase = 0u;
	uint32_t frame_start;
	uint32_t frame = 0u;

	if (ddr_init()) {
		printf("DDR initialization failed\n");
		while (1) {
		}
	}

	printf("\n=== VERTEX PROCESSOR TRIPLE-BUFFER DEMO ===\n");
	printf("3 color buffers, 2 depth buffers, hardware completion polling\n");

	cmd_upload_geometry();

	for (uint8_t buffer = 0; buffer < COLOR_BUFFER_COUNT; buffer++) {
		cmd_clear_color(buffer);
	}
	for (uint8_t buffer = 0; buffer < DEPTH_BUFFER_COUNT; buffer++) {
		cmd_clear_depth(buffer);
	}

	REG32(HDMI_CTRL_FBID(0)) = 0u;
	REG32(HDMI_CTRL_CTRL(0)) =
		(1u << HDMI_CTRL_CTRL_PHY_ENABLE_LSB)
		| (1u << HDMI_CTRL_CTRL_FETCH_ENABLE_LSB);

	frame_start = cycle_count();
	while (1) {
		uint32_t frame_cycles;

		make_camera_matrix(camera_matrix, camera_phase, camera_eye);
		cmd_upload_matrix(camera_matrix);
		cmd_render_frame(draw_color, draw_depth);

		// Rasterizer completion guarantees that this color buffer is complete.
		// HDMI applies the requested ID at its next video-frame boundary.
		REG32(HDMI_CTRL_FBID(0)) = draw_color;

		frame++;
		frame_cycles = cycle_count() - frame_start;
		frame_start = cycle_count();
		report_fps(
			frame,
			frame_cycles,
			draw_color,
			draw_depth,
			camera_eye
		);

		// The next timing interval starts before printf above, so printing,
		// camera work, matrix writes, clears and rasterization are all included.
		draw_color = (uint8_t)((draw_color + 1u) % COLOR_BUFFER_COUNT);
		draw_depth = (uint8_t)((draw_depth + 1u) % DEPTH_BUFFER_COUNT);
		camera_phase = (uint8_t)(camera_phase + 2u);
	}
}
