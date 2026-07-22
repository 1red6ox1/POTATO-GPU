#ifndef GRAPHICS_PIPELINE_H
#define GRAPHICS_PIPELINE_H

#include <stdint.h>
#include <rvlab.h>

#include "matrix_math.h"
#include "hdmi_utils.h"

#define TRIANGLE_ID_MASK 0x7ffu
#define BACKGROUND_COLOR 0x02040cu
#define CPU_CLOCK_HZ     50000000u

typedef uint8_t  buf_id_t;
typedef uint16_t tri_id_t;
typedef uint8_t  palette_id_t;
typedef uint8_t  texture_id_t;

/* UV descriptor: 6 bit value describing UV coordinates of a triangle */
typedef uint8_t uv_desc_t;

void clear_color_buf(buf_id_t color_buffer);

void clear_depth_buf(buf_id_t depth_buffer);

void clear_buffers();

void render_frame(buf_id_t color_buffer, buf_id_t depth_buffer);

void write_camera_matrix(matrix_t matrix);

void enable_hdmi();

void set_texid(tri_id_t tri, texture_id_t tex);

texture_id_t get_texid(tri_id_t tri);

void set_uv_desc(tri_id_t tri, uv_desc_t desc);

uv_desc_t get_uv_desc(tri_id_t tri);

void set_tri_count(uint32_t count);

uint32_t get_tri_count();

void set_hdmi_fbid(buf_id_t buf);

void advance_buffers(buf_id_t *color, buf_id_t *depth);

void update_fps_display(buf_id_t fbid);

#endif // GRAPHICS_PIPELINE_H
