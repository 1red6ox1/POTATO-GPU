#ifndef GEOMETRY_H
#define GEOMETRY_H

#include <stdint.h>
#include <rvlab.h>

#include "graphics_pipeline.h"

void make_face(
	triangle_t *tri_a,
	triangle_t *tri_b,
	const vertex_t *corner,
	const vec3_t edge_a,
	const vec3_t edge_b,
	texture_id_t texid
);

void make_cube(triangle_t *dest, uint32_t subdivisions, uint32_t *num_triangles);

#endif // GEOMETRY_H
