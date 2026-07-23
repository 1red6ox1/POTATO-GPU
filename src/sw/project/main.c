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

	uint32_t cube_triangle_count;

	make_cube(cube_triangles, 4, &cube_triangle_count);
	clear_buffers();
	enable_hdmi();

	int state = 0; // 0 = image, 1 = monke, 2 = bad apple animation

	printf("Starting main loop!\n");

	uint32_t animation_frame_cycles = 2500000;
	uint32_t total_animation_frames = 3110;

	frame_start = read_csr("mcycle");
	init = frame_start;
	while (1) {
		frame_start = read_csr("mcycle");
		uint32_t frameid = ((frame_start - init) / animation_frame_cycles) % total_animation_frames;

		switch (state) {
			case 0: {
				load_slide_to_fb(draw_color);
				break;
			}
			case 2:
				load_textures(0, (uint32_t *)(VIDEO_BASE + (frameid << 14)), 16);
			case 1: {
				make_camera_matrix(camera_matrix, camera_phase, camera_eye);
				write_camera_matrix(camera_matrix);
				render_frame(draw_color, draw_depth);
				update_fps_display(draw_color);
				break;
			}
			default: ;
		}

		set_hdmi_fbid(draw_color);

		frame++;

		advance_buffers(&draw_color, &draw_depth);
		if (frame % 3 == 0) camera_phase = (uint8_t)(camera_phase + 1u);

		if (ibuf_getc_nonblocking() == ' ') {
			state = (state + 1) % 3;
			switch (state) {
				case 1: {
					uint32_t tricount = REG32(MESH_SIZE_ADDR);
					write_geometry((triangle_t *)MESH_BASE, tricount);
					set_texture_checkered(0, 0, 1);
					set_palette_color(0, 5, 5, 5);
					set_palette_color(1, 200, 200, 200);
					break;
				}
				case 2:
					write_geometry(cube_triangles, cube_triangle_count);
					load_palette((uint32_t *)PALETTE_BASE);
					break;
				default: ;
			}
		}
	}

	return 0;
}
