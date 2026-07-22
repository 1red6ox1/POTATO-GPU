/* SPDX-License-Identifier: CC0-1.0
 * SPDX-FileCopyrightText: 2026 RVLab Contributors
 */

#include <stdint.h>
#include <stdio.h>
#include <rvlab.h>

#include "graphics_math.h"
#include "memcpy.h"
#include "graphics_pipeline.h"
#include "geometry.h"
#include "dram_addrmap.h"

#define TRIANGLE_COUNT 2048u

static triangle_t cube_triangles[TRIANGLE_COUNT];

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

	uint32_t tricount = REG32(MESH_SIZE_ADDR);

	printf("Loading %d triangles...\n", tricount);

	//make_cube(cube_triangles, 4, &tricount);
	write_geometry((triangle_t *)MESH_BASE, tricount);

	clear_buffers();

	enable_hdmi();

	set_texture_checkered(0, 0, 1);
	set_palette_color(0, 5, 5, 5);
	set_palette_color(1, 200, 200, 200);

	frame_start = read_csr("mcycle");
	init = frame_start;
	while (1) {
		frame_start = read_csr("mcycle");
		uint32_t frameid = 0;//((frame_start - init) / 2000000) % 54;

		//memcpy_dma(TEXTURE_RAM0_BASE_ADDR, VIDEO_MEM_BASE + (frameid << 14), 16384);

		make_camera_matrix(camera_matrix, camera_phase, camera_eye);
		write_camera_matrix(camera_matrix);
		render_frame(draw_color, draw_depth);

		set_hdmi_fbid(draw_color);

		frame++;

		update_fps_display(draw_color);
		advance_buffers(&draw_color, &draw_depth);
		if (frame % 3 == 0) camera_phase = (uint8_t)(camera_phase + 1u);
	}
}
