#include "hdmi_utils.h"

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

void get_pixel(uint8_t fbid, uint16_t x, uint16_t y, uint8_t *r, uint8_t *g, uint8_t *b) {
    uint8_t cxo = x & 0x1F;
    uint8_t cxb = x >> 5;
    uint32_t addr_r = (1 << 31) | (fbid << 24) | (y << 13) | (cxb << 7) | cxo;
    uint32_t addr_g = addr_r | (1 << 5);
    uint32_t addr_b = addr_r | (2 << 5);
    *r = *((uint8_t*)addr_r);
    *g = *((uint8_t*)addr_g);
    *b = *((uint8_t*)addr_b);
}

uint8_t zero[8] = {
    0b00000000,
    0b00111100,
    0b01100110,
    0b01000010,
    0b01000010,
    0b01100110,
    0b00111100,
    0b00000000
};

uint8_t one[8] = {
    0b00000000,
    0b00001000,
    0b00011000,
    0b00111000,
    0b01101000,
    0b00001000,
    0b01111110,
    0b00000000
};

uint8_t two[8] = {
    0b00000000,
    0b00111100,
    0b01100110,
    0b00001100,
    0b00011000,
    0b00110000,
    0b01111110,
    0b00000000
};

uint8_t three[8] = {
    0b00000000,
    0b00111100,
    0b01100010,
    0b00001110,
    0b00000010,
    0b01100110,
    0b00111100,
    0b00000000
};

uint8_t four[8] = {
    0b00000000,
    0b00000100,
    0b00001100,
    0b00010100,
    0b00100100,
    0b01111110,
    0b00000100,
    0b00000000
};

uint8_t five[8] = {
    0b00000000,
    0b01111110,
    0b01000000,
    0b01111000,
    0b00001100,
    0b00000110,
    0b01111100,
    0b00000000
};

uint8_t six[8] = {
    0b00000000,
    0b00111100,
    0b01000000,
    0b01011100,
    0b01100110,
    0b01100110,
    0b00111100,
    0b00000000
};

uint8_t seven[8] = {
    0b00000000,
    0b01111110,
    0b00000110,
    0b00001100,
    0b00011000,
    0b00110000,
    0b01100000,
    0b00000000
};

uint8_t eight[8] = {
    0b00000000,
    0b00111100,
    0b01100110,
    0b00111100,
    0b01100110,
    0b01100110,
    0b00111100,
    0b00000000
};

uint8_t nine[8] = {
    0b00000000,
    0b00111100,
    0b01100110,
    0b01100110,
    0b00111010,
    0b00000010,
    0b00111100,
    0b00000000
};

uint8_t charF[8] = {
    0b00000000,
    0b01111110,
    0b01000000,
    0b01000000,
    0b01110000,
    0b01000000,
    0b01000000,
    0b00000000
};

uint8_t charP[8] = {
    0b00000000,
    0b01111100,
    0b01000110,
    0b01000110,
    0b01111100,
    0b01000000,
    0b01000000,
    0b00000000
};

uint8_t charS[8] = {
    0b00000000,
    0b00111100,
    0b01100010,
    0b01100000,
    0b00011100,
    0b01000110,
    0b00111100,
    0b00000000
};

uint8_t charColon[8] = {
    0b00000000,
    0b00000000,
    0b01100000,
    0b01100000,
    0b00000000,
    0b01100000,
    0b01100000,
    0b00000000
};

uint8_t charPeriod[8] = {
    0b00000000,
    0b00000000,
    0b00000000,
    0b00000000,
    0b00000000,
    0b00011000,
    0b00011000,
    0b00000000
};

uint8_t charSpace[8] = {
    0b00000000,
    0b00000000,
    0b00000000,
    0b00000000,
    0b00000000,
    0b00000000,
    0b00000000,
    0b00000000
};

void draw_char(uint8_t fbid, uint16_t x, uint16_t y, char c) {
    uint8_t *base;
    switch (c) {
        case '0': base = zero; break;
        case '1': base = one; break;
        case '2': base = two; break;
        case '3': base = three; break;
        case '4': base = four; break;
        case '5': base = five; break;
        case '6': base = six; break;
        case '7': base = seven; break;
        case '8': base = eight; break;
        case '9': base = nine; break;
        case 'F': base = charF; break;
        case 'P': base = charP; break;
        case 'S': base = charS; break;
        case ':': base = charColon; break;
        case '.': base = charPeriod; break;
        default: base = charSpace; break;
    }
    for (int yi = 0; yi < 8; yi++) {
        uint8_t row = base[yi];
        for (int xi = 0; xi < 8; xi++) {
            bool set = (row << xi) & 0x80;
            uint8_t color = set ? 255 : 0;
            set_pixel(fbid, x + 2*xi, y + 2*yi, color, color, color);
            set_pixel(fbid, x + 2*xi+1, y + 2*yi, color, color, color);
            set_pixel(fbid, x + 2*xi, y + 2*yi+1, color, color, color);
            set_pixel(fbid, x + 2*xi+1, y + 2*yi+1, color, color, color);
        }
    }
}

void write_string(uint8_t fbid, uint16_t x, uint16_t y, char *s) {
    char c;
    while ((c = *s++)) {
        draw_char(fbid, x, y, c);
        x += 16;
    }
}
