#!/usr/bin/env python3
"""Convert a slide image into the POTATO GPU framebuffer layout."""

from __future__ import annotations

import argparse
from pathlib import Path


FRAME_WIDTH = 1920
FRAME_HEIGHT = 1080
FRAME_ROW_STRIDE = 8192
TILE_WIDTH = 32
CHANNEL_STRIDE = TILE_WIDTH
TILE_STRIDE = 128
MAX_FRAME_WIDTH = (FRAME_ROW_STRIDE // TILE_STRIDE) * TILE_WIDTH
MAX_FRAME_HEIGHT = 2048


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Convert an exported slide image into the raw framebuffer format "
            "used by the POTATO GPU HDMI path."
        )
    )
    parser.add_argument("input", type=Path, help="input image, usually PNG or JPG")
    parser.add_argument("output", type=Path, help="output framebuffer binary")
    parser.add_argument(
        "--width",
        type=int,
        default=FRAME_WIDTH,
        help=f"target visible width in pixels, default {FRAME_WIDTH}",
    )
    parser.add_argument(
        "--height",
        type=int,
        default=FRAME_HEIGHT,
        help=f"target visible height in pixels, default {FRAME_HEIGHT}",
    )
    parser.add_argument(
        "--fit",
        choices=("contain", "stretch"),
        default="contain",
        help="resize mode: preserve aspect ratio with black padding, or stretch",
    )
    return parser.parse_args()


def validate_dimensions(width: int, height: int) -> None:
    if width <= 0:
        raise ValueError("--width must be positive")
    if height <= 0:
        raise ValueError("--height must be positive")
    if width % TILE_WIDTH != 0:
        raise ValueError(f"--width must be a multiple of {TILE_WIDTH}")
    if width > MAX_FRAME_WIDTH:
        raise ValueError(
            f"--width must be at most {MAX_FRAME_WIDTH} for the current row layout"
        )
    if height > MAX_FRAME_HEIGHT:
        raise ValueError(
            f"--height must be at most {MAX_FRAME_HEIGHT} for the current row layout"
        )


def load_pillow():
    try:
        from PIL import Image
    except ModuleNotFoundError as exc:
        raise SystemExit(
            "Pillow is required. Install project dependencies with "
            "`python3 -m pip install -r requirements.txt`."
        ) from exc

    return Image


def to_rgb_on_black(image, image_module):
    if image.mode in ("RGBA", "LA") or (
        image.mode == "P" and "transparency" in image.info
    ):
        rgba = image.convert("RGBA")
        background = image_module.new("RGBA", rgba.size, (0, 0, 0, 255))
        background.alpha_composite(rgba)
        return background.convert("RGB")

    return image.convert("RGB")


def resized_canvas(image, image_module, width: int, height: int, fit: str):
    if fit == "stretch":
        return image.resize((width, height), image_module.Resampling.LANCZOS)

    scale = min(width / image.width, height / image.height)
    resized_size = (
        max(1, round(image.width * scale)),
        max(1, round(image.height * scale)),
    )
    resized = image.resize(resized_size, image_module.Resampling.LANCZOS)

    canvas = image_module.new("RGB", (width, height), (0, 0, 0))
    offset = ((width - resized.width) // 2, (height - resized.height) // 2)
    canvas.paste(resized, offset)
    return canvas


def image_to_framebuffer(image, width: int, height: int) -> bytearray:
    framebuffer = bytearray(height * FRAME_ROW_STRIDE)
    pixels = image.load()

    for y in range(height):
        row_base = y * FRAME_ROW_STRIDE
        for chunk_x in range(width // TILE_WIDTH):
            chunk_base = row_base + chunk_x * TILE_STRIDE
            for pixel_x in range(TILE_WIDTH):
                r, g, b = pixels[chunk_x * TILE_WIDTH + pixel_x, y]
                framebuffer[chunk_base + 0 * CHANNEL_STRIDE + pixel_x] = r
                framebuffer[chunk_base + 1 * CHANNEL_STRIDE + pixel_x] = g
                framebuffer[chunk_base + 2 * CHANNEL_STRIDE + pixel_x] = b

    return framebuffer


def convert_image_file(
    input_path: Path,
    output_path: Path,
    width: int = FRAME_WIDTH,
    height: int = FRAME_HEIGHT,
    fit: str = "contain",
) -> int:
    validate_dimensions(width, height)
    if fit not in ("contain", "stretch"):
        raise ValueError("fit must be either 'contain' or 'stretch'")

    image_module = load_pillow()
    with image_module.open(input_path) as source:
        rgb = to_rgb_on_black(source, image_module)
        canvas = resized_canvas(rgb, image_module, width, height, fit)

    framebuffer = image_to_framebuffer(canvas, width, height)
    output_path.write_bytes(framebuffer)
    return len(framebuffer)


def main() -> None:
    args = parse_args()
    try:
        byte_count = convert_image_file(
            args.input,
            args.output,
            width=args.width,
            height=args.height,
            fit=args.fit,
        )
    except ValueError as exc:
        raise SystemExit(f"error: {exc}") from exc

    print(
        f"wrote {args.output} "
        f"({byte_count} bytes, {args.width}x{args.height}, {args.fit})"
    )


if __name__ == "__main__":
    main()
