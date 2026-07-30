#include <stdint.h>
#include <rvlab.h>
#include <stdio.h>

typedef struct {
	int16_t x;
	int16_t y;
	uint16_t z;
	int32_t uq;
	int32_t vq;
	int32_t q;
} vertex_t;

static void clear_buffer(void) {
	REG32(FRAMECLEAR_DMA_FBID(0)) = 0u;
	REG32(FRAMECLEAR_DMA_CLEAR_COLOR(0)) = 0x11111u;
	REG32(FRAMECLEAR_DMA_MODE(0)) = 0u;
	REG32(FRAMECLEAR_DMA_STATUS(0)) = 1u;
	while (REG32(FRAMECLEAR_DMA_STATUS(0)));

	REG32(FRAMECLEAR_DMA_FBID(0)) = 0u;
	REG32(FRAMECLEAR_DMA_MODE(0)) = 1u;
	REG32(FRAMECLEAR_DMA_STATUS(0)) = 1u;
	while (REG32(FRAMECLEAR_DMA_STATUS(0)));
}

static void load_texture(uint32_t texture_id) {
	REG32(PALETTE_RAM0_BASE_ADDR + 1u * 4u) = 0x00e02020u;
	REG32(PALETTE_RAM0_BASE_ADDR + 2u * 4u) = 0x002080e0u;

	for (uint32_t v = 0; v < 32u; v++) {
		for (uint32_t u_word = 0; u_word < 8u; u_word++) {
			uint32_t palette_id = ((v >> 2) ^ u_word) & 1u ? 1u : 2u;
			REG32(TEXTURE_RAM0_BASE_ADDR + (texture_id << 10)
				+ (v << 5) + (u_word << 2)) = palette_id * 0x01010101u;
		}
	}
}

static void enable_hdmi(void) {
	REG32(HDMI_CTRL_FBID(0)) = 0u;
	REG32(HDMI_CTRL_CTRL(0)) = (1u << HDMI_CTRL_CTRL_PHY_ENABLE_LSB) | (1u << HDMI_CTRL_CTRL_FETCH_ENABLE_LSB);
}

static void clean_status(void) {
	REG32(RASTERIZER_STATUS_STATUS(0)) = RASTERIZER_STATUS_STATUS_VALID_MASK;
}

static int rasterization_completed(void) {
	return REG32(RASTERIZER_STATUS_STATUS(0)) & RASTERIZER_STATUS_STATUS_VALID_MASK;
}

static void draw_triangle(uint32_t id, const vertex_t *a,
	const vertex_t *b, const vertex_t *c) {
	while (REG32(TRIANGLE_INPUT_STATUS(0)) & TRIANGLE_INPUT_STATUS_VALID_MASK);

	REG32(TRIANGLE_INPUT_FBID_COLOR(0)) = 0u;
	REG32(TRIANGLE_INPUT_FBID_DEPTH(0)) = 0u;
	REG32(TRIANGLE_INPUT_TRIANGLE_ID(0)) = id;
	REG32(TRIANGLE_INPUT_AX(0)) = (uint16_t)a->x;
	REG32(TRIANGLE_INPUT_AY(0)) = (uint16_t)a->y;
	REG32(TRIANGLE_INPUT_AZ(0)) = a->z;
	REG32(TRIANGLE_INPUT_AUQ(0)) = (uint32_t)a->uq;
	REG32(TRIANGLE_INPUT_AVQ(0)) = (uint32_t)a->vq;
	REG32(TRIANGLE_INPUT_AQ(0)) = (uint32_t)a->q;
	REG32(TRIANGLE_INPUT_BX(0)) = (uint16_t)b->x;
	REG32(TRIANGLE_INPUT_BY(0)) = (uint16_t)b->y;
	REG32(TRIANGLE_INPUT_BZ(0)) = b->z;
	REG32(TRIANGLE_INPUT_BUQ(0)) = (uint32_t)b->uq;
	REG32(TRIANGLE_INPUT_BVQ(0)) = (uint32_t)b->vq;
	REG32(TRIANGLE_INPUT_BQ(0)) = (uint32_t)b->q;
	REG32(TRIANGLE_INPUT_CX(0)) = (uint16_t)c->x;
	REG32(TRIANGLE_INPUT_CY(0)) = (uint16_t)c->y;
	REG32(TRIANGLE_INPUT_CZ(0)) = c->z;
	REG32(TRIANGLE_INPUT_CUQ(0)) = (uint32_t)c->uq;
	REG32(TRIANGLE_INPUT_CVQ(0)) = (uint32_t)c->vq;
	REG32(TRIANGLE_INPUT_CQ(0)) = (uint32_t)c->q;
	REG32(TRIANGLE_INPUT_SUBMIT(0)) = TRIANGLE_INPUT_SUBMIT_VALID_MASK;
}

int main(void) {
	static const vertex_t first_a = { 360,  80, 0x1800, 0, 0, 1 << 24 };
	static const vertex_t first_b = {1000, 650, 0x2600, 1 << 24, 0, 1 << 24 };
	static const vertex_t first_c = { 120, 600, 0x2100, 0, 1 << 24, 1 << 24 };
	static const vertex_t second_a = { 880, 180, 0x0, 0, 0, 1 << 24 };
	static const vertex_t second_b = {1100, 700, 0x0, 1 << 24, 0, 1 << 24 };
	static const vertex_t second_c = { 440, 410, 0x4100, 0, 1 << 24, 1 << 24 };
	static const vertex_t third_a = { 820,  20, 0x5800, 0, 0, 1 << 24 };
	static const vertex_t third_b = {1150,  50, 0x6800, 1 << 24, 0, 1 << 24 };
	static const vertex_t third_c = {1030, 300, 0x6100, 0, 1 << 24, 1 << 24 };
	static const vertex_t fourth_a = {-160, 300, 0x4a00, 0, 0, 1 << 24 };
	static const vertex_t fourth_b = { 200,-100, 0x5300, 1 << 24, 0, 1 << 24 };
	static const vertex_t fourth_c = { 300, 120, 0x4d00, 0, 1 << 24, 1 << 24 };
	if (ddr_init()) {
		return 1;
	}
	clear_buffer();
	load_texture(0u);

	REG32(LOAD_TEXTURE0_BASE_ADDR + 0u * 4u) = 0u;
	REG32(LOAD_TEXTURE0_BASE_ADDR + 1u * 4u) = 0u;
	REG32(LOAD_TEXTURE0_BASE_ADDR + 2u * 4u) = 0u;
	REG32(LOAD_TEXTURE0_BASE_ADDR + 3u * 4u) = 0u;
	REG32(LOAD_TEXTURE0_BASE_ADDR + RASTERIZER_COMPLETION_TRIANGLE_ID * 4u) = 0u;
	clean_status();

	draw_triangle(0u, &first_a, &first_b, &first_c);
	draw_triangle(1u, &second_a, &second_b, &second_c);
	draw_triangle(2u, &third_a, &third_b, &third_c);
	draw_triangle(3u, &fourth_a, &fourth_b, &fourth_c);
	draw_triangle(RASTERIZER_COMPLETION_TRIANGLE_ID, &first_a, &first_b, &first_c);

	while (!rasterization_completed());

	enable_hdmi();

	while (1);
}
