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

#define SIN_LUT_SIZE        256
#define SIN_LUT_INDEX_SHIFT 16
#define SIN_LUT_INDEX_MASK  0xFF
#define SIN_LUT_FRAC_SHIFT  14
#define SIN_LUT_FRAC_MASK   0x3
#define SIN_LUT_QUARTER     (SIN_LUT_SIZE / 4)  /* quarter period, for cos() */
 
extern const fixed_t sin_lut[SIN_LUT_SIZE];
 
fixed_t fixed_sin(fixed_t angle) {
    uint32_t idx  = ((uint32_t)angle >> SIN_LUT_INDEX_SHIFT) & SIN_LUT_INDEX_MASK;
    uint32_t frac = ((uint32_t)angle >> SIN_LUT_FRAC_SHIFT) & SIN_LUT_FRAC_MASK;
 
    fixed_t a = sin_lut[idx];
    fixed_t b = sin_lut[(idx + 1) & SIN_LUT_INDEX_MASK];
 
    /* linear interpolation: a + (b - a) * frac / 4 */
    return a + (fixed_t)(((int64_t)(b - a) * (int64_t)frac) >> 2);
}
 
fixed_t fixed_cos(fixed_t angle) {
    return fixed_sin(angle + (SIN_LUT_QUARTER << SIN_LUT_INDEX_SHIFT));
}

fixed_t fixed_lerp(fixed_t a, fixed_t b, fixed_t t) {
    return a + fixed_mul(b - a, t);
}
