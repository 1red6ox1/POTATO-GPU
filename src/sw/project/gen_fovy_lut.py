# 2026 POTATO GPU Contributors

# LUT mapping FOVy between 45° and 90° to corresponding cot(FOVy/2) for perspective projection matrix
# Generated in C code

from math import tan, radians


def fov_coefficient(fovy: float):
	return 1.0 / tan(radians(fovy / 2.0))

def fov_coeff_fixed(fovy: float):
	return int(fov_coefficient(fovy) * (1 << 16)) & 0xFFFFFFFF

CFILE_WRAPPER = """#include "fixed_math.h"

const fixed_t fov_coeff_lut [%d] = {
%s
};

"""

def gen_cfile_text(fovy_min, fovy_max):
	fov_range = fovy_max - fovy_min + 1;
	lut_lines = []
	for i in range(fovy_min, fovy_max + 1):
		fov_coeff = fov_coefficient(i)
		lut_value = fov_coeff_fixed(i)
		if i < fovy_max:
			lut_lines.append("    0x%08x, // %1.2f" % (lut_value, round(fov_coeff, 2)))
		else:
			lut_lines.append("    0x%08x  // %1.2f" % (lut_value, round(fov_coeff, 2)))
	return CFILE_WRAPPER % (fov_range, "\n".join(lut_lines))

print(gen_cfile_text(45, 90))
