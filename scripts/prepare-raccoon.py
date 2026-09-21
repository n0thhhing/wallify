#!/usr/bin/env python3
"""Prepare the reference-style curled raccoon atlas and breathing preview (requires Pillow)."""
from pathlib import Path
from math import sin, pi
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
source = Image.open(ROOT / "assets/sprites/raccoon-source.png").convert("RGBA")
box = source.getchannel("A").point(lambda a: 255 if a >= 128 else 0).getbbox()
body = source.crop(box)
body.thumbnail((108, 64), Image.Resampling.NEAREST)
base = Image.new("RGBA", (110, 68))
base.paste(body, ((110 - body.width) // 2, 67 - body.height))
# Flat colors sampled from the user's pixel-art style reference.
# Keep clean stepped edges and remove the generated image's subtle gradients.
palette = [(209, 210, 212), (0, 0, 0), (201, 192, 185),
           (169, 123, 80), (88, 88, 90), (118, 76, 41)]
pixels = []
for r, g, b, a in base.getdata():
    if a < 128:
        pixels.append((0, 0, 0, 0))
    else:
        color = min(palette, key=lambda c: (c[0] - r)**2 + (c[1] - g)**2 + (c[2] - b)**2)
        pixels.append((*color, 255))
base.putdata(pixels)

frames = []
for rise in (0, 1, 2, 1, 0):
    frame = base.copy()
    # Gently raise the torso, tapering to zero at the face and hind paws.
    # Native one-pixel motion keeps the breathing subtle at the cat's scale.
    for x in range(68, 106):
        lift = round(rise * sin(pi * (x - 67) / 39))
        top = next((y for y in range(36) if base.getpixel((x, y))[3] >= 128), 36)
        if top == 36 or lift == 0:
            continue
        for y in range(36):
            if y < top - lift:
                frame.putpixel((x, y), (0, 0, 0, 0))
            else:
                source_y = round(top + (y - top + lift) * (36 - top) / (36 - top + lift))
                frame.putpixel((x, y), base.getpixel((x, source_y)))
    frames.append(frame)

sheet = Image.new("RGBA", (550, 68))
for index, frame in enumerate(frames):
    sheet.paste(frame, (index * 110, 0))
sheet.save(ROOT / "assets/sprites/raccoon.png")

preview = []
for frame in frames:
    background = Image.new("RGBA", frame.size, (30, 29, 32, 255))
    background.alpha_composite(frame)
    preview.append(background.convert("RGB").resize((440, 272), Image.Resampling.NEAREST))
# GIF timing is quantized to 10ms; the runtime uses exactly 3fps like the cat.
preview[0].save(ROOT / "assets/sprites/raccoon-preview.gif", save_all=True,
                append_images=preview[1:], duration=[330, 340, 330, 330, 340], loop=0)
