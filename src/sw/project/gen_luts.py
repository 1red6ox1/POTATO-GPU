# 2026 POTATO GPU Contributors

# LUT mapping FOVy between 45° and 90° to corresponding cot(FOVy/2) for perspective projection matrix
# LUT for sin(), covering a full period in 256 entries, stored as 16.16 fixed point (int32_t)
# Generated in C code

from math import tan, radians, sin, pi


def fov_coefficient(fovy: float):
	return 1.0 / tan(radians(fovy / 2.0))

def fov_coeff_fixed(fovy: float):
	return int(fov_coefficient(fovy) * (1 << 16)) & 0xFFFFFFFF

CFILE_HEADER = """#include "fixed_math.h"

"""

FOV_CFILE_WRAPPER = """const fixed_t fov_coeff_lut [%d] = {
%s
};

"""

def gen_fov_cfile_text(fovy_min, fovy_max):
	fov_range = fovy_max - fovy_min + 1;
	lut_lines = []
	for i in range(fovy_min, fovy_max + 1):
		fov_coeff = fov_coefficient(i)
		lut_value = fov_coeff_fixed(i)
		if i < fovy_max:
			lut_lines.append("    0x%08x, // %1.2f" % (lut_value, round(fov_coeff, 2)))
		else:
			lut_lines.append("    0x%08x  // %1.2f" % (lut_value, round(fov_coeff, 2)))
	return FOV_CFILE_WRAPPER % (fov_range, "\n".join(lut_lines))

SIN_LUT_SIZE = 256

def sin_value(i: int):
	return sin(2.0 * pi * i / SIN_LUT_SIZE)

def sin_value_fixed(i: int):
	return int(round(sin_value(i) * (1 << 16))) & 0xFFFFFFFF

SIN_CFILE_WRAPPER = """const fixed_t sin_lut [%d] = {
%s
};

"""

def gen_sin_cfile_text():
	lut_lines = []
	for i in range(SIN_LUT_SIZE):
		val = sin_value(i)
		lut_value = sin_value_fixed(i)
		if i < SIN_LUT_SIZE - 1:
			lut_lines.append("    0x%08x, // %1.4f" % (lut_value, round(val, 4)))
		else:
			lut_lines.append("    0x%08x  // %1.4f" % (lut_value, round(val, 4)))
	return SIN_CFILE_WRAPPER % (SIN_LUT_SIZE, "\n".join(lut_lines))


def gen_cfile_text():
	return CFILE_HEADER + gen_fov_cfile_text(45, 90) + gen_sin_cfile_text()

print(gen_cfile_text())
