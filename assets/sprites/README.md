# Raccoon sprite

`raccoon.png` contains five horizontal 110×68 RGBA frames, drawn at native
size with nearest-neighbor texture sampling, matching the Pixel Cat's width.
The raccoon keeps its curled-up pose with the flat tan-and-gray pixel-art
style of the user's `pixiplus-raccoon-7723089_1920.png` reference. Six colors
sampled from that reference preserve the simple mask and deadpan expression.
The face is no longer enlarged from a coarse 40×28 sprite.

The five frames play at 3 fps (a 1⅔-second breathing cycle), matching the cat.
The torso rises by up to two native pixels and settles back down; the face,
paws and tail stay anchored. The first and last poses match at the seam.
Sleep Zs and petting hearts use the shared Pixel Cat effect.

`raccoon-source.png` is the artwork created with the built-in imagegen tool
for the curled-up raccoon, using the supplied image for style and the previous
sprite for pose. The exact prompt is in `raccoon-prompt.txt`. Nearest-neighbor
reduction, palette mapping and binary alpha keep the pixel edges and flat
colors crisp. `raccoon-preview.gif` shows the breathing loop;
its timing rounds to GIF's 10ms resolution.

Regenerate the atlas and embedded binary with Python and Pillow:

```sh
python3 scripts/prepare-raccoon.py
python3 scripts/encode-sprite.py assets/sprites/raccoon.png src/assets/bin/raccoon_pixels.bin
```

The binary uses the same RGBA run format as the cat and banana atlases.
The Zig decoder premultiplies alpha when uploading the texture.
