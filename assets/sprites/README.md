# Raccoon sprite

`raccoon.png` is the runtime source atlas: five horizontal 40×28 RGBA frames,
rendered at 3× with nearest-neighbor sampling and an eight-color palette.
The 3.6-second breathing cycle uses frame durations of 900, 400, 700, 500,
and 1100 ms. The first and last poses match for a seamless resting pause.
Sleep Zs and petting hearts use the shared Pixel Cat effect.

`raccoon-source.png` preserves the artwork generated using the built-in imagegen
tool. The first pose is reduced with nearest-neighbor sampling and quantized
to flat colors. The upper back expands by up to two pixels while the head,
paws and foreground tail remain anchored. Transparency is binary.

The current generation prompt is in `raccoon-prompt.txt`. The animated
`raccoon-preview.gif` uses the runtime frame durations on the idle card color.

Regenerate the embedded binary with Python and Pillow:

```sh
python3 scripts/prepare-raccoon.py
python3 scripts/encode-sprite.py assets/sprites/raccoon.png src/assets/bin/raccoon_pixels.bin
```

The encoder uses the same RGBA run format as the cat and banana atlases;
the existing Zig decoder handles premultiplication when uploading the texture.
