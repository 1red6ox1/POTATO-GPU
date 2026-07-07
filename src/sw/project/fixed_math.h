#ifndef FIXED_MATH_H
#define FIXED_MATH_H

#include <stdio.h>
#include <stdint.h>

typedef int32_t fixed_t;

fixed_t fixed_sqrt(fixed_t x);

fixed_t fixed_mul(fixed_t a, fixed_t b);

// Expensive. Avoid if possible.
fixed_t fixed_div(fixed_t a, fixed_t b);

void fixed_print(fixed_t f);

void fixed_print_full(fixed_t f);

#endif // FIXED_MATH_H
