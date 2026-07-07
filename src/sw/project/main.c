/* SPDX-License-Identifier: CC0-1.0
 * SPDX-FileCopyrightText: 2024 RVLab Contributors
 */

#include <stdio.h>
#include <stdbool.h>
#include <rvlab.h>

#include "graphics_math.h"

uint32_t last_frame;

void cmd_clear_fb(unsigned char fbid, unsigned char r, unsigned char g, unsigned char b) {

    //printf("Filling FB %u with R=%03u, G=%03u, B=%03u\n", fbid, r, g, b);

    REG32(FRAMECLEAR_DMA_FBID(0)) = fbid;
    REG32(FRAMECLEAR_DMA_CLEAR_COLOR(0)) = (r << 16) | (g << 8) | (b << 0);
    REG32(FRAMECLEAR_DMA_MODE(0)) = 0;
    REG32(FRAMECLEAR_DMA_STATUS(0)) = 1;

    uint32_t start = read_csr("mcycle");

    while (REG32(FRAMECLEAR_DMA_STATUS(0)));

    uint32_t finish = read_csr("mcycle");

    //printf("Took %u cycles!\n", finish - start);

    if (finish - start < 100000) {
        printf("Frame clear unusually fast (%u cycles)!!\n", finish - start);
    }

    uint32_t dt = finish - last_frame;
    uint32_t fps_x10 = 500000000 / dt;

    //printf("\rFPS: %u.%u", fps_x10/10, fps_x10%10);

    last_frame = finish;
}

typedef vec4_t triangle_t[3];

void viewport_transform(vec4_t clip, int16_t* x, int16_t* y) {
    fixed_t ndc_x = fixed_div(clip[0], clip[3]);
    fixed_t ndc_y = fixed_div(clip[1], clip[3]);
    fixed_t screen_x = ((ndc_x + (1<<16)) >> 1) * 1920;
    fixed_t screen_y = ((ndc_y + (1<<16)) >> 1) * 1080;
    *x = screen_x >> 16;
    *y = 1080 - (screen_y >> 16);
}

void set_pixel(uint8_t fbid, uint16_t x, uint16_t y, uint8_t r, uint8_t g, uint8_t b) {
    uint8_t cxo = x & 0x1F;
    uint8_t cxb = x >> 5;
    uint32_t addr_r = (1 << 31) | (fbid << 24) | (y << 13) | (cxb << 7) | cxo;
    uint32_t addr_g = addr_r | (1 << 5);
    uint32_t addr_b = addr_r | (2 << 5);
    *((uint8_t*)addr_r) = r;
    *((uint8_t*)addr_g) = g;
    *((uint8_t*)addr_b) = b;
}

void render_line(uint8_t fbid, uint16_t x0, uint16_t y0, uint16_t x1, uint16_t y1) {
    int16_t dx = x0 < x1 ? x1 - x0 : x0 - x1;
    int16_t sx = x0 < x1 ? 1 : -1;
    int16_t dy = y0 < y1 ? y0 - y1 : y1 - y0;
    int16_t sy = y0 < y1 ? 1 : -1;
    int16_t err = dx + dy;
    int16_t err2;

    while (1) {
        if (x0 < 0 || y0 < 0) break;
        set_pixel(fbid, x0, y0, 255, 255, 255);
        err2 = err * 2;
        if (err2 >= dy) {
            if (x0 == x1) break;
            err = err + dy;
            x0 = x0 + sx;
        }
        if (err2 <= dx) {
            if (y0 == y1) break;
            err = err + dx;
            y0 = y0 + sy;
        }
    }
}

void render_tri(triangle_t tri, matrix_t VP, uint8_t fbid) {
    vec4_t clip_p0, clip_p1, clip_p2;
    int16_t x0, x1, x2;
    int16_t y0, y1, y2;
    mat_vec_mul(clip_p0, VP, tri[0]);
    mat_vec_mul(clip_p1, VP, tri[1]);
    mat_vec_mul(clip_p2, VP, tri[2]);
    viewport_transform(clip_p0, &x0, &y0);
    viewport_transform(clip_p1, &x1, &y1);
    viewport_transform(clip_p2, &x2, &y2);
    render_line(fbid, x0, y0, x1, y1);
    render_line(fbid, x1, y1, x2, y2);
    render_line(fbid, x2, y2, x0, y0);
    // Flush DDR cache
    for (volatile uint8_t* x = (uint8_t*)0x90000000; x < (uint8_t*)0x90004000; x += 32) *x;
}

#define F(x) ((x) << 16)
#define V3(x, y, z) (vec3_t){F(x), F(y), F(z)}
#define V4(x, y, z, w) {F(x), F(y), F(z), F(w)}
// Default camera attributes: aspect 16/9, near 0.25, far 100
#define FOVY 60
#define INV_ASPECT 0x00009000
#define NEAR (1<<14)
#define FAR (100<<16)

void testcase_single_tri(matrix_t VP, triangle_t tri) {
    vec4_t clip[3];
    int16_t x[3];
    int16_t y[3];

    mat_vec_mul(clip[0], VP, tri[0]);
    mat_vec_mul(clip[1], VP, tri[1]);
    mat_vec_mul(clip[2], VP, tri[2]);
    viewport_transform(clip[0], &x[0], &y[0]);
    viewport_transform(clip[1], &x[1], &y[1]);
    viewport_transform(clip[2], &x[2], &y[2]);

    printf("  WORLD SPACE:\n");
    for (int k = 0; k < 3; k++) {
        printf("    P%d: ", k);
        vec4_print(tri[k]);
        printf("\n");
    }

    printf("  CLIP SPACE:\n");
    for (int k = 0; k < 3; k++) {
        printf("    P%d: ", k);
        vec4_print(clip[k]);
        printf("\n");
    }

    printf("  SCREEN SPACE:\n");
    for (int k = 0; k < 3; k++) {
        bool discard = x[k] > 1919 || x[k] < 0 || y[k] > 1079 || y[k] < 0;
        printf("    P%d: %4d/%4d %s", k, x[k], y[k], discard ? "(discarded)" : "");
        printf("\n");
    }
}

void testcases() {
    /* Generate some test cases for different stages of the design */

    #define NCAMPOS 5
    #define NTRIS 2

    matrix_t view_mat, proj_mat, VP;
    vec3_t camera_positions[NCAMPOS] = {
        {F( 5), F( 0), F( 0)},
        {F(-2), F( 3), F( 1)},
        {F( 1), F( 6), F( 0)},
        {F( 3), F( 3), F( 3)},
        {F( 0), F( 0), F( 1)}
    };

    triangle_t triangles[NTRIS] = {
        {V4(0, 0, 0, 1), V4(1, 0, 0, 1), V4(1, 1, 0, 1)},
        {V4(-2, -1, 1, 1), V4(1, 2, 0, 1), V4(-1, 0, 0, 1)}
    };

    persp_proj_mat(proj_mat, FOVY, INV_ASPECT, FAR, NEAR);

    for (int i = 0; i < NCAMPOS; i++) {
        vec3_t *camera_pos = &camera_positions[i];

        // Generate matrices
        lookat_mat(view_mat, *camera_pos, V3(0, 0, 0), V3(0, 1, 0));
        mat_mat_mul(VP, proj_mat, view_mat);

        printf("\n===\n\n");
        printf("VIEWxPROJ for camera %d @ ", i);
        vec3_print(*camera_pos);
        printf(":\n");
        mat_print(VP);
        printf("\n");

        for (int j = 0; j < NTRIS; j++) {
            printf("TRI %d:\n", j);
            testcase_single_tri(VP, triangles[j]);
            printf("\n");
        }
    }
}

int main(void) {
    ddr_init();

    vec3_t camera_pos = {F(5), F(2), F(-5)};
    matrix_t view_mat, proj_mat, VP;
    persp_proj_mat(proj_mat, FOVY, INV_ASPECT, FAR, NEAR);

    uint8_t fbid = 0;
    
    REG32(HDMI_CTRL_CTRL(0)) |= (1<<HDMI_CTRL_CTRL_PHY_ENABLE_LSB); // Enable HDMI output
    REG32(HDMI_CTRL_CTRL(0)) |= (1<<HDMI_CTRL_CTRL_FETCH_ENABLE_LSB);
    REG32(HDMI_CTRL_FBID(0)) = 0;

    testcases();

    while (1) {
        cmd_clear_fb(fbid, 0, 0, 0);

        // Projection matrix stays the same, adjust view matrix and regenerate VP
        lookat_mat(view_mat, camera_pos, V3(0, 0, 0), V3(0, 1, 0));
        mat_mat_mul(VP, proj_mat, view_mat);

        camera_pos[2] = camera_pos[2] + 0x00000400;
        if (camera_pos[2] > (5 << 16)) camera_pos[2] = -5 << 16;

        render_tri((triangle_t){
            V4(0, 0, 0, 1),
            V4(1, 0, 0, 1),
            V4(1, 1, 0, 1)
        }, VP, fbid);

        render_tri((triangle_t){
            V4(2, 0, 0, 1),
            V4(3, 0, 0, 1),
            V4(3, 1, 0, 1)
        }, VP, fbid);

        REG32(HDMI_CTRL_FBID(0)) = fbid;
        fbid = (fbid + 1) % 4;
    }

    return 0;
}
