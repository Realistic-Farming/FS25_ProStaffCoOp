#!/usr/bin/env python3
# Build the ProStaff mod icon in the Realistic Farming house style:
# cream rounded border, colored plate, "REALISTIC FARMING" header, a center
# glyph, a divider, and the mod name. Distinct plate colour: SLATE (green,
# navy, purple, brown, teal and barn-red are taken by the sibling mods).
# Glyph: a ladder = the 20-level Co-Op climb.
#
# Writes icon_source.png (512x512 RGBA) and icon.dds (512x512 uncompressed
# BGRA, the exact format FS25 loads, matching DairyCore's icon.dds).
import os, struct
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, ".."))

SIZE = 512
SS = 2                      # supersample factor for clean edges
S = SIZE * SS

# Palette (slate plate, warm-cream ink to match the family).
INK = (238, 231, 210, 255)          # warm cream: border, text, glyph
BG_CENTER = (62, 77, 92)            # slate, lighter core
BG_EDGE = (30, 39, 48)              # slate, darker rim
ARIAL_BD = "C:/Windows/Fonts/arialbd.ttf"
ARIAL_BLK = "C:/Windows/Fonts/ariblk.ttf"


def radial_bg(size, c_center, c_edge):
    """Vertical-ish radial gradient plate, darker toward the corners."""
    img = Image.new("RGB", (size, size), c_edge)
    px = img.load()
    cx, cy = size / 2.0, size / 2.0
    maxd = (cx ** 2 + cy ** 2) ** 0.5
    for y in range(size):
        for x in range(size):
            d = ((x - cx) ** 2 + (y - cy) ** 2) ** 0.5 / maxd
            d = min(1.0, d)
            px[x, y] = tuple(
                int(c_center[i] + (c_edge[i] - c_center[i]) * d) for i in range(3)
            )
    return img


def rounded_border(draw, size, inset, radius, color, width):
    box = [inset, inset, size - inset, size - inset]
    draw.rounded_rectangle(box, radius=radius, outline=color, width=width)


def centered_text(draw, cy, text, font, fill, size):
    l, t, r, b = draw.textbbox((0, 0), text, font=font)
    w, h = r - l, b - t
    draw.text(((size - w) / 2 - l, cy - h / 2 - t), text, font=font, fill=fill)


def ladder(draw, color, cx, top, bottom, rail_w, rail_gap, rungs):
    """A cream ladder: two rails + evenly spaced rungs, rounded caps."""
    lx = cx - rail_gap / 2
    rx = cx + rail_gap / 2
    r = rail_w / 2
    # rails
    draw.rounded_rectangle([lx - r, top, lx + r, bottom], radius=r, fill=color)
    draw.rounded_rectangle([rx - r, top, rx + r, bottom], radius=r, fill=color)
    # rungs (inset a touch inside the rails)
    rung_h = rail_w * 0.85
    inner_top = top + rail_w * 1.1
    inner_bot = bottom - rail_w * 1.1
    span = inner_bot - inner_top
    for i in range(rungs):
        y = inner_top + span * i / (rungs - 1)
        rr = rung_h / 2
        draw.rounded_rectangle([lx - r * 0.2, y - rr, rx + r * 0.2, y + rr],
                               radius=rr, fill=color)


def build_png():
    img = radial_bg(S, BG_CENTER, BG_EDGE).convert("RGBA")
    draw = ImageDraw.Draw(img)

    f_top = ImageFont.truetype(ARIAL_BD, int(46 * SS))
    f_bot = ImageFont.truetype(ARIAL_BLK, int(60 * SS))

    # cream rounded border
    rounded_border(draw, S, int(14 * SS), int(30 * SS), INK, int(5 * SS))

    # top header
    centered_text(draw, int(56 * SS), "REALISTIC FARMING", f_top, INK, S)

    # center ladder glyph
    ladder(draw, INK, cx=S / 2, top=int(150 * SS), bottom=int(372 * SS),
           rail_w=int(20 * SS), rail_gap=int(120 * SS), rungs=6)

    # divider line above the mod name
    dy = int(410 * SS)
    dw = int(150 * SS)
    draw.line([(S / 2 - dw, dy), (S / 2 + dw, dy)], fill=INK, width=int(3 * SS))

    # bottom mod name
    centered_text(draw, int(454 * SS), "PRO STAFF", f_bot, INK, S)

    img = img.resize((SIZE, SIZE), Image.LANCZOS)
    out = os.path.join(ROOT, "icon_source.png")
    img.save(out)
    print("Wrote", out)
    return img


def write_dds(img, path):
    """Write a 512x512 uncompressed BGRA DDS (FS25-compatible)."""
    img = img.convert("RGBA")
    w, h = img.size
    pitch = w * 4
    # DDS header (124 bytes after the 4-byte magic)
    flags = 0x1 | 0x2 | 0x4 | 0x1000 | 0x8    # CAPS|HEIGHT|WIDTH|PIXELFORMAT|PITCH
    header = b"DDS "
    header += struct.pack("<I", 124)          # dwSize
    header += struct.pack("<I", flags)
    header += struct.pack("<I", h)
    header += struct.pack("<I", w)
    header += struct.pack("<I", pitch)        # dwPitchOrLinearSize
    header += struct.pack("<I", 0)            # depth
    header += struct.pack("<I", 0)            # mipMapCount
    header += b"\x00" * 44                    # 11 reserved dwords
    # ddspf pixel format (32 bytes)
    header += struct.pack("<I", 32)          # pf size
    header += struct.pack("<I", 0x41)        # DDPF_ALPHAPIXELS | DDPF_RGB
    header += struct.pack("<I", 0)           # fourCC
    header += struct.pack("<I", 32)          # rgbBitCount
    header += struct.pack("<I", 0x00FF0000)  # R mask
    header += struct.pack("<I", 0x0000FF00)  # G mask
    header += struct.pack("<I", 0x000000FF)  # B mask
    header += struct.pack("<I", 0xFF000000)  # A mask
    header += struct.pack("<I", 0x1000)      # caps  DDSCAPS_TEXTURE
    header += struct.pack("<I", 0)           # caps2
    header += struct.pack("<I", 0)           # caps3
    header += struct.pack("<I", 0)           # caps4
    header += struct.pack("<I", 0)           # reserved2
    assert len(header) == 128, len(header)

    # pixel data as BGRA, top-to-bottom
    data = bytearray()
    px = img.load()
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            data += bytes((b, g, r, a))

    with open(path, "wb") as f:
        f.write(header)
        f.write(data)
    print("Wrote", path, "(%d bytes)" % (128 + len(data)))


def main():
    img = build_png()
    write_dds(img, os.path.join(ROOT, "icon.dds"))


if __name__ == "__main__":
    main()
