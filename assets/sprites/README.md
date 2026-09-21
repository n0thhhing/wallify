# Raccoon sprite

`raccoon.png` contains five horizontal 110×68 RGBA frames, drawn at native
size with nearest-neighbor texture sampling, matching the Pixel Cat's width.
The raccoon keeps its curled-up pose with a finer shaded pixel-art style.
The face is no longer enlarged from a coarse 40×28 sprite.

The five frames play at 3 fps (a 1⅔-second breathing cycle), matching the cat.
The torso rises by up to two native pixels and settles back down; the face,
paws and tail stay anchored. The first and last poses match at the seam.
Sleep Zs and petting hearts use the shared Pixel Cat effect.

`raccoon-source.png` is the artwork created with the built-in imagegen tool
for the curled-up raccoon. The exact
prompt is in `raccoon-prompt.txt`. Fine shading and edge alpha are preserved
when reducing the artwork. `raccoon-preview.gif` shows the breathing loop;
its timing rounds to GIF's 10ms resolution.

Regenerate the atlas and embedded binary with Python and Pillow:

```sh
python3 scripts/prepare-raccoon.py
python3 scripts/encode-sprite.py assets/sprites/raccoon.png src/assets/bin/raccoon_pixels.bin
```

The binary uses the same RGBA run format as the cat and banana atlases.
The Zig decoder premultiplies alpha when uploading the texture.
