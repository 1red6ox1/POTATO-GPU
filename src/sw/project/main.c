/* SPDX-License-Identifier: CC0-1.0
 * SPDX-FileCopyrightText: 2026 RVLab Contributors
 */

#include <stdint.h>
#include <stdio.h>
#include <rvlab.h>

#include "graphics_math.h"
#include "camera.h"
#include "memcpy.h"
#include "graphics_pipeline.h"
#include "geometry.h"
#include "dram_addrmap.h"

#define TRIANGLE_COUNT 2048u
#define CAM_LERP_SPEED 0x00003000

static triangle_t cube_triangles[TRIANGLE_COUNT];

int main(void) {
	matrix_t proj_matrix;
	matrix_t camera_matrix;
	camera_t camera, smooth_camera;
	init_camera(&camera);
	init_camera(&smooth_camera);
	get_default_proj_mat(proj_matrix);

	camera.pos[2] = 0x00040000;
	smooth_camera.pos[2] = 0x00040000;

	camera.azimuth = 0x00800000;
	smooth_camera.azimuth = 0x00800000;

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

	int state = 2; // 0 = image, 1 = monke, 2 = bad apple animation

	printf("Starting main loop!\n");

	uint32_t animation_frame_cycles = REG32(FRAME_CYC_ADDR);
	uint32_t total_animation_frames = REG32(ANIM_FCNT_ADDR);

	write_geometry(cube_triangles, cube_triangle_count);
	load_palette((uint32_t *)PALETTE_BASE);

	ibuf_getc();

	frame_start = read_csr("mcycle");
	init = frame_start;
	while (1) {
		frame_start = read_csr("mcycle");
		uint32_t frameid = ((frame_start - init) / animation_frame_cycles) % total_animation_frames;

		// Update smooth camera to track camera via linear interpolation
		smooth_camera.pos[0] = fixed_lerp(smooth_camera.pos[0], camera.pos[0], CAM_LERP_SPEED);
		smooth_camera.pos[1] = fixed_lerp(smooth_camera.pos[1], camera.pos[1], CAM_LERP_SPEED);
		smooth_camera.pos[2] = fixed_lerp(smooth_camera.pos[2], camera.pos[2], CAM_LERP_SPEED);
		smooth_camera.azimuth = fixed_lerp(smooth_camera.azimuth, camera.azimuth, CAM_LERP_SPEED);
		smooth_camera.elevation = fixed_lerp(smooth_camera.elevation, camera.elevation, CAM_LERP_SPEED);

		switch (state) {
			case 0: {
				load_slide_to_fb(draw_color);
				break;
			}
			case 2:
				load_textures(0, (uint32_t *)(VIDEO_BASE + (frameid << 14)), 16);
			case 1: {
				get_camera_matrix(camera_matrix, &smooth_camera, proj_matrix);
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

		bool is_switching_scene = false;

		// Process inputs
		char selected_char;
		while ((selected_char = ibuf_getc_nonblocking())) {
			switch (selected_char) {
				case 'e': {
					state = (state + 1) % 3;
					is_switching_scene = true;
					break;
				}
				case 'q': {
					state = (state + 2) % 3;
					is_switching_scene = true;
					break;
				}
				case 'j': {
					camera.azimuth += 0x00040000;
					break;
				}
				case 'l': {
					camera.azimuth -= 0x00040000;
					break;
				}
				case 'i': {
					camera.elevation += 0x00020000;
					break;
				}
				case 'k': {
					camera.elevation -= 0x00020000;
					break;
				}
				case 'w': {
					fixed_t fwd_x = fixed_sin(camera.azimuth);
					fixed_t fwd_z = fixed_cos(camera.azimuth);
					camera.pos[0] += fixed_mul(fwd_x, CAMERA_MOVE_SPEED);
					camera.pos[2] += fixed_mul(fwd_z, CAMERA_MOVE_SPEED);
					break;
				}
				case 's': {
					fixed_t fwd_x = fixed_sin(camera.azimuth);
					fixed_t fwd_z = fixed_cos(camera.azimuth);
					camera.pos[0] -= fixed_mul(fwd_x, CAMERA_MOVE_SPEED);
					camera.pos[2] -= fixed_mul(fwd_z, CAMERA_MOVE_SPEED);
					break;
				}
				case 'd': {
					fixed_t right_x = fixed_cos(camera.azimuth);
					fixed_t right_z = -fixed_sin(camera.azimuth);
					camera.pos[0] -= fixed_mul(right_x, CAMERA_MOVE_SPEED);
					camera.pos[2] -= fixed_mul(right_z, CAMERA_MOVE_SPEED);
					break;
				}
				case 'a': {
					fixed_t right_x = fixed_cos(camera.azimuth);
					fixed_t right_z = -fixed_sin(camera.azimuth);
					camera.pos[0] += fixed_mul(right_x, CAMERA_MOVE_SPEED);
					camera.pos[2] += fixed_mul(right_z, CAMERA_MOVE_SPEED);
					break;
				}
			    case ' ': {
			    	camera.pos[1] += CAMERA_MOVE_SPEED;
			    	break;
			    }
			    case 'c': {
			    	camera.pos[1] -= CAMERA_MOVE_SPEED;
			    	break;
			    }
				default: ;
			}
		}

		if (is_switching_scene) {
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
					init = frame_start;
					write_geometry(cube_triangles, cube_triangle_count);
					load_palette((uint32_t *)PALETTE_BASE);
					break;
				default: ;
			}
		}
	}

	return 0;
}
