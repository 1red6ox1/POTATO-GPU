/* SPDX-License-Identifier: CC0-1.0
 * SPDX-FileCopyrightText: 2024 RVLab Contributors
 */

#include <stdint.h>
#include <rvlab.h>
#include "graphics_math.h"

#define SCREEN_WIDTH  1920
#define SCREEN_HEIGHT 1080

#define Q16_ONE 65536

#define CUBE_SIZE     150
#define CAMERA_Z      760
#define CAMERA_NEAR   10
#define CAMERA_FAR    1200

#define DISPLAY_SWITCH_CYCLES 1000000u
#define HW_RENDER_WAIT_CYCLES  4000000u

typedef struct {
    int16_t x;
    int16_t y;
    int16_t z;
} cube_vertex_t;

typedef struct {
    uint8_t a;
    uint8_t b;
    uint8_t c;
} triangle_index_t;

// The vertex-post adapter currently assigns barycentric debug colors after
// projection, so the CPU only has to provide object-space positions here.
static const cube_vertex_t cube_vertices[8] = {
    {-CUBE_SIZE, -CUBE_SIZE, -CUBE_SIZE},
    { CUBE_SIZE, -CUBE_SIZE, -CUBE_SIZE},
    { CUBE_SIZE,  CUBE_SIZE, -CUBE_SIZE},
    {-CUBE_SIZE,  CUBE_SIZE, -CUBE_SIZE},
    {-CUBE_SIZE, -CUBE_SIZE,  CUBE_SIZE},
    { CUBE_SIZE, -CUBE_SIZE,  CUBE_SIZE},
    { CUBE_SIZE,  CUBE_SIZE,  CUBE_SIZE},
    {-CUBE_SIZE,  CUBE_SIZE,  CUBE_SIZE},
};

// Two triangles for every cube face. Both front and back faces are submitted;
// the hardware depth buffer decides which fragments are visible.
static const triangle_index_t cube_triangles[12] = {
    {0, 1, 2}, {0, 2, 3},
    {4, 6, 5}, {4, 7, 6},
    {0, 3, 7}, {0, 7, 4},
    {1, 5, 6}, {1, 6, 2},
    {0, 4, 5}, {0, 5, 1},
    {3, 2, 6}, {3, 6, 7},
};

static void wait_cycles(uint32_t cycles) {
    uint32_t start = (uint32_t)read_csr("mcycle");

    while ((uint32_t)((uint32_t)read_csr("mcycle") - start) < cycles);
}

static void cmd_clear_buffers(
    uint8_t fbid,
    uint8_t red,
    uint8_t green,
    uint8_t blue
) {
    REG32(FRAMECLEAR_DMA_FBID(0)) = fbid;
    REG32(FRAMECLEAR_DMA_CLEAR_COLOR(0)) =
        ((uint32_t)red << 16) | ((uint32_t)green << 8) | blue;

    // Clear the planar RGB framebuffer.
    REG32(FRAMECLEAR_DMA_MODE(0)) = 0;
    REG32(FRAMECLEAR_DMA_STATUS(0)) = 1;
    while (REG32(FRAMECLEAR_DMA_STATUS(0)));

    // Clear depth to zero. The rasterizer uses larger depth as closer.
    REG32(FRAMECLEAR_DMA_MODE(0)) = 1;
    REG32(FRAMECLEAR_DMA_STATUS(0)) = 1;
    while (REG32(FRAMECLEAR_DMA_STATUS(0)));
}

// Smooth integer sine approximation. Input phase 0..255 represents 0..2*pi;
// output is signed Q2.14. This avoids requiring libm on the bare-metal CPU.
static int32_t sin_q14(uint8_t phase) {
    uint32_t half_phase = phase & 0x7fu;
    uint32_t x = half_phase <= 64u ? half_phase : 128u - half_phase;
    int32_t value = (int32_t)(x * (128u - x) * 4u);

    return (phase & 0x80u) ? -value : value;
}

static int32_t cos_q14(uint8_t phase) {
    return sin_q14((uint8_t)(phase + 64u));
}

static fixed_t int_to_q16(int32_t value) {
    return value * Q16_ONE;
}

static fixed_t scaled_q16_from_q14(int32_t value_q14, int32_t scale) {
    return (fixed_t)(((int64_t)value_q14 * scale * Q16_ONE) >> 14);
}

static uint32_t vertex_vec_addr(
    uint32_t triangle,
    uint32_t vertex,
    uint32_t lane
) {
    return VERTEX_DATA0_BASE_ADDR | (triangle << 6) | (vertex << 4) | (lane << 2);
}

static uint8_t triangle_vertex_index(uint32_t triangle, uint32_t vertex) {
    if (vertex == 0) return cube_triangles[triangle].a;
    if (vertex == 1) return cube_triangles[triangle].b;
    return cube_triangles[triangle].c;
}

static void cmd_load_cube_vertices(void) {
    for (uint32_t triangle = 0; triangle < 12; triangle++) {
        for (uint32_t vertex = 0; vertex < 3; vertex++) {
            const cube_vertex_t *source = &cube_vertices[
                triangle_vertex_index(triangle, vertex)
            ];

            REG32(vertex_vec_addr(triangle, vertex, 0)) =
                (uint32_t)int_to_q16(source->x);
            REG32(vertex_vec_addr(triangle, vertex, 1)) =
                (uint32_t)int_to_q16(source->y);
            REG32(vertex_vec_addr(triangle, vertex, 2)) =
                (uint32_t)int_to_q16(source->z);
            REG32(vertex_vec_addr(triangle, vertex, 3)) =
                (uint32_t)Q16_ONE;
        }
    }
}

static void cmd_write_vertex_matrix(uint8_t phase_x, uint8_t phase_y) {
    vec3_t eye = {
        scaled_q16_from_q14(sin_q14(phase_y), CAMERA_Z),
        scaled_q16_from_q14(sin_q14(phase_x), CUBE_SIZE),
        scaled_q16_from_q14(cos_q14(phase_y), CAMERA_Z),
    };
    vec3_t center = {
        int_to_q16(0),
        int_to_q16(0),
        int_to_q16(0),
    };
    vec3_t up = {
        int_to_q16(0),
        int_to_q16(1),
        int_to_q16(0),
    };
    matrix_t view;
    matrix_t projection;
    matrix_t view_projection;
    fixed_t near = int_to_q16(CAMERA_NEAR);
    fixed_t far = int_to_q16(CAMERA_FAR);
    fixed_t far_minus_near = far - near;

    lookat_mat(view, eye, center, up);
    persp_proj_mat(
        projection,
        60,
        fixed_div(int_to_q16(SCREEN_HEIGHT), int_to_q16(SCREEN_WIDTH)),
        far,
        near
    );

    // The rasterizer depth test treats larger depth values as closer, while
    // persp_proj_mat creates the usual near-low/far-high OpenGL Z mapping.
    // Keep its X/Y/W projection and replace Z with a reversed-depth mapping.
    projection[2][2] = fixed_div(near, far_minus_near);
    projection[2][3] = fixed_div(fixed_mul(far, near), far_minus_near);

    mat_mat_mul(view_projection, projection, view);

    for (uint32_t row = 0; row < 4; row++) {
        for (uint32_t column = 0; column < 4; column++) {
            REG32(VERTEX_CFG0_BASE_ADDR + ((row * 4 + column) << 2)) =
                (uint32_t)view_projection[row][column];
        }
    }
}

static void cmd_start_cube_hw(uint8_t phase_x, uint8_t phase_y) {
    cmd_write_vertex_matrix(phase_x, phase_y);
    REG32(VERTEX_PROCESSOR_TRIANGLE_COUNT(0)) = 11;
    REG32(VERTEX_PROCESSOR_START_RENDER(0)) = 1;
}

int main(void) {
    uint8_t phase_x = 0;
    uint8_t phase_y = 0;

    if (ddr_init()) {
        while (1);
    }

    // The vertex-post adapter currently emits fixed framebuffer ID 0.
    cmd_load_cube_vertices();
    cmd_clear_buffers(0, 2, 4, 12);
    cmd_start_cube_hw(phase_x, phase_y);
    wait_cycles(HW_RENDER_WAIT_CYCLES);

    REG32(HDMI_CTRL_FBID(0)) = 0;
    REG32(HDMI_CTRL_CTRL(0)) =
        (1u << HDMI_CTRL_CTRL_PHY_ENABLE_LSB)
        | (1u << HDMI_CTRL_CTRL_FETCH_ENABLE_LSB);

    while (1) {
        wait_cycles(DISPLAY_SWITCH_CYCLES);

        phase_x = (uint8_t)(phase_x + 2u);
        phase_y = (uint8_t)(phase_y + 3u);

        cmd_clear_buffers(0, 2, 4, 12);
        cmd_start_cube_hw(phase_x, phase_y);
        wait_cycles(HW_RENDER_WAIT_CYCLES);
    }
}
