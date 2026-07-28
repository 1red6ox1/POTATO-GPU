#ifndef HDMI_UTILS_H
#define HDMI_UTILS_H

#include <stdint.h>
#include <stdbool.h>

void set_pixel(uint8_t fbid, uint16_t x, uint16_t y, uint8_t r, uint8_t g, uint8_t b);

void get_pixel(uint8_t fbid, uint16_t x, uint16_t y, uint8_t *r, uint8_t *g, uint8_t *b);

void draw_char(uint8_t fbid, uint16_t x, uint16_t y, char c);

void write_string(uint8_t fbid, uint16_t x, uint16_t y, char *s);

#endif // HDMI_UTILS_H
