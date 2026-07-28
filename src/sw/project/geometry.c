#include "geometry.h"
#include "graphics_pipeline.h"

#define FIXED_ONE 0x00010000

typedef struct {
	vertex_t corner;
	vec3_t edge_a;
	vec3_t edge_b;
} face_desc_t;

static const face_desc_t cube_faces[6] = {
	/* back   (z = -1) */ { {-FIXED_ONE, -FIXED_ONE, -FIXED_ONE}, { 2*FIXED_ONE, 0, 0}, {0,  2*FIXED_ONE, 0} },
	/* front  (z = +1) */ { { FIXED_ONE, -FIXED_ONE,  FIXED_ONE}, {-2*FIXED_ONE, 0, 0}, {0,  2*FIXED_ONE, 0} },
	/* left   (x = -1) */ { {-FIXED_ONE, -FIXED_ONE,  FIXED_ONE}, {0, 0, -2*FIXED_ONE}, {0,  2*FIXED_ONE, 0} },
	/* right  (x = +1) */ { { FIXED_ONE, -FIXED_ONE, -FIXED_ONE}, {0, 0,  2*FIXED_ONE}, {0,  2*FIXED_ONE, 0} },
	/* bottom (y = -1) */ { { FIXED_ONE, -FIXED_ONE, -FIXED_ONE}, {-2*FIXED_ONE, 0, 0}, {0, 0,  2*FIXED_ONE} },
	/* top    (y = +1) */ { { FIXED_ONE,  FIXED_ONE,  FIXED_ONE}, {-2*FIXED_ONE, 0, 0}, {0, 0, -2*FIXED_ONE} },
};

void make_face(
	triangle_t *tri_a,
	triangle_t *tri_b,
	const vertex_t *corner,
	const vec3_t edge_a,
	const vec3_t edge_b,
	texture_id_t texid
) {
	const vertex_t a_corner = {
		corner->x + edge_a[0],
		corner->y + edge_a[1],
		corner->z + edge_a[2],
	};
	const vertex_t b_corner = {
		corner->x + edge_b[0],
		corner->y + edge_b[1],
		corner->z + edge_b[2],
	};
	const vertex_t ab_corner = {
		corner->x + edge_a[0] + edge_b[0],
		corner->y + edge_a[1] + edge_b[1],
		corner->z + edge_a[2] + edge_b[2],
	};

	tri_a->a = *corner;
	tri_a->b = ab_corner;
	tri_a->c = b_corner;
	tri_a->uv = 0b011000;
	tri_a->texid = texid;

	tri_b->a = *corner;
	tri_b->b = a_corner;
	tri_b->c = ab_corner;
	tri_b->uv = 0b011110;
	tri_b->texid = texid;
}

void make_cube(triangle_t *dest, uint32_t subdivisions, uint32_t *num_triangles) {
	uint32_t triangle = 0;

	for (uint32_t face = 0; face < 6; face++) {
		const face_desc_t *fd = &cube_faces[face];

		uint32_t face_square_id = 0;

		/* Per-step edge vectors: full face edge divided into `subdivisions` parts. */
		const vec3_t step_a = {
			fd->edge_a[0] / (int32_t)subdivisions,
			fd->edge_a[1] / (int32_t)subdivisions,
			fd->edge_a[2] / (int32_t)subdivisions,
		};
		const vec3_t step_b = {
			fd->edge_b[0] / (int32_t)subdivisions,
			fd->edge_b[1] / (int32_t)subdivisions,
			fd->edge_b[2] / (int32_t)subdivisions,
		};

		for (uint32_t j = 0; j < subdivisions; j++) {
			for (uint32_t i = 0; i < subdivisions; i++) {
				const vertex_t corner = {
					fd->corner.x + step_a[0] * (int32_t)i + step_b[0] * (int32_t)j,
					fd->corner.y + step_a[1] * (int32_t)i + step_b[1] * (int32_t)j,
					fd->corner.z + step_a[2] * (int32_t)i + step_b[2] * (int32_t)j,
				};

				make_face(dest, &dest[1], &corner, step_a, step_b, face_square_id);
				dest = &dest[2];

				triangle += 2;
				face_square_id += 1;
			}
		}
	}
	*num_triangles = triangle;
}
