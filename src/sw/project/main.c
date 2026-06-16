/* SPDX-License-Identifier: CC0-1.0
 * SPDX-FileCopyrightText: 2024 RVLab Contributors
 */

#include <stdio.h>
#include <rvlab.h>

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

    REG32(HDMI_CTRL_FBID(0)) = fbid;
}


int main(void) {
    ddr_init();
    printf("HDMI HPD Status: %d\n", REG32(HDMI_CTRL_HPD(0)));

    REG32(HDMI_CTRL_CTRL(0)) |= (1<<HDMI_CTRL_CTRL_PHY_ENABLE_LSB); // Enable HDMI output
    REG32(HDMI_CTRL_CTRL(0)) |= (1<<HDMI_CTRL_CTRL_FETCH_ENABLE_LSB);

    uint32_t r = 255;
    uint32_t g = 0;
    uint32_t b = 0;

    uint32_t fbid = 1;

    last_frame = read_csr("mcycle");

    while (1) {
        for (int i = 0; i < 255; i++) {
            cmd_clear_fb(fbid, r, ++g, b);
            fbid = 1 - fbid;
        }
        for (int i = 0; i < 255; i++) {
            cmd_clear_fb(fbid, --r, g, b);
            fbid = 1 - fbid;
        }
        for (int i = 0; i < 255; i++) {
            cmd_clear_fb(fbid, r, g, ++b);
            fbid = 1 - fbid;
        }
        for (int i = 0; i < 255; i++) {
            cmd_clear_fb(fbid, r, --g, b);
            fbid = 1 - fbid;
        }
        for (int i = 0; i < 255; i++) {
            cmd_clear_fb(fbid, ++r, g, b);
            fbid = 1 - fbid;
        }
        for (int i = 0; i < 255; i++) {
            cmd_clear_fb(fbid, r, g, --b);
            fbid = 1 - fbid;
        }
    }

    return 0;
}
