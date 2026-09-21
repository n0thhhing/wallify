# Raccoon sprite

`raccoon.png` is the runtime source atlas: five horizontal 48×32 RGBA frames,
rendered at 2× with nearest-neighbor sampling and animated at 3 fps, matching
the Pixel Cat's sleep cycle. Sleep Zs and petting hearts use the shared effect.

`raccoon-source.png` preserves the artwork generated using the built-in imagegen
tool. Each cell was centered, cropped to a common vertical range, and reduced
with nearest-neighbor sampling. Transparency is binary in the runtime atlas.

Final imagegen prompt:

> Create a beautiful professional indie-game pixel art sprite sheet: five animation frames in one horizontal row, transparent background. A VERY CUTE SLEEPING BABY RACCOON curled into a low soft oval, big ROUND head on left resting on little cream paws, petite button nose, TWO gently closed smiling eyelids clearly readable in medium-charcoal mask, rounded cream-rimmed ears, fluffy silver-gray body, plump ringed tail wrapping around right side and under chin. Kawaii proportions, peaceful expression, soft warm-gray and cream palette with peach blush, confident dark-brown pixel outline. Low-resolution 48x32 sprite art with crisp blocky square pixels, clean pixel clusters and 8 flat colors, NO gradient NO fuzzy texture NO photorealism. Five matching frames with only a subtle breathing rise and fall; same character size, same baseline, identical face, tail and paws anchored. Each sprite takes up its equal-width cell, generous transparent gap between them. No text, letters, Z, hearts, shadow, grid or environment. Visually polished, lovable and readable at 100 pixels wide. Landscape image.

Regenerate the embedded binary with Python and Pillow:

```sh
python3 scripts/encode-sprite.py assets/sprites/raccoon.png src/assets/bin/raccoon_pixels.bin
```

The encoder uses the same RGBA run format as the cat and banana atlases;
the existing Zig decoder handles premultiplication when uploading the texture.
