#!/usr/bin/env python3
"""Prepare the raccoon atlas and anchored breathing frames (requires Pillow)."""
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
source = Image.open(ROOT / "assets/sprites/raccoon-source.png").convert("RGBA")
cell = source.crop((0, 0, round(source.width / 5), source.height))
left, top, right, bottom = cell.getchannel("A").point(lambda a: 255 if a >= 128 else 0).getbbox()
base = cell.crop((left - 5, top - 10, right + 5, bottom + 5)).resize((40, 28), Image.Resampling.NEAREST)

# Flat color clusters keep the small sprite readable and remove generated dithering.
palette = [(36, 29, 25), (57, 49, 43), (86, 77, 70), (119, 110, 103),
           (153, 144, 135), (190, 178, 159), (252, 231, 197), (230, 155, 119)]
pixels = []
for r, g, b, a in base.getdata():
    if a < 128:
        pixels.append((0, 0, 0, 0))
    else:
        color = min(palette, key=lambda c: (c[0]-r)**2 + (c[1]-g)**2 + (c[2]-b)**2)
        pixels.append((*color, 255))
base.putdata(pixels)

frames = []
for rise in (0, 1, 2, 1, 0):
    frame = base.copy()
    # Expand only the upper back. The face, ears, paws and foreground tail
    # remain exactly the same pixels in every frame. Taper at both shoulders.
    for x in range(25, 39):
        lift = round(rise * min(1, (x - 24) / 4, (39 - x) / 4))
        for y in range(17):
            source_y = round(17 - (17 - y) * 17 / (17 + lift))
            frame.putpixel((x, y), base.getpixel((x, max(0, source_y))))
    frames.append(frame)

sheet = Image.new("RGBA", (200, 28))
for index, frame in enumerate(frames):
    sheet.paste(frame, (index * 40, 0))
sheet.save(ROOT / "assets/sprites/raccoon.png")

# Preview uses the same frame durations as the runtime on the idle card color.
preview = []
for frame in frames:
    background = Image.new("RGBA", frame.size, (30, 29, 32, 255))
    background.alpha_composite(frame)
    preview.append(background.convert("RGB").resize((240, 168), Image.Resampling.NEAREST))
preview[0].save(ROOT / "assets/sprites/raccoon-preview.gif", save_all=True,
                append_images=preview[1:], duration=[900, 400, 700, 500, 1100], loop=0)
