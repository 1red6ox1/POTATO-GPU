/* SPDX-License-Identifier: CC0-1.0
 * SPDX-FileCopyrightText: 2026 RVLab Contributors
 */

#include <stdint.h>
#include <stdio.h>
#include <rvlab.h>

#define Q_ONE (1u << 24)

#define COLOR_FBID 0u
#define DEPTH_FBID 2u
#define TEST_DEPTH 0xc000u

#define TRIANGLE_ID_MASK      0x7ffu
#define HW_RENDER_WAIT_CYCLES 4000000u

#define TEXTURE_COUNT 30u
#define GRID_COLUMNS  6u

#define PANEL_X_START 35u
#define PANEL_Y_START 35u
#define PANEL_WIDTH   300u
#define PANEL_HEIGHT  190u
#define PANEL_X_STEP  310u
#define PANEL_Y_STEP  205u

typedef struct {
	int16_t x;
	int16_t y;
	uint16_t z;
	uint32_t uq;
	uint32_t vq;
	uint32_t q;
} screen_vertex_t;

static uint32_t next_triangle_id = 1u;

static void wait_cycles(uint32_t cycles) {
	uint32_t start = (uint32_t)read_csr("mcycle");

	while ((uint32_t)((uint32_t)read_csr("mcycle") - start) < cycles) {
	}
}

static void cmd_clear_buffers(void) {
	REG32(FRAMECLEAR_DMA_CLEAR_COLOR(0)) = 0x02040cu;

	REG32(FRAMECLEAR_DMA_FBID(0)) = COLOR_FBID;
	REG32(FRAMECLEAR_DMA_MODE(0)) = 0u;
	REG32(FRAMECLEAR_DMA_STATUS(0)) = 1u;
	while (REG32(FRAMECLEAR_DMA_STATUS(0))) {
	}

	REG32(FRAMECLEAR_DMA_FBID(0)) = DEPTH_FBID;
	REG32(FRAMECLEAR_DMA_MODE(0)) = 1u;
	REG32(FRAMECLEAR_DMA_STATUS(0)) = 1u;
	while (REG32(FRAMECLEAR_DMA_STATUS(0))) {
	}
}

static void cmd_enable_hdmi(void) {
	REG32(HDMI_CTRL_FBID(0)) = COLOR_FBID;
	REG32(HDMI_CTRL_CTRL(0)) =
		(1u << HDMI_CTRL_CTRL_PHY_ENABLE_LSB)
		| (1u << HDMI_CTRL_CTRL_FETCH_ENABLE_LSB);
}

static void cmd_set_triangle_texture(
	uint32_t triangle_id,
	uint8_t texture_id
) {
	REG32(LOAD_TEXTURE0_BASE_ADDR
	      + ((triangle_id & TRIANGLE_ID_MASK) << 2)) = texture_id;
}

static void cmd_submit_triangle(
	uint32_t triangle_id,
	screen_vertex_t a,
	screen_vertex_t b,
	screen_vertex_t c
) {
	while (REG32(TRIANGLE_INPUT_STATUS(0))
	       & TRIANGLE_INPUT_STATUS_VALID_MASK) {
	}

	REG32(TRIANGLE_INPUT_TRIANGLE_ID(0)) = triangle_id;
	REG32(TRIANGLE_INPUT_FBID_COLOR(0)) = COLOR_FBID;
	REG32(TRIANGLE_INPUT_FBID_DEPTH(0)) = DEPTH_FBID;

	REG32(TRIANGLE_INPUT_AX(0)) = (uint16_t)a.x;
	REG32(TRIANGLE_INPUT_AY(0)) = (uint16_t)a.y;
	REG32(TRIANGLE_INPUT_AZ(0)) = a.z;
	REG32(TRIANGLE_INPUT_AUQ(0)) = a.uq;
	REG32(TRIANGLE_INPUT_AVQ(0)) = a.vq;
	REG32(TRIANGLE_INPUT_AQ(0)) = a.q;

	REG32(TRIANGLE_INPUT_BX(0)) = (uint16_t)b.x;
	REG32(TRIANGLE_INPUT_BY(0)) = (uint16_t)b.y;
	REG32(TRIANGLE_INPUT_BZ(0)) = b.z;
	REG32(TRIANGLE_INPUT_BUQ(0)) = b.uq;
	REG32(TRIANGLE_INPUT_BVQ(0)) = b.vq;
	REG32(TRIANGLE_INPUT_BQ(0)) = b.q;

	REG32(TRIANGLE_INPUT_CX(0)) = (uint16_t)c.x;
	REG32(TRIANGLE_INPUT_CY(0)) = (uint16_t)c.y;
	REG32(TRIANGLE_INPUT_CZ(0)) = c.z;
	REG32(TRIANGLE_INPUT_CUQ(0)) = c.uq;
	REG32(TRIANGLE_INPUT_CVQ(0)) = c.vq;
	REG32(TRIANGLE_INPUT_CQ(0)) = c.q;

	REG32(TRIANGLE_INPUT_SUBMIT(0)) = 1u;
}

static screen_vertex_t make_vertex(
	int16_t x,
	int16_t y,
	uint32_t u,
	uint32_t v
) {
	screen_vertex_t vertex;

	vertex.x = x;
	vertex.y = y;
	vertex.z = TEST_DEPTH;
	vertex.uq = u;
	vertex.vq = v;
	vertex.q = Q_ONE;

	return vertex;
}

static void cmd_submit_textured_triangle(
	uint8_t texture_id,
	screen_vertex_t a,
	screen_vertex_t b,
	screen_vertex_t c
) {
	uint32_t triangle_id = next_triangle_id;

	next_triangle_id = (next_triangle_id + 1u) & TRIANGLE_ID_MASK;
	cmd_set_triangle_texture(triangle_id, texture_id);
	cmd_submit_triangle(triangle_id, a, b, c);
}

static void cmd_draw_textured_quad(
	int16_t x0,
	int16_t y0,
	int16_t x1,
	int16_t y1,
	uint32_t u0,
	uint32_t v0,
	uint32_t u1,
	uint32_t v1,
	uint8_t texture_id
) {
	screen_vertex_t top_left = make_vertex(x0, y0, u0, v0);
	screen_vertex_t top_right = make_vertex(x1, y0, u1, v0);
	screen_vertex_t bottom_right = make_vertex(x1, y1, u1, v1);
	screen_vertex_t bottom_left = make_vertex(x0, y1, u0, v1);

	cmd_submit_textured_triangle(
		texture_id, top_left, top_right, bottom_right
	);
	cmd_submit_textured_triangle(
		texture_id, top_left, bottom_right, bottom_left
	);
}

static void cmd_wait_for_triangles(
	uint32_t rasterized_count,
	uint32_t triangle_count
) {
	while ((uint32_t)(REG32(TRIANGLE_INPUT_RASTERIZED_COUNT(0))
	                  - rasterized_count) < triangle_count) {
	}

	// Rasterized completion marks the last generated tile. Allow the worker,
	// writer and outstanding DDR requests to drain before HDMI starts reading.
	wait_cycles(HW_RENDER_WAIT_CYCLES);
}

int main(void) {
	uint32_t rasterized_count;

	if (ddr_init()) {
		printf("DDR initialization failed\n");
		while (1) {
		}
	}

	printf("\n=== 30 TEXTURE GRID TEST ===\n");
	printf("6 columns x 5 rows, one panel per texture\n");
	printf("30 quads, 60 triangles, 32 texels in parallel\n");
	printf("Texture IDs increase left-to-right, then top-to-bottom\n");
	printf("Texture 0 is brick; textures 1-29 use generated data\n");

	cmd_clear_buffers();
	rasterized_count = REG32(TRIANGLE_INPUT_RASTERIZED_COUNT(0));

	for (uint32_t texture_id = 0; texture_id < TEXTURE_COUNT; texture_id++) {
		uint32_t column = texture_id % GRID_COLUMNS;
		uint32_t row = texture_id / GRID_COLUMNS;
		int16_t x0 = (int16_t)(PANEL_X_START + column * PANEL_X_STEP);
		int16_t y0 = (int16_t)(PANEL_Y_START + row * PANEL_Y_STEP);
		int16_t x1 = (int16_t)(x0 + PANEL_WIDTH);
		int16_t y1 = (int16_t)(y0 + PANEL_HEIGHT);

		cmd_draw_textured_quad(
			x0, y0, x1, y1,
			0u, 0u, Q_ONE, Q_ONE,
			(uint8_t)texture_id
		);
	}

	cmd_wait_for_triangles(rasterized_count, 2u * TEXTURE_COUNT);
	cmd_enable_hdmi();

	printf("Texture test rendered to HDMI framebuffer %u\n", COLOR_FBID);
	printf("Triangle-to-texture table writes completed\n");

	while (1) {
	}
}
