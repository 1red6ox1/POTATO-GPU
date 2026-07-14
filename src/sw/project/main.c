/* SPDX-License-Identifier: CC0-1.0
 * SPDX-FileCopyrightText: 2024 RVLab Contributors
 */

#include <stdint.h>
#include <rvlab.h>

#define SCREEN_WIDTH  1920
#define SCREEN_HEIGHT 1080

#define Q_ONE   (1u << 24)
#define Q_HALF  (Q_ONE >> 1)
#define Q_THIRD (Q_ONE / 3)

#define CUBE_SIZE     150
#define CAMERA_Z      760
#define FOCAL_LENGTH  900
#define DEPTH_SCALE   48

#define DISPLAY_SWITCH_CYCLES 1000000u

typedef struct {
    int16_t x;
    int16_t y;
    uint16_t z;
    uint32_t uq;
    uint32_t vq;
    uint32_t q;
} screen_vertex_t;

typedef struct {
    int16_t x;
    int16_t y;
    int16_t z;
    uint32_t u;
    uint32_t v;
} cube_vertex_t;

typedef struct {
    uint8_t a;
    uint8_t b;
    uint8_t c;
} triangle_index_t;

// u and v are barycentric color coordinates. The hardware produces
// red = 1-u-v, green = v, blue = u.
static const cube_vertex_t cube_vertices[8] = {
    {-CUBE_SIZE, -CUBE_SIZE, -CUBE_SIZE, 0,       0      },
    { CUBE_SIZE, -CUBE_SIZE, -CUBE_SIZE, Q_ONE,   0      },
    { CUBE_SIZE,  CUBE_SIZE, -CUBE_SIZE, Q_HALF,  Q_HALF },
    {-CUBE_SIZE,  CUBE_SIZE, -CUBE_SIZE, 0,       Q_ONE  },
    {-CUBE_SIZE, -CUBE_SIZE,  CUBE_SIZE, Q_HALF,  0      },
    { CUBE_SIZE, -CUBE_SIZE,  CUBE_SIZE, Q_THIRD, Q_THIRD},
    { CUBE_SIZE,  CUBE_SIZE,  CUBE_SIZE, 0,       Q_HALF },
    {-CUBE_SIZE,  CUBE_SIZE,  CUBE_SIZE, Q_HALF,  Q_HALF },
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

static void cmd_submit_triangle(
    uint8_t color_buffer,
    uint8_t depth_buffer,
    screen_vertex_t a,
    screen_vertex_t b,
    screen_vertex_t c
) {
    while (REG32(TRIANGLE2D_INPUT_STATUS(0))
           & TRIANGLE2D_INPUT_STATUS_VALID_MASK);

    REG32(TRIANGLE2D_INPUT_FBID_COLOR(0)) = color_buffer;
    REG32(TRIANGLE2D_INPUT_FBID_DEPTH(0)) = depth_buffer;

    REG32(TRIANGLE2D_INPUT_AX(0)) = (uint16_t)a.x;
    REG32(TRIANGLE2D_INPUT_AY(0)) = (uint16_t)a.y;
    REG32(TRIANGLE2D_INPUT_AZ(0)) = a.z;
    REG32(TRIANGLE2D_INPUT_AUQ(0)) = a.uq;
    REG32(TRIANGLE2D_INPUT_AVQ(0)) = a.vq;
    REG32(TRIANGLE2D_INPUT_AQ(0)) = a.q;

    REG32(TRIANGLE2D_INPUT_BX(0)) = (uint16_t)b.x;
    REG32(TRIANGLE2D_INPUT_BY(0)) = (uint16_t)b.y;
    REG32(TRIANGLE2D_INPUT_BZ(0)) = b.z;
    REG32(TRIANGLE2D_INPUT_BUQ(0)) = b.uq;
    REG32(TRIANGLE2D_INPUT_BVQ(0)) = b.vq;
    REG32(TRIANGLE2D_INPUT_BQ(0)) = b.q;

    REG32(TRIANGLE2D_INPUT_CX(0)) = (uint16_t)c.x;
    REG32(TRIANGLE2D_INPUT_CY(0)) = (uint16_t)c.y;
    REG32(TRIANGLE2D_INPUT_CZ(0)) = c.z;
    REG32(TRIANGLE2D_INPUT_CUQ(0)) = c.uq;
    REG32(TRIANGLE2D_INPUT_CVQ(0)) = c.vq;
    REG32(TRIANGLE2D_INPUT_CQ(0)) = c.q;

    REG32(TRIANGLE2D_INPUT_SUBMIT(0)) = 1;
}

static void cmd_submit_winding_corrected(
    uint8_t color_buffer,
    uint8_t depth_buffer,
    screen_vertex_t a,
    screen_vertex_t b,
    screen_vertex_t c
) {
    int32_t area = (int32_t)(b.x - a.x) * (int32_t)(c.y - a.y)
                 - (int32_t)(b.y - a.y) * (int32_t)(c.x - a.x);

    if (area == 0) {
        return;
    }

    if (area < 0) {
        screen_vertex_t temporary = b;
        b = c;
        c = temporary;
    }

    cmd_submit_triangle(color_buffer, depth_buffer, a, b, c);
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

static screen_vertex_t rotate_and_project(
    const cube_vertex_t *vertex,
    int32_t sin_x,
    int32_t cos_x,
    int32_t sin_y,
    int32_t cos_y
) {
    int32_t x_yaw = ((int32_t)vertex->x * cos_y
                   + (int32_t)vertex->z * sin_y) >> 14;
    int32_t z_yaw = (-(int32_t)vertex->x * sin_y
                   + (int32_t)vertex->z * cos_y) >> 14;
    int32_t y_pitch = ((int32_t)vertex->y * cos_x
                     - z_yaw * sin_x) >> 14;
    int32_t z_pitch = ((int32_t)vertex->y * sin_x
                     + z_yaw * cos_x) >> 14;
    int32_t camera_z = z_pitch + CAMERA_Z;
    int32_t screen_x = SCREEN_WIDTH / 2 + x_yaw * FOCAL_LENGTH / camera_z;
    int32_t screen_y = SCREEN_HEIGHT / 2 - y_pitch * FOCAL_LENGTH / camera_z;
    int32_t depth = 65535 - camera_z * DEPTH_SCALE;
    uint32_t q = (uint32_t)(((uint64_t)Q_ONE * CAMERA_Z)
                           / (uint32_t)camera_z);
    screen_vertex_t result;

    if (screen_x < 0) screen_x = 0;
    if (screen_x >= SCREEN_WIDTH) screen_x = SCREEN_WIDTH - 1;
    if (screen_y < 0) screen_y = 0;
    if (screen_y >= SCREEN_HEIGHT) screen_y = SCREEN_HEIGHT - 1;
    if (depth < 1) depth = 1;
    if (depth > 65535) depth = 65535;

    result.x = (int16_t)screen_x;
    result.y = (int16_t)screen_y;
    result.z = (uint16_t)depth;
    result.q = q;

    // uq=u*q and vq=v*q make the hardware interpolation perspective-correct.
    result.uq = (uint32_t)(((uint64_t)vertex->u * q) >> 24);
    result.vq = (uint32_t)(((uint64_t)vertex->v * q) >> 24);

    return result;
}

static void cmd_draw_cube(
    uint8_t color_buffer,
    uint8_t depth_buffer,
    uint8_t phase_x,
    uint8_t phase_y
) {
    screen_vertex_t projected[8];
    int32_t sin_x = sin_q14(phase_x);
    int32_t cos_x = cos_q14(phase_x);
    int32_t sin_y = sin_q14(phase_y);
    int32_t cos_y = cos_q14(phase_y);

    for (uint32_t i = 0; i < 8; i++) {
        projected[i] = rotate_and_project(&cube_vertices[i],
                                          sin_x, cos_x, sin_y, cos_y);
    }

    for (uint32_t i = 0; i < 12; i++) {
        cmd_submit_winding_corrected(
            color_buffer,
            depth_buffer,
            projected[cube_triangles[i].a],
            projected[cube_triangles[i].b],
            projected[cube_triangles[i].c]
        );
    }
}

int main(void) {
    uint8_t visible_buffer = 0;
    uint8_t phase_x = 0;
    uint8_t phase_y = 0;

    if (ddr_init()) {
        while (1);
    }

    // Initialize both color/depth buffer pairs before enabling the display.
    cmd_clear_buffers(0, 2, 4, 12);
    cmd_clear_buffers(1, 2, 4, 12);

    REG32(HDMI_CTRL_FBID(0)) = visible_buffer;
    REG32(HDMI_CTRL_CTRL(0)) =
        (1u << HDMI_CTRL_CTRL_PHY_ENABLE_LSB)
        | (1u << HDMI_CTRL_CTRL_FETCH_ENABLE_LSB);

    while (1) {
        uint8_t draw_buffer = visible_buffer ^ 1u;

        cmd_clear_buffers(draw_buffer, 2, 4, 12);
        cmd_draw_cube(draw_buffer, draw_buffer, phase_x, phase_y);

        // Status remains set until the complete rasterizer pipeline is empty
        // and every DDR write response has arrived.
        while (REG32(TRIANGLE2D_INPUT_STATUS(0))
               & TRIANGLE2D_INPUT_STATUS_VALID_MASK);

        // HDMI_CTRL_FBID selects the framebuffer at the next video frame.
        REG32(HDMI_CTRL_FBID(0)) = draw_buffer;
        wait_cycles(DISPLAY_SWITCH_CYCLES);
        visible_buffer = draw_buffer;

        phase_x = (uint8_t)(phase_x + 2u);
        phase_y = (uint8_t)(phase_y + 3u);
    }
}
