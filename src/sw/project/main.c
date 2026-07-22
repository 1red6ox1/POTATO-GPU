/* SPDX-License-Identifier: CC0-1.0
 * SPDX-FileCopyrightText: 2026 RVLab Contributors
 */

#include <stdint.h>
#include <stdio.h>
#include <rvlab.h>

#include "graphics_math.h"
#include "memcpy.h"
#include "graphics_pipeline.h"

#define TRIANGLE_COUNT     12u

typedef struct {
	fixed_t x;
	fixed_t y;
	fixed_t z;
} vertex_t;

typedef struct {
	uint8_t a;
	uint8_t b;
	uint8_t c;
	uv_desc_t uv;
	uint8_t texid;
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
	{0, 2, 3, 0b011000, 0}, {0, 1, 2, 0b011110, 0},
	{5, 7, 6, 0b011000, 1}, {5, 4, 7, 0b011110, 1},
	{4, 3, 7, 0b011000, 2}, {4, 0, 3, 0b011110, 2},
	{1, 6, 2, 0b011000, 3}, {1, 5, 6, 0b011110, 3},
	{1, 4, 5, 0b011000, 4}, {1, 0, 4, 0b011110, 4},
	{6, 3, 2, 0b011000, 5}, {6, 7, 3, 0b011110, 5},
};

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

static void set_texids(texture_id_t texid) {
	for (tri_id_t triangle = 0; triangle < TRIANGLE_COUNT; triangle++) {
		set_texid(triangle, texid);
	}
}

static void cmd_upload_geometry(void) {
	for (uint32_t triangle = 0; triangle < TRIANGLE_COUNT; triangle++) {
		const triangle_t *tri = &cube_triangles[triangle];
		const uint8_t vertex_indices[3] = {
			tri->a, tri->b, tri->c
		};

		for (uint32_t vertex = 0; vertex < 3; vertex++) {
			const vertex_t *position = &cube_vertices[vertex_indices[vertex]];

			REG32(vertex_address(triangle, vertex, 0)) = position->x;
			REG32(vertex_address(triangle, vertex, 1)) = position->y;
			REG32(vertex_address(triangle, vertex, 2)) = position->z;
			REG32(vertex_address(triangle, vertex, 3)) = FIXED_ONE;
		}

		set_texid(triangle, tri->texid);
		set_uv_desc(triangle, tri->uv);
	}

	set_tri_count(TRIANGLE_COUNT);
}

int main(void) {
	matrix_t camera_matrix;
	vec3_t camera_eye;
	buf_id_t draw_color = 1u;
	buf_id_t draw_depth = 0u;
	uint8_t camera_phase = 0u;
	uint32_t frame_start;
	uint32_t frame = 0u;

	uint32_t init = 0u;

	if (ddr_init()) {
		printf("DDR initialization failed\n");
		//while (1);
	}

	cmd_upload_geometry();

	clear_buffers();

	enable_hdmi();

	frame_start = read_csr("mcycle");
	init = frame_start;
	while (1) {
		frame_start = read_csr("mcycle");
		uint32_t frameid = ((frame_start - init) / 2000000) % 54;

		memcpy_dma(TEXTURE_RAM0_BASE_ADDR, VIDEO_MEM_BASE + (frameid << 10), 1024);

		set_texids(0);

		make_camera_matrix(camera_matrix, camera_phase, camera_eye);
		write_camera_matrix(camera_matrix);
		render_frame(draw_color, draw_depth);

		set_hdmi_fbid(draw_color);

		frame++;

		update_fps_display(draw_color);

		// The next timing interval starts before printf above, so printing,
		// camera work, matrix writes, clears and rasterization are all included.
		advance_buffers(&draw_color, &draw_depth);

		if (frame % 3 == 0) camera_phase = (uint8_t)(camera_phase + 1u);
	}
}
