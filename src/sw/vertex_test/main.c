/* SPDX-License-Identifier: CC0-1.0
 * SPDX-FileCopyrightText: 2026 RVLab Contributors
 */

#include <stdint.h>
#include <stdio.h>
#include <rvlab.h>

static uint32_t vertex_vec_addr(unsigned int triangle, unsigned int vertex, unsigned int lane) {
    return VERTEX_DATA0_BASE_ADDR | (triangle << 6) | (vertex << 4) | (lane << 2);
}

static int check_word(const char *name, uint32_t addr, uint32_t expected) {
    uint32_t actual = REG32(addr);

    if (actual != expected) {
        printf("FAIL %s @ 0x%08x: expected 0x%08x, got 0x%08x\n",
               name, addr, expected, actual);
        return 1;
    }

    return 0;
}

int main(void) {
    static const uint32_t identity_matrix[16] = {
        0x00010000, 0x00000000, 0x00000000, 0x00000000,
        0x00000000, 0x00010000, 0x00000000, 0x00000000,
        0x00000000, 0x00000000, 0x00010000, 0x00000000,
        0x00000000, 0x00000000, 0x00000000, 0x00010000,
    };

    int failed = 0;

    printf("vertex_test: write/read config matrix\n");
    for (unsigned int i = 0; i < 16; i++) {
        uint32_t addr = VERTEX_CFG0_BASE_ADDR + (i << 2);
        REG32(addr) = identity_matrix[i];
        failed |= check_word("cfg", addr, identity_matrix[i]);
    }

    printf("vertex_test: write/read vector RAM\n");
    for (unsigned int triangle = 0; triangle < 2; triangle++) {
        for (unsigned int vertex = 0; vertex < 3; vertex++) {
            for (unsigned int lane = 0; lane < 4; lane++) {
                uint32_t addr = vertex_vec_addr(triangle, vertex, lane);
                uint32_t value = 0x10000000 | (triangle << 12) | (vertex << 8) | lane;
                REG32(addr) = value;
            }
        }
    }

    for (unsigned int triangle = 0; triangle < 2; triangle++) {
        for (unsigned int vertex = 0; vertex < 3; vertex++) {
            for (unsigned int lane = 0; lane < 4; lane++) {
                uint32_t addr = vertex_vec_addr(triangle, vertex, lane);
                uint32_t expected = 0x10000000 | (triangle << 12) | (vertex << 8) | lane;
                failed |= check_word("vec", addr, expected);
            }
        }
    }

    if (failed) {
        printf("vertex_test: FAIL\n");
        return 1;
    }

    printf("vertex_test: PASS\n");
    return 0;
}
