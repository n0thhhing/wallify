# Raccoon sprite

`raccoon.png` is the runtime source atlas: five horizontal 36×24 RGBA frames,
rendered at 3× with nearest-neighbor sampling and animated at 3 fps, matching
the Pixel Cat's sleep cycle. Sleep Zs and petting hearts use the shared effect.

`raccoon-source.png` preserves the artwork generated using the built-in imagegen
tool. Each cell was centered, cropped to a common vertical range, and reduced
with nearest-neighbor sampling. Transparency is binary in the runtime atlas.

Final imagegen prompt:

> Edit this five-frame sleeping raccoon sprite sheet. Make the raccoon MUCH CUTER and MUCH MORE PIXELATED: genuine tiny 32x20-pixel game sprite aesthetic enlarged with nearest-neighbor hard square pixel blocks. Chubby rounded bean body, oversized cute head, tiny closed happy eyes, tiny nose, small ears, short plump striped tail wrapped at front, cozy adorable sleeping pose. Maximum 8 flat colors: warm gray, charcoal outlines and eye mask, creamy muzzle, tiny blush peach cheek pixels. Remove all detailed fur shading, texture, gradients, blur, antialiasing, realism. Every edge should be a chunky stair-step pixel edge. Keep exactly FIVE consistent raccoons arranged in five equal cells in ONE HORIZONTAL ROW, all facing left, same size and baseline, only tiny breathing changes across frames. Transparent background with generous empty gaps. No letters, no Zs, no hearts, no labels, no grid. This must read as charming very low-resolution pixel game art, not a detailed illustration.

Regenerate the embedded binary with Python and Pillow:

```sh
python3 scripts/encode-sprite.py assets/sprites/raccoon.png src/assets/bin/raccoon_pixels.bin
```

The encoder uses the same RGBA run format as the cat and banana atlases;
the existing Zig decoder handles premultiplication when uploading the texture.
