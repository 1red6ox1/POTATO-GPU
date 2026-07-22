#include "fixed_math.h"

static uint8_t clz32(uint32_t x) {
	if (x == 0) return 0;
    uint8_t n = 0;
    while ((x & 0x80000000u) == 0) {
        n++;
        x <<= 1;
    }
    return n;
}

fixed_t fixed_sqrt(fixed_t x) {
    if (x <= 0) return 0;

    uint32_t ux = (uint32_t)x;
    uint8_t msb = 31 - clz32(ux);

    // initial sqrt estimate: sqrt(x<<16) ~= 2^((msb+16)/2)
    fixed_t y = (fixed_t)(1 << ((msb + 16) >> 1));

    // newton-raphson
    for (int i = 0; i < 4; i++) {
        y = (fixed_t)((y + (((int64_t)x << 16) / y)) >> 1);
    }

    return y;
}

fixed_t fixed_mul(fixed_t a, fixed_t b) {
	int64_t product = (int64_t)a * (int64_t)b;
	return (fixed_t)(product >> 16);
}

fixed_t fixed_div(fixed_t a, fixed_t b) {
	return (fixed_t)(((int64_t)a << 16) / b);
}

void fixed_print(fixed_t f) {
	int64_t f_x10k = (int64_t)f * 10000; // (true value * 65536) * 10.000
	int64_t true_x10k = f_x10k >> 16;    // (true value) * 10.000
	int32_t decimals = true_x10k < 0 ? ((-true_x10k) % 10000) : (true_x10k % 10000);
	int32_t integer = true_x10k / 10000;
	printf("%6d.%04d", integer, decimals);
}

void fixed_print_full(fixed_t f) {
    int64_t f_x10k = (int64_t)f * 10000; // (true value * 65536) * 10.000
    int64_t true_x10k = f_x10k >> 16;    // (true value) * 10.000
    int32_t decimals = true_x10k < 0 ? ((-true_x10k) % 10000) : (true_x10k % 10000);
    int32_t integer = true_x10k / 10000;
    printf("%6d.%04d[0x%08x]", integer, decimals, f);
}

// Input phase 0..255 represents 0..2*pi. The result is signed Q2.14.
int32_t sin_q14(uint8_t phase) {
    uint32_t half_phase = phase & 0x7fu;
    uint32_t x = half_phase <= 64u ? half_phase : 128u - half_phase;
    int32_t value = (int32_t)(x * (128u - x) * 4u);

    return (phase & 0x80u) ? -value : value;
}

int32_t cos_q14(uint8_t phase) {
    return sin_q14((uint8_t)(phase + 64u));
}
