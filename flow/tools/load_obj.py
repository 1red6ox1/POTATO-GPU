#!/usr/bin/env python3
"""
obj_to_triangle_bin.py

Loads a Wavefront OBJ file and converts its geometry into a contiguous
binary blob matching the in-memory layout of the C struct:

    typedef struct {
        fixed_t x;   // int32_t, 16.16 fixed point
        fixed_t y;
        fixed_t z;
    } vertex_t;

    typedef struct {
        vertex_t a;
        vertex_t b;
        vertex_t c;
        uv_desc_t uv;   // uint8_t
        uint8_t   texid;
    } triangle_t;

`uv` and `texid` are NOT derived from the OBJ file -- they are constants
set from Python, since triangle_t only carries one uv_desc_t per
triangle (not per-vertex texture coordinates), matching how the
original cube_triangles table works.

Usage as a library:
    from obj_to_triangle_bin import convert_obj_to_bin
    convert_obj_to_bin("cube.obj", "cube_triangles.bin", uv=0b011000, texid=0)

Usage from the command line:
    python3 obj_to_triangle_bin.py input.obj output.bin --uv 0b011000 --texid 0
"""

import argparse
import struct
import sys
from dataclasses import dataclass
from typing import Dict, List, Optional, Tuple

FIXED_SHIFT = 16          # 16.16 fixed point
FIXED_ONE = 1 << FIXED_SHIFT
INT32_MIN = -(1 << 31)
INT32_MAX = (1 << 31) - 1

# Struct layout constants for triangle_t.
# vertex_t is 3 x int32_t (12 bytes), so a/b/c together are 36 bytes.
# uv (uint8_t) + texid (uint8_t) add 2 bytes -> 38 bytes "logical" size.
# Most 32-bit ABIs (e.g. ARM EABI, x86) align structs containing int32_t
# members to a 4-byte boundary and pad the overall struct size up to a
# multiple of that alignment, giving a real sizeof(triangle_t) of 40
# bytes (2 bytes of trailing padding). If the target build uses
# #pragma pack(1) (or __attribute__((packed))), the true size is 38
# bytes with no padding. Both are supported below.
LOGICAL_SIZE = 38
PACKED_ALIGN_4_SIZE = 40


@dataclass
class Vertex:
    x: float
    y: float
    z: float


@dataclass
class Triangle:
    a: Vertex
    b: Vertex
    c: Vertex
    uv: int
    texid: int


def to_fixed(value: float) -> int:
    """Convert a float to a 16.16 fixed-point int32, rounding to nearest."""
    fixed = round(value * FIXED_ONE)
    if fixed < INT32_MIN or fixed > INT32_MAX:
        raise ValueError(
            f"value {value} overflows int32 16.16 fixed point "
            f"(fixed={fixed}); scale your mesh down or increase precision"
        )
    return fixed


def _parse_face_vertex_index(token: str, vertex_count: int) -> int:
    """
    Parse a single OBJ face token like 'v', 'v/vt', 'v//vn', or 'v/vt/vn'
    and return the 0-based vertex index (handling OBJ's 1-based and
    negative/relative indices).
    """
    v_index_str = token.split("/")[0]
    v_index = int(v_index_str)
    if v_index > 0:
        return v_index - 1
    else:
        # Negative indices are relative to the current end of the vertex list.
        return vertex_count + v_index


def load_obj_triangles(
    obj_path: str,
    uv: int,
    texid: int,
    material_texid_map: Optional[Dict[str, int]] = None,
) -> List[Triangle]:
    """
    Parse an OBJ file and return a flat list of Triangle objects.
    Polygonal (>3 vertex) faces are fan-triangulated. `uv` and `texid`
    are applied to every triangle unless material_texid_map is given,
    in which case the texid for a face is looked up from the most
    recent `usemtl` name (falling back to the constant `texid` if the
    material isn't in the map).
    """
    positions: List[Vertex] = []
    triangles: List[Triangle] = []
    current_texid = texid

    with open(obj_path, "r") as f:
        for line_no, raw_line in enumerate(f, start=1):
            line = raw_line.strip()
            if not line or line.startswith("#"):
                continue

            parts = line.split()
            keyword = parts[0]

            if keyword == "v":
                if len(parts) < 4:
                    raise ValueError(f"{obj_path}:{line_no}: malformed 'v' line")
                x, y, z = float(parts[1]), float(parts[2]), float(parts[3])
                positions.append(Vertex(x, y, z))

            elif keyword == "usemtl" and material_texid_map is not None:
                material_name = parts[1] if len(parts) > 1 else ""
                current_texid = material_texid_map.get(material_name, texid)

            elif keyword == "f":
                face_tokens = parts[1:]
                if len(face_tokens) < 3:
                    raise ValueError(f"{obj_path}:{line_no}: face has fewer than 3 vertices")

                indices = [
                    _parse_face_vertex_index(tok, len(positions))
                    for tok in face_tokens
                ]

                # Fan triangulation, preserving the face's original
                # vertex winding order (OBJ faces are typically
                # specified counter-clockwise around the outward
                # normal, same convention as cube_triangles).
                anchor = indices[0]
                for i in range(1, len(indices) - 1):
                    ia, ib, ic = anchor, indices[i], indices[i + 1]
                    try:
                        va, vb, vc = positions[ia], positions[ib], positions[ic]
                    except IndexError as exc:
                        raise ValueError(
                            f"{obj_path}:{line_no}: face references vertex "
                            f"index out of range"
                        ) from exc
                    triangles.append(
                        Triangle(
                            a=va,
                            b=vc,
                            c=vb,
                            uv=uv,
                            texid=current_texid,
                        )
                    )

            # All other keywords (vt, vn, o, g, s, mtllib, etc.) are
            # ignored: per-vertex texture coords/normals have no home
            # in triangle_t, which only stores one uv_desc_t per triangle.

    return triangles


def pack_triangle(tri: Triangle, packed: bool) -> bytes:
    """
    Pack a single Triangle into bytes matching triangle_t's memory
    layout. `packed=True` emits the 38-byte #pragma pack(1) layout;
    `packed=False` emits the 40-byte layout with 2 bytes of trailing
    padding, matching default 4-byte struct alignment on most 32-bit
    targets.
    """
    fixed_coords = (
        to_fixed(tri.a.x), to_fixed(tri.a.y), to_fixed(tri.a.z),
        to_fixed(tri.b.x), to_fixed(tri.b.y), to_fixed(tri.b.z),
        to_fixed(tri.c.x), to_fixed(tri.c.y), to_fixed(tri.c.z),
    )

    if not (0 <= tri.uv <= 0xFF):
        raise ValueError(f"uv value {tri.uv!r} does not fit in a uint8_t")
    if not (0 <= tri.texid <= 0xFF):
        raise ValueError(f"texid value {tri.texid!r} does not fit in a uint8_t")

    # '<' = little-endian (assumed target byte order; flip to '>' if needed)
    body = struct.pack("<9i", *fixed_coords)
    body += struct.pack("<BB", tri.uv, tri.texid)

    if packed:
        return body  # exactly LOGICAL_SIZE (38) bytes
    else:
        return body + b"\x00" * (PACKED_ALIGN_4_SIZE - LOGICAL_SIZE)  # pad to 40


def convert_obj_to_bin(
    obj_path: str,
    output_path: str,
    uv: int = 0b011000,
    texid: int = 0,
    packed: bool = False,
    material_texid_map: Optional[Dict[str, int]] = None,
) -> int:
    """
    Top-level entry point: load `obj_path`, convert every triangle to
    the triangle_t binary layout, and write the concatenated result to
    `output_path`.

    Args:
        obj_path: path to the input .obj file.
        output_path: path to write the raw binary triangle_t array to.
        uv: constant uv_desc_t value applied to every triangle
            (e.g. 0b011000 or 0b011110, matching the existing convention).
        texid: constant texture id applied to every triangle, unless
            overridden per-face via material_texid_map.
        packed: if True, emit the 38-byte #pragma pack(1) layout; if
            False (default), emit the 40-byte naturally-aligned layout.
        material_texid_map: optional dict mapping OBJ material names
            (from `usemtl`) to texid values, for meshes with multiple
            materials. Faces with no matching/declared material fall
            back to `texid`.

    Returns:
        The number of triangles written.
    """
    triangles = load_obj_triangles(
        obj_path, uv=uv, texid=texid, material_texid_map=material_texid_map
    )

    if not triangles:
        raise ValueError(f"no triangles found in {obj_path}")

    with open(output_path, "wb") as out:
        for tri in triangles:
            out.write(pack_triangle(tri, packed=packed))

    return len(triangles)


def _auto_int(value: str) -> int:
    """argparse helper that accepts decimal, hex (0x..), or binary (0b..) literals."""
    return int(value, 0)


def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(
        description="Convert an OBJ mesh into a binary triangle_t array."
    )
    parser.add_argument("obj_path", help="input .obj file")
    parser.add_argument("output_path", help="output .bin file")
    parser.add_argument(
        "--uv", type=_auto_int, default=0b011000,
        help="constant uv_desc_t value for every triangle (default: 0b011000)",
    )
    parser.add_argument(
        "--texid", type=_auto_int, default=0,
        help="constant texid for every triangle (default: 0)",
    )
    parser.add_argument(
        "--packed", action="store_true",
        help="emit the 38-byte #pragma pack(1) layout instead of the "
             "default 40-byte naturally-aligned layout",
    )
    args = parser.parse_args(argv)

    try:
        count = convert_obj_to_bin(
            args.obj_path,
            args.output_path,
            uv=args.uv,
            texid=args.texid,
            packed=args.packed,
        )
    except (OSError, ValueError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1

    struct_size = LOGICAL_SIZE if args.packed else PACKED_ALIGN_4_SIZE
    print(
        f"wrote {count} triangles ({count * struct_size} bytes, "
        f"{struct_size} bytes/triangle) to {args.output_path}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
