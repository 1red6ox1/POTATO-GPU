/* SPDX-License-Identifier: CC0-1.0
 * SPDX-FileCopyrightText: 2024 RVLab Contributors
 */

#include <stdio.h>
#include <stdbool.h>
#include <rvlab.h>

#include "graphics_math.h"
#include "hdmi_utils.h"

uint32_t last_frame;

char fps_display[20];

void cmd_clear_fb(unsigned char fbid, unsigned char r, unsigned char g, unsigned char b) {

    //printf("Filling FB %u with R=%03u, G=%03u, B=%03u\n", fbid, r, g, b);

    REG32(FRAMECLEAR_DMA_FBID(0)) = fbid;
    REG32(FRAMECLEAR_DMA_CLEAR_COLOR(0)) = (r << 16) | (g << 8) | (b << 0);
    REG32(FRAMECLEAR_DMA_MODE(0)) = 0;
    REG32(FRAMECLEAR_DMA_STATUS(0)) = 1;

    uint32_t start = read_csr("mcycle");

    while (REG32(FRAMECLEAR_DMA_STATUS(0)));

    uint32_t finish = read_csr("mcycle");

    if (finish - start < 100000) {
        printf("Frame clear unusually fast (%u cycles)!!\n", finish - start);
    }

    uint32_t dt = finish - last_frame;
    uint32_t fps_x10 = 500000000 / dt;

    sprintf(fps_display, "FPS: %u.%u", fps_x10 / 10, fps_x10 % 10);

    last_frame = finish;
}

typedef vec4_t triangle_t[3];

void viewport_transform(vec4_t clip, int16_t* x, int16_t* y) {
    fixed_t ndc8_x = fixed_div(clip[0] << 3, clip[3]);
    fixed_t ndc8_y = fixed_div(clip[1] << 3, clip[3]);
    fixed_t screen_x = ((ndc8_x + (8<<16)) >> 1) * 1920;
    fixed_t screen_y = ((ndc8_y + (8<<16)) >> 1) * 1080;
    *x = screen_x >> 16;
    *y = (1080 << 3) - (screen_y >> 16);
}

void render_line(uint8_t fbid, int16_t x0, int16_t y0, int16_t x1, int16_t y1) {
    int16_t dx = x0 < x1 ? x1 - x0 : x0 - x1;
    int16_t sx = x0 < x1 ? 1 : -1;
    int16_t dy = y0 < y1 ? y0 - y1 : y1 - y0;
    int16_t sy = y0 < y1 ? 1 : -1;
    int16_t err = dx + dy;
    int16_t err2;

    while (1) {
        if (x0 >= 0 && x0 < 1920 && y0 >= 0 && y0 < 1080) {
            set_pixel(fbid, x0, y0, 255, 255, 255);
        }
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

int16_t clamp(int16_t x, int16_t low, int16_t high) {
    if (x < low) return low;
    if (x > high) return high;
    return x;
}

typedef int32_t affine_coeffs[3];
typedef int64_t affine_pcoeffs[3];

void gen_edgefn_coeffs(affine_pcoeffs dest, int16_t x0, int16_t y0, int16_t x1, int16_t y1) {
    dest[0] = y1 - y0;
#define V3(x, y, z) (vec3_t){F(x), F(y), F(z)}
    dest[1] = x0 - x1;
    dest[2] = x1 * y0 - x0 * y1;
}

void gen_attrib_coeffs(
    affine_pcoeffs dest,
    fixed_t a0, fixed_t a1, fixed_t a2,
    affine_pcoeffs e0, affine_pcoeffs e1, affine_pcoeffs e2
) {
    int64_t a0e0a = (int64_t)a0 * e0[0];
    int64_t a1e1a = (int64_t)a1 * e1[0];
    int64_t a2e2a = (int64_t)a2 * e2[0];
    dest[0] = a0e0a + a1e1a + a2e2a;
    int64_t a0e0b = (int64_t)a0 * e0[1];
    int64_t a1e1b = (int64_t)a1 * e1[1];
    int64_t a2e2b = (int64_t)a2 * e2[1];
    dest[1] = a0e0b + a1e1b + a2e2b;
    int64_t a0e0c = (int64_t)a0 * e0[2];
    int64_t a1e1c = (int64_t)a1 * e1[2];
    int64_t a2e2c = (int64_t)a2 * e2[2];
    dest[2] = a0e0c + a1e1c + a2e2c;
}

int64_t affine_peval(affine_pcoeffs pcoeffs, int32_t x, int32_t y) {
    return pcoeffs[0] * x + pcoeffs[1] * y + pcoeffs[2];
}

void rasterize_tri(
    uint8_t fbid,
    int16_t x0, int16_t y0, fixed_t w0,
    int16_t x1, int16_t y1, fixed_t w1,
    int16_t x2, int16_t y2, fixed_t w2
) {

    /*
    xi / yi are subpixel coordinates
    such that one increment of any parameter
    corresponds to 1/8th of a pixel
    */

    int16_t min_x, max_x;
    int16_t min_y, max_y;

    min_x = x0;
    if (x1 < min_x) min_x = x1;
    if (x2 < min_x) min_x = x2;
    max_x = x0;
    if (x1 > max_x) max_x = x1;
    if (x2 > max_x) max_x = x2;
    min_y = y0;
    if (y1 < min_y) min_y = y1;
    if (y2 < min_y) min_y = y2;
    max_y = y0;
    if (y1 > max_y) max_y = y1;
    if (y2 > max_y) max_y = y2;

    min_x = (clamp(min_x, 0, 1919 << 3) & ~7) - 1;
#define V3(x, y, z) (vec3_t){F(x), F(y), F(z)}
    max_x = clamp(max_x, 0, 1919 << 3) | 7;
    min_y = (clamp(min_y, 0, 1079 << 3) & ~7) - 1;
    max_y = clamp(max_y, 0, 1079 << 3) | 7;

    min_x = min_x & ~255;

    affine_pcoeffs ab;
    affine_pcoeffs bc;
    affine_pcoeffs ca;

    gen_edgefn_coeffs(ab, x0, y0, x1, y1);
    gen_edgefn_coeffs(bc, x1, y1, x2, y2);
    gen_edgefn_coeffs(ca, x2, y2, x0, y0);

    // 2**31 / (2**16 * wi) = 2**15 / wi
    fixed_t w_rcp0 = (0x80000000 / w0) << 1;
    fixed_t w_rcp1 = (0x80000000 / w1) << 1;
    fixed_t w_rcp2 = (0x80000000 / w2) << 1;

    affine_pcoeffs u_num;
    affine_pcoeffs v_num;
    affine_pcoeffs uv_denom;

    u_num[0] = bc[0] * w_rcp1;
    u_num[1] = bc[1] * w_rcp1;
    u_num[2] = bc[2] * w_rcp1;

    v_num[0] = ca[0] * w_rcp2;
    v_num[1] = ca[1] * w_rcp2;
    v_num[2] = ca[2] * w_rcp2;

    gen_attrib_coeffs(uv_denom, w_rcp0, w_rcp1, w_rcp2, ab, bc, ca);

    int64_t ab_startval = affine_peval(ab,       min_x, min_y);
    int64_t bc_startval = affine_peval(bc,       min_x, min_y);
    int64_t ca_startval = affine_peval(ca,       min_x, min_y);
    int64_t un_startval = affine_peval(u_num,    min_x, min_y);
    int64_t vn_startval = affine_peval(v_num,    min_x, min_y);
    int64_t iw_startval = affine_peval(uv_denom, min_x, min_y);

    /*printf("START VALUES: %08x%08x/%08x%08x/%08x%08x/%08x%08x/%08x%08x/%08x%08x\n",
        (int32_t)(ab_startval >> 32), (int32_t)ab_startval,
        (int32_t)(bc_startval >> 32), (int32_t)bc_startval,
        (int32_t)(ca_startval >> 32), (int32_t)ca_startval,
        (int32_t)(un_startval >> 32), (int32_t)un_startval,
        (int32_t)(vn_startval >> 32), (int32_t)vn_startval,
        (int32_t)(iw_startval >> 32), (int32_t)iw_startval
    );

    printf("DIFFS:\n");
    printf("  AB: %08x/%08x\n", (int32_t)ab[0], (int32_t)ab[1]);
    printf("  BC: %08x/%08x\n", (int32_t)bc[0], (int32_t)bc[1]);
    printf("  CA: %08x/%08x\n", (int32_t)ca[0], (int32_t)ca[1]);
    printf("  UN: %08x/%08x\n", (int32_t)u_num[0], (int32_t)u_num[1]);
    printf("  VN: %08x/%08x\n", (int32_t)v_num[0], (int32_t)v_num[1]);
    printf("  IW: %08x/%08x\n", (int32_t)uv_denom[0], (int32_t)uv_denom[1]);

    printf("BBOX: %d/%d/%d/%d\n", min_x, min_y, max_x, max_y);*/

    REG32(RASTERIZER_CTRL_FBID(0)) = fbid;
    REG32(RASTERIZER_CTRL_AB_TOPLEFT_HI(0)) = (int32_t)(ab_startval >> 32);
    REG32(RASTERIZER_CTRL_AB_TOPLEFT_LO(0)) = (int32_t)(ab_startval);
    REG32(RASTERIZER_CTRL_BC_TOPLEFT_HI(0)) = (int32_t)(bc_startval >> 32);
    REG32(RASTERIZER_CTRL_BC_TOPLEFT_LO(0)) = (int32_t)(bc_startval);
    REG32(RASTERIZER_CTRL_CA_TOPLEFT_HI(0)) = (int32_t)(ca_startval >> 32);
    REG32(RASTERIZER_CTRL_CA_TOPLEFT_LO(0)) = (int32_t)(ca_startval);
    REG32(RASTERIZER_CTRL_UN_TOPLEFT_HI(0)) = (int32_t)(un_startval >> 32);
    REG32(RASTERIZER_CTRL_UN_TOPLEFT_LO(0)) = (int32_t)(un_startval);
    REG32(RASTERIZER_CTRL_VN_TOPLEFT_HI(0)) = (int32_t)(vn_startval >> 32);
    REG32(RASTERIZER_CTRL_VN_TOPLEFT_LO(0)) = (int32_t)(vn_startval);
    REG32(RASTERIZER_CTRL_IW_TOPLEFT_HI(0)) = (int32_t)(iw_startval >> 32);
    REG32(RASTERIZER_CTRL_IW_TOPLEFT_LO(0)) = (int32_t)(iw_startval);
    REG32(RASTERIZER_CTRL_AB_DX(0)) = (int32_t)ab[0];
    REG32(RASTERIZER_CTRL_AB_DY(0)) = (int32_t)ab[1];
    REG32(RASTERIZER_CTRL_BC_DX(0)) = (int32_t)bc[0];
    REG32(RASTERIZER_CTRL_BC_DY(0)) = (int32_t)bc[1];
    REG32(RASTERIZER_CTRL_CA_DX(0)) = (int32_t)ca[0];
    REG32(RASTERIZER_CTRL_CA_DY(0)) = (int32_t)ca[1];
    REG32(RASTERIZER_CTRL_UN_DX(0)) = (int32_t)u_num[0];
    REG32(RASTERIZER_CTRL_UN_DY(0)) = (int32_t)u_num[1];
    REG32(RASTERIZER_CTRL_VN_DX(0)) = (int32_t)v_num[0];
    REG32(RASTERIZER_CTRL_VN_DY(0)) = (int32_t)v_num[1];
    REG32(RASTERIZER_CTRL_IW_DX(0)) = (int32_t)uv_denom[0];
    REG32(RASTERIZER_CTRL_IW_DY(0)) = (int32_t)uv_denom[1];
    REG32(RASTERIZER_CTRL_MIN_X(0)) = min_x;
    REG32(RASTERIZER_CTRL_MIN_Y(0)) = min_y;
    REG32(RASTERIZER_CTRL_MAX_X(0)) = max_x;
    REG32(RASTERIZER_CTRL_MAX_Y(0)) = max_y;

    REG32(RASTERIZER_CTRL_STATUS(0)) = 1;

    while (REG32(RASTERIZER_CTRL_STATUS(0)) > 0);
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

    rasterize_tri(fbid, x0, y0, clip_p0[3], x1, y1, clip_p1[3], x2, y2, clip_p2[3]);

    // Flush DDR cache
    //for (volatile uint8_t* x = (uint8_t*)0x90000000; x < (uint8_t*)0x90004000; x += 32) *x;
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

    vec3_t camera_pos = {F(5), F(1), F(6)};
    matrix_t view_mat, proj_mat, VP;
    persp_proj_mat(proj_mat, FOVY, INV_ASPECT, FAR, NEAR);

    //testcases();

    uint8_t fbid = 0;
    
    REG32(HDMI_CTRL_CTRL(0)) |= (1<<HDMI_CTRL_CTRL_PHY_ENABLE_LSB); // Enable HDMI output
    REG32(HDMI_CTRL_CTRL(0)) |= (1<<HDMI_CTRL_CTRL_FETCH_ENABLE_LSB);
    REG32(HDMI_CTRL_FBID(0)) = 0;

    fps_display[0] = '\0';

    while (1) {
        cmd_clear_fb(fbid, 0, 0, 0);

        // Projection matrix stays the same, adjust view matrix and regenerate VP
        lookat_mat(view_mat, camera_pos, V3(0, 0, 0), V3(0, 1, 0));
        mat_mat_mul(VP, proj_mat, view_mat);

        camera_pos[2] = camera_pos[2] + 0x00000100;
        if (camera_pos[2] > (8 << 16)) camera_pos[2] = -5 << 16;

        /*render_tri((triangle_t){
            V4(0, 0, -1, 1),
            V4(0, 1, 0, 1),
            V4(0, 0, 0, 1)
        }, VP, fbid);*/

        render_tri((triangle_t){
            V4(0, 0, 0, 1),
            V4(0, 2, 2, 1),
            V4(0, 0, 2, 1)
        }, VP, fbid);

        render_tri((triangle_t){
            V4(0, 0, 2, 1),
            V4(0, 1, 3, 1),
            V4(0, 0, 3, 1)
        }, VP, fbid);

        render_tri((triangle_t){
            V4(0, 0, 0, 1),
            V4(2, 2, 0, 1),
            V4(0, 2, 2, 1)
        }, VP, fbid);

        render_tri((triangle_t){
            V4(0, 0, 0, 1),
            V4(2, 0, 0, 1),
            V4(2, 2, 0, 1)
        }, VP, fbid);

        write_string(fbid, 0, 0, fps_display);

        for (volatile uint8_t* x = (uint8_t*)0x90000000; x < (uint8_t*)0x90004000; x += 32) *x;

        REG32(HDMI_CTRL_FBID(0)) = fbid;
        fbid = (fbid + 1) % 4;
    }

    return 0;
}
