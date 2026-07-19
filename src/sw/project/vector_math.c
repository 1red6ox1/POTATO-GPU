#include "vector_math.h"

static uint64_t isqrt_u64(uint64_t value) {
	uint64_t root = 0;
	uint64_t bit = 1ull << 62;

	while (bit > value) {
		bit >>= 2;
	}

	while (bit != 0) {
		if (value >= root + bit) {
			value -= root + bit;
			root = (root >> 1) + bit;
		} else {
			root >>= 1;
		}
		bit >>= 2;
	}

	return root;
}

void vec3_add(vec3_t dest, vec3_t a, vec3_t b) {
	dest[0] = a[0] + b[0];
	dest[1] = a[1] + b[1];
	dest[2] = a[2] + b[2];
}

void vec3_sub(vec3_t dest, vec3_t a, vec3_t b) {
	dest[0] = a[0] - b[0];
	dest[1] = a[1] - b[1];
	dest[2] = a[2] - b[2];
}

fixed_t vec3_abs(vec3_t in) {
	uint64_t radicand = 0;
	for (int i = 0; i < 3; i++) {
		uint64_t component = (uint64_t)in[i];
		radicand += component * component;
	}
	return (fixed_t)(isqrt_u64(radicand));
}

fixed_t vec3_dot(vec3_t vec1, vec3_t vec2) {
	fixed_t result = 0;
	result += fixed_mul(vec1[0], vec2[0]);
	result += fixed_mul(vec1[1], vec2[1]);
	result += fixed_mul(vec1[2], vec2[2]);
	return result;
}

void vec3_cross(vec3_t dest, vec3_t a, vec3_t b) {
	dest[0] = fixed_mul(a[1], b[2]) - fixed_mul(a[2], b[1]);
	dest[1] = fixed_mul(a[2], b[0]) - fixed_mul(a[0], b[2]);
	dest[2] = fixed_mul(a[0], b[1]) - fixed_mul(a[1], b[0]);
}

void vec3_normalize(vec3_t dest, vec3_t src) {
	fixed_t abs = vec3_abs(src);
	dest[0] = fixed_div(src[0], abs);
	dest[1] = fixed_div(src[1], abs);
	dest[2] = fixed_div(src[2], abs);
}

void vec3_print(vec3_t vec) {
	printf("( ");
	for (int i = 0; i < 3; i++) {
		fixed_print_full(vec[i]);
		printf(" ");
	}
	printf(")");
}

void vec4_print(vec4_t vec) {
	printf("[ ");
	for (int i = 0; i < 4; i++) {
		fixed_print_full(vec[i]);
		printf(" ");
	}
	printf("]");
}
