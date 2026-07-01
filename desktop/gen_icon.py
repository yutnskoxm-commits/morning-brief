#!/usr/bin/env python3
"""
Generate FinFlash app icon as PNG files for .icns creation.
Pure Python — no external dependencies needed.
"""
import struct
import zlib
import sys
import os

OUTPUT_DIR = sys.argv[1] if len(sys.argv) > 1 else "AppIcon.iconset"

# Icon sizes macOS requires for .icns
SIZES = [16, 32, 64, 128, 256, 512, 1024]

# Colors
BG = (0x16, 0x18, 0x26)        # Dark navy background
YELLOW = (0xFD, 0xD8, 0x35)    # FinFlash yellow/gold
YELLOW_DIM = (0xD4, 0xA0, 0x17)  # Shadow/darker yellow


def create_png(width: int, height: int) -> bytes:
    """Generate a PNG with a lightning bolt icon."""

    # Build RGBA pixel data (row by row, top to bottom)
    rows = []
    for y in range(height):
        row = bytearray()
        for x in range(width):
            r, g, b, a = draw_pixel(x, y, width, height)
            row.extend([r, g, b, a])
        rows.append(bytes(row))

    raw = b''.join(rows)

    # Helper: create a PNG chunk
    def chunk(chunk_type: bytes, data: bytes) -> bytes:
        c = chunk_type + data
        crc = struct.pack('>I', zlib.crc32(c) & 0xFFFFFFFF)
        return struct.pack('>I', len(data)) + c + crc

    # IHDR
    ihdr = struct.pack('>IIBBBBB', width, height, 8, 6, 0, 0, 0)  # 8-bit RGBA, no palette, no interlace

    # IDAT — filter byte 0 (None) before each row
    filtered = b''
    for i in range(height):
        filtered += b'\x00'  # filter: None
        filtered += raw[i * width * 4:(i + 1) * width * 4]

    # PNG signature + chunks
    return (
        b'\x89PNG\r\n\x1a\n' +
        chunk(b'IHDR', ihdr) +
        chunk(b'IDAT', zlib.compress(filtered)) +
        chunk(b'IEND', b'')
    )


def draw_pixel(x: int, y: int, w: int, h: int) -> tuple:
    """Return (r, g, b, a) for a given pixel."""

    cx, cy = w / 2, h / 2        # center
    s = w / 1024.0                # scale factor for 1024-base design
    dx = (x - cx) / s
    dy = (y - cy) / s

    # Background — rounded rect feel with slight gradient
    bg_intensity = 0
    r, g, b = BG
    a = 255

    # Circular background mask (rounded corners look)
    dist_from_center = (dx**2 + dy**2)**0.5
    max_radius = 480  # radius for the main circle
    corner_radius = 440

    if dist_from_center > max_radius:
        # Outside the icon circle — fully transparent
        return (0, 0, 0, 0)

    # Lightning bolt shape (polygon)
    if is_lightning(dx, dy):
        # Main bolt fill
        return YELLOW + (255,)
    elif is_lightning(dx + 3, dy) or is_lightning(dx - 3, dy) or is_lightning(dx, dy + 3) or is_lightning(dx, dy - 3):
        return YELLOW + (255,)
    elif is_lightning(dx + 8, dy) or is_lightning(dx - 8, dy):
        return YELLOW_DIM + (180,)

    # Background fill
    return BG + (255,)


def is_lightning(dx: float, dy: float) -> bool:
    """Check if a point (dx, dy) is inside the lightning bolt shape.
    The bolt goes from top-center to bottom-right, with a zigzag.
    """

    # Normalize to roughly -500..500 range
    # Lightning bolt path in local coordinates:
    # Points: (0, -420) top → (-80, -60) → (50, -80) → (-30, 180) → (60, 150) → (0, 420) bottom
    if dy < -430 or dy > 430:
        return False

    # Define the left and right edges of the bolt at normalized y
    def left_edge(yy: float) -> float:
        """Left boundary of bolt at given y."""
        # Segment 1: top point to upper zig
        if yy < -60:
            t = (yy + 420) / (-60 + 420)
            return lerp(0, -80, t) - 30
        # Segment 2: upper zig to middle zag
        elif yy < 150:
            t = (yy + 60) / (150 + 60)
            return lerp(-80, -30, t) - 30
        # Segment 3: middle zag to bottom
        else:
            t = (yy - 150) / (420 - 150)
            return lerp(-30, 0, t) - 30

    def right_edge(yy: float) -> float:
        """Right boundary of bolt at given y."""
        # Segment 1: top point to upper zig
        if yy < -80:
            t = (yy + 420) / (-80 + 420)
            return lerp(0, 50, t) + 30
        # Segment 2: upper zig to middle zag
        elif yy < 180:
            t = (yy + 80) / (180 + 80)
            return lerp(50, 60, t) + 30
        # Segment 3: middle zag to bottom
        else:
            t = (yy - 180) / (420 - 180)
            return lerp(60, 0, t) + 30

    le = left_edge(dy)
    re = right_edge(dy)
    return le <= dx <= re


def lerp(a: float, b: float, t: float) -> float:
    return a + (b - a) * max(0, min(1, t))


def main():
    os.makedirs(OUTPUT_DIR, exist_ok=True)

    for size in SIZES:
        png_data = create_png(size, size)
        if size == 1024:
            # Base size
            path = os.path.join(OUTPUT_DIR, f"icon_512x512@2x.png")
        elif size == 512:
            path = os.path.join(OUTPUT_DIR, f"icon_256x256@2x.png")
            path2 = os.path.join(OUTPUT_DIR, f"icon_512x512.png")
            with open(path2, 'wb') as f:
                f.write(png_data)
        elif size == 256:
            path = os.path.join(OUTPUT_DIR, f"icon_128x128@2x.png")
            path2 = os.path.join(OUTPUT_DIR, f"icon_256x256.png")
            with open(path2, 'wb') as f:
                f.write(png_data)
        elif size == 128:
            path = os.path.join(OUTPUT_DIR, f"icon_128x128.png")
        elif size == 64:
            path = os.path.join(OUTPUT_DIR, f"icon_32x32@2x.png")
            path2 = os.path.join(OUTPUT_DIR, f"icon_64x64.png")
            with open(path2, 'wb') as f:
                f.write(png_data)
        elif size == 32:
            path = os.path.join(OUTPUT_DIR, f"icon_32x32.png")
            path2 = os.path.join(OUTPUT_DIR, f"icon_16x16@2x.png")
            with open(path2, 'wb') as f:
                f.write(png_data)
        elif size == 16:
            path = os.path.join(OUTPUT_DIR, f"icon_16x16.png")
        else:
            continue

        with open(path, 'wb') as f:
            f.write(png_data)

    print(f"  Generated {len(SIZES)} icon sizes in {OUTPUT_DIR}")


if __name__ == '__main__':
    main()
