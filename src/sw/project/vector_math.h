#ifndef VECTOR_MATH_H
#define VECTOR_MATH_H

#include "fixed_math.h"

typedef fixed_t vec3_t [3];
typedef fixed_t vec4_t [4];

void vec3_add(vec3_t dest, vec3_t a, vec3_t b);

void vec3_sub(vec3_t dest, vec3_t a, vec3_t b);

fixed_t vec3_abs(vec3_t in);

fixed_t vec3_dot(vec3_t vec1, vec3_t vec2);

void vec3_cross(vec3_t dest, vec3_t a, vec3_t b);

void vec3_normalize(vec3_t dest, vec3_t src);

void vec3_print(vec3_t vec);

void vec4_print(vec4_t vec);

#endif // VECTOR_MATH_H
