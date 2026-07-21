import argparse
import json
import struct
import sys
from pathlib import Path

from PIL import Image, ImageSequence


def load_composited_frames(path):
    """
    Load every frame of a GIF, compositing each one onto a running
    canvas so that partial-frame GIFs (common disposal method
    optimizations) are decoded correctly. Returns a list of
    (RGBA Image, duration_ms) tuples at the GIF's native size.
    """
    im = Image.open(path)

    frames = []
    canvas = Image.new("RGBA", im.size, (0, 0, 0, 0))

    for frame in ImageSequence.Iterator(im):
        duration = frame.info.get("duration", 100)
        frame_rgba = frame.convert("RGBA")
        canvas = Image.alpha_composite(canvas, frame_rgba)
        frames.append((canvas.copy(), duration))

    return frames


def flatten_alpha(rgba_image, bg=(0, 0, 0)):
    """Flatten an RGBA image onto a solid background, returning RGB."""
    background = Image.new("RGB", rgba_image.size, bg)
    background.paste(rgba_image, mask=rgba_image.split()[3])
    return background


def build_global_palette(rgb_frames, num_colors):
    """
    Given a list of same-sized RGB images (already resized), build one
    shared palette of up to `num_colors` colors that best represents
    all of them combined.

    Approach: stitch all frames into one tall image and let Pillow's
    high-quality quantizer (libimagequant if available, else the
    median-cut/octree quantizer) pick the best shared palette.
    """
    if not rgb_frames:
        raise ValueError("No frames to build a palette from.")

    w, h = rgb_frames[0].size
    n = len(rgb_frames)

    combined = Image.new("RGB", (w, h * n))
    for i, frame in enumerate(rgb_frames):
        combined.paste(frame, (0, i * h))

    # method=Image.Quantize.LIBIMAGEQUANT would be ideal but isn't
    # always compiled in; MEDIANCUT is the reliable, always-available
    # high quality option.
    quantized = combined.quantize(
        colors=num_colors,
        method=Image.Quantize.MEDIANCUT,
        dither=Image.Dither.NONE,
    )

    raw_palette = quantized.getpalette()  # flat [r,g,b,r,g,b,...] length 768
    # Determine how many colors are actually in use.
    color_count = len(quantized.getcolors(maxcolors=num_colors) or [])
    color_count = max(color_count, 1)

    palette = [
        tuple(raw_palette[i * 3: i * 3 + 3])
        for i in range(min(num_colors, 256))
    ]
    # Trim any unused trailing black padding Pillow adds beyond the
    # colors actually found, but keep at least `color_count` entries.
    palette = palette[:max(color_count, 1)]

    return palette, quantized


def indices_for_frame(rgb_frame, palette_image, dither):
    """
    Map a single RGB frame onto the given shared palette, returning a
    flat list of 8-bit palette indices (length = width * height).
    """
    dither_mode = Image.Dither.FLOYDSTEINBERG if dither else Image.Dither.NONE
    p_frame = rgb_frame.quantize(palette=palette_image, dither=dither_mode)
    if hasattr(p_frame, "get_flattened_data"):
        return list(p_frame.get_flattened_data())
    return list(p_frame.getdata())  # Pillow < 12 fallback


def image_to_chunks(image_path, num_colors=256, dither=False,
                    image_size=(128, 128), chunk_size=32):
    if image_size[0] % chunk_size != 0 or image_size[1] % chunk_size != 0:
        raise ValueError("image_size must be evenly divisible by chunk_size")

    im = Image.open(image_path).convert("RGBA")
    resized = im.resize(image_size, Image.LANCZOS)
    rgb = flatten_alpha(resized)

    palette, palette_image = build_global_palette([rgb], num_colors)

    full_indices = indices_for_frame(rgb, palette_image, dither)

    width, height = image_size
    cols = width // chunk_size
    rows = height // chunk_size

    chunks = []
    for chunk_row in range(rows):
        for chunk_col in range(cols):
            chunk_indices = []
            base_y = chunk_row * chunk_size
            base_x = chunk_col * chunk_size
            for ly in range(chunk_size):
                row_start = (base_y + ly) * width + base_x
                chunk_indices.extend(full_indices[row_start:row_start + chunk_size])
            chunks.append(chunk_indices)

    return palette, chunks


def convert_gif(input_path, size, num_colors, dither):
    frames_raw = load_composited_frames(input_path)

    resized_rgb = []
    durations = []
    for rgba_frame, duration in frames_raw:
        resized = rgba_frame.resize(size, Image.LANCZOS)
        resized_rgb.append(flatten_alpha(resized))
        durations.append(duration)

    palette, palette_image = build_global_palette(resized_rgb, num_colors)

    frame_indices = [
        indices_for_frame(frame, palette_image, dither)
        for frame in resized_rgb
    ]

    return palette, frame_indices, durations


def write_json(out_path, size, palette, frame_indices, durations):
    data = {
        "width": size[0],
        "height": size[1],
        "num_colors": len(palette),
        "palette": [list(c) for c in palette],
        "frames": [
            {"duration_ms": dur, "indices": idxs}
            for dur, idxs in zip(durations, frame_indices)
        ],
    }
    with open(out_path, "w") as f:
        json.dump(data, f)


def write_binary(out_path, size, palette, frame_indices, durations):
    w, h = size
    with open(out_path, "wb") as f:
        f.write(struct.pack("<HHHH", w, h, len(palette), len(frame_indices)))
        for r, g, b in palette:
            f.write(struct.pack("<BBB", r, g, b))
        for dur, idxs in zip(durations, frame_indices):
            f.write(struct.pack("<I", dur))
            f.write(bytes(idxs))
