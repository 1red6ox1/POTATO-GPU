#include "graphics_pipeline.h"

void clear_color_buf(buf_id_t color_buffer) {
	REG32(FRAMECLEAR_DMA_FBID(0)) = color_buffer;
	REG32(FRAMECLEAR_DMA_CLEAR_COLOR(0)) = BACKGROUND_COLOR;
	REG32(FRAMECLEAR_DMA_MODE(0)) = 0u;
	REG32(FRAMECLEAR_DMA_STATUS(0)) = 1u;

	while (REG32(FRAMECLEAR_DMA_STATUS(0))) {
	}
}

void clear_depth_buf(buf_id_t depth_buffer) {
	REG32(FRAMECLEAR_DMA_FBID(0)) = depth_buffer;
	REG32(FRAMECLEAR_DMA_MODE(0)) = 1u;
	REG32(FRAMECLEAR_DMA_STATUS(0)) = 1u;

	while (REG32(FRAMECLEAR_DMA_STATUS(0))) {
	}
}

void clear_buffers() {
	for (buf_id_t buffer = 0; buffer < 4; buffer++) {
		clear_color_buf(buffer);
	}
	for (buf_id_t buffer = 0; buffer < 2; buffer++) {
		clear_depth_buf(buffer);
	}
}

void render_frame(
	buf_id_t color_buffer,
	buf_id_t depth_buffer
) {
	clear_color_buf(color_buffer);
	clear_depth_buf(depth_buffer);

	// STATUS is write-one-to-clear. Clear the previous completion before
	// launching the vertex processor's real triangles and completion marker.
	REG32(RASTERIZER_STATUS_STATUS(0)) =
		RASTERIZER_STATUS_STATUS_VALID_MASK;
	REG32(TRIANGLE_INPUT_FBID_COLOR(0)) = color_buffer;
	REG32(TRIANGLE_INPUT_FBID_DEPTH(0)) = depth_buffer;
	REG32(VERTEX_PROCESSOR_START_RENDER(0)) = 1u;

	while (!(REG32(RASTERIZER_STATUS_STATUS(0))
	         & RASTERIZER_STATUS_STATUS_VALID_MASK));
}

void write_camera_matrix(matrix_t matrix) {
	for (uint32_t row = 0; row < 4; row++) {
		for (uint32_t column = 0; column < 4; column++) {
			uint32_t index = row * 4u + column;

			REG32(VERTEX_CFG0_BASE_ADDR + (index << 2)) =
				(uint32_t)matrix[row][column];
		}
	}
}

void enable_hdmi() {
	REG32(HDMI_CTRL_FBID(0)) = 0u;
	REG32(HDMI_CTRL_CTRL(0)) = (1u << HDMI_CTRL_CTRL_PHY_ENABLE_LSB)
		| (1u << HDMI_CTRL_CTRL_FETCH_ENABLE_LSB);
}

void set_texid(tri_id_t tri, texture_id_t tex) {
	REG32(LOAD_TEXTURE0_BASE_ADDR + ((tri & TRIANGLE_ID_MASK) << 2)) = tex;
}

texture_id_t get_texid(tri_id_t tri) {
	return REG32(LOAD_TEXTURE0_BASE_ADDR + ((tri & TRIANGLE_ID_MASK) << 2));
}

void set_uv_desc(tri_id_t tri, uv_desc_t desc) {
	REG32(UV_RAM0_BASE_ADDR + ((tri & TRIANGLE_ID_MASK) << 2)) = desc;
}

uv_desc_t get_uv_desc(tri_id_t tri) {
	return REG32(UV_RAM0_BASE_ADDR + ((tri & TRIANGLE_ID_MASK) << 2));
}

void set_tri_count(uint32_t count) {
	// The register contains the last triangle ID, not the number of triangles.
	REG32(VERTEX_PROCESSOR_TRIANGLE_COUNT(0)) = count > 0 ? count - 1 : 0;
}

uint32_t get_tri_count() {
	return REG32(VERTEX_PROCESSOR_TRIANGLE_COUNT(0)) + 1;
}

void set_hdmi_fbid(buf_id_t buf) {
	REG32(HDMI_CTRL_FBID(0)) = buf;
}

void advance_buffers(buf_id_t *color, buf_id_t *depth) {
	*color = (buf_id_t)((*color + 1u) % 4);
	*depth = (buf_id_t)((*depth + 1u) % 2);
}

static void _flush_ddr_llc() {
	volatile uint8_t *x = (uint8_t *)0x90000000;
	for ( ; x < (uint8_t*)0x90004000; x += 32) {
		*x;
	}
}

static uint32_t last_frame = 0;
static char fps_display[20];

void update_fps_display(buf_id_t fbid) {
	uint32_t cycle = read_csr("mcycle");
	uint32_t frame_cycles = cycle - last_frame;
	last_frame = cycle;

	uint32_t fps_x10 = (CPU_CLOCK_HZ * 10) / frame_cycles;
	sprintf(fps_display, "FPS: %u.%u", fps_x10 / 10, fps_x10 % 10);
	write_string(fbid, 0, 0, fps_display);
	_flush_ddr_llc();
}
