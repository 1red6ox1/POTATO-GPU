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

static uint32_t *vertex_address (tri_id_t triangle, uint32_t vertex, uint32_t lane) {
	return (uint32_t *)(VERTEX_DATA0_BASE_ADDR
		| (triangle << 6)
		| (vertex << 4)
		| (lane << 2));
}

void write_geometry(triangle_t *triangles, uint32_t count) {
	for (uint32_t triangle = 0; triangle < count; triangle++) {
		const triangle_t *tri = &triangles[triangle];
		const vertex_t *positions[3] = { &tri->a, &tri->b, &tri->c };
		for (uint32_t vertex = 0; vertex < 3; vertex++) {
			const vertex_t *position = positions[vertex];
			REG32(vertex_address(triangle, vertex, 0)) = position->x;
			REG32(vertex_address(triangle, vertex, 1)) = position->y;
			REG32(vertex_address(triangle, vertex, 2)) = position->z;
			REG32(vertex_address(triangle, vertex, 3)) = 0x00010000;
		}
		set_texid(triangle, tri->texid);
		set_uv_desc(triangle, tri->uv);
	}
	set_tri_count(count);
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

void set_texture(texture_id_t texid, palette_id_t palid) {
	for (int v = 0; v < 32; v++) {
		for (int ub = 0; ub < 8; ub++) {
			REG32(TEXTURE_RAM0_BASE_ADDR + (texid << 10) + (v << 5) + (ub << 2)) = palid * 0x01010101;
		}
	}
}

void set_texture_checkered(texture_id_t texid, palette_id_t palid1, palette_id_t palid2) {
	for (int v = 0; v < 32; v++) {
		for (int ub = 0; ub < 8; ub++) {
			if ((v >> 2) % 2) {
				REG32(TEXTURE_RAM0_BASE_ADDR + (texid << 10) + (v << 5) + (ub << 2)) = ((ub & 1) ? palid1 : palid2) * 0x01010101;
            } else {
            	REG32(TEXTURE_RAM0_BASE_ADDR + (texid << 10) + (v << 5) + (ub << 2)) = ((ub & 1) ? palid2 : palid1) * 0x01010101;
            }
		}
	}
}

void set_palette_color(palette_id_t palid, uint8_t r, uint8_t g, uint8_t b) {
	REG32(PALETTE_RAM0_BASE_ADDR + (palid << 2)) = (r << 16) | (g << 8) | b;
}

void load_slide_to_fb(buf_id_t fbid) {
	memcpy_dma((uint32_t *)(VIDEO_BASE + (fbid << 24)), (uint32_t *)SLIDE_BASE, 8192 * 1080);
}
