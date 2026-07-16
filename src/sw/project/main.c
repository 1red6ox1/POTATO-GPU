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

#define INITIAL_PHASE 16u
#define DISPLAY_SWITCH_CYCLES 1000000u
#define HW_RENDER_WAIT_CYCLES  4000000u

#define BUFFER_A 0u
#define BUFFER_B 1u

#define TRI2D_FBID_COLOR 0x08u
#define TRI2D_FBID_DEPTH 0x0cu

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

static void cmd_enable_hdmi(uint8_t fbid) {
    REG32(HDMI_CTRL_FBID(0)) = fbid;
    REG32(HDMI_CTRL_CTRL(0)) =
        (1u << HDMI_CTRL_CTRL_PHY_ENABLE_LSB)
        | (1u << HDMI_CTRL_CTRL_FETCH_ENABLE_LSB);
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

    REG32(FRAMECLEAR_DMA_MODE(0)) = 0;
    REG32(FRAMECLEAR_DMA_STATUS(0)) = 1;
    while (REG32(FRAMECLEAR_DMA_STATUS(0)));

    REG32(FRAMECLEAR_DMA_MODE(0)) = 1;
    REG32(FRAMECLEAR_DMA_STATUS(0)) = 1;
    while (REG32(FRAMECLEAR_DMA_STATUS(0)));
}

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

static void cmd_set_raster_buffers(uint8_t color_fbid, uint8_t depth_fbid) {
    REG32(TRIANGLE2D_INPUT0_BASE_ADDR + TRI2D_FBID_COLOR) = color_fbid & 0x3u;
    REG32(TRIANGLE2D_INPUT0_BASE_ADDR + TRI2D_FBID_DEPTH) = depth_fbid & 0x3u;
}

static void cmd_write_vertex_matrix(uint8_t phase) {
    int32_t camera_sin = sin_q14(phase);
    int32_t camera_cos = cos_q14(phase);

    vec3_t eye = {
        int_to_q16(0),
        scaled_q16_from_q14(camera_sin, CAMERA_Z),
        scaled_q16_from_q14(camera_cos, CAMERA_Z),
    };
    vec3_t center = {
        int_to_q16(0),
        int_to_q16(0),
        int_to_q16(0),
    };
    vec3_t up = {
        int_to_q16(0),
        scaled_q16_from_q14(camera_cos, 1),
        -scaled_q16_from_q14(camera_sin, 1),
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

static void cmd_start_cube_hw(uint8_t phase, uint8_t color_fbid, uint8_t depth_fbid) {
    cmd_set_raster_buffers(color_fbid, depth_fbid);
    cmd_write_vertex_matrix(phase);
    REG32(VERTEX_PROCESSOR_TRIANGLE_COUNT(0)) = 11;
    REG32(VERTEX_PROCESSOR_START_RENDER(0)) = 1;
}

int main(void) {
    uint8_t phase = INITIAL_PHASE;
    uint8_t display_fbid = BUFFER_A;
    uint8_t render_fbid = BUFFER_A;

    if (ddr_init()) {
        while (1);
    }

    cmd_load_cube_vertices();
    cmd_clear_buffers(render_fbid, 2, 4, 12);
    cmd_start_cube_hw(phase, render_fbid, render_fbid);
    wait_cycles(HW_RENDER_WAIT_CYCLES);
    cmd_enable_hdmi(display_fbid);

    while (1) {
        wait_cycles(DISPLAY_SWITCH_CYCLES);

        phase = (uint8_t)(phase + 2u);
        render_fbid = display_fbid == BUFFER_A ? BUFFER_B : BUFFER_A;

        cmd_clear_buffers(render_fbid, 2, 4, 12);
        cmd_start_cube_hw(phase, render_fbid, render_fbid);
        wait_cycles(HW_RENDER_WAIT_CYCLES);

        display_fbid = render_fbid;
        cmd_enable_hdmi(display_fbid);
    }
}
