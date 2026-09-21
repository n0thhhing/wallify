# Raccoon sprite

`raccoon.png` contains five horizontal 110×68 RGBA frames, drawn at native
size with nearest-neighbor texture sampling, matching the Pixel Cat's width.
The raccoon is an original design generated from scratch: a rounded sleeping
face, closed smiling eyes, silver-gray fur, cream cheeks, pink ears, tiny dark
paws and a fluffy striped tail. Fine shading stays readable at native size.

The five frames play at 3 fps (a 1⅔-second breathing cycle), matching the cat.
The torso rises by up to two native pixels and settles back down; the face,
paws and tail stay anchored. The first and last poses match at the seam.
Sleep Zs and petting hearts use the shared Pixel Cat effect.

`raccoon-source.png` is the artwork created with the built-in imagegen tool
without reference images, followed by a transparency cleanup pass. The exact
prompts are in `raccoon-prompt.txt`. Low-alpha halo pixels are removed before
reducing the artwork; the character's colors and shading are preserved.
`raccoon-preview.gif` shows the breathing loop;
its timing rounds to GIF's 10ms resolution.

Regenerate the atlas and embedded binary with Python and Pillow:

```sh
python3 scripts/prepare-raccoon.py
python3 scripts/encode-sprite.py assets/sprites/raccoon.png src/assets/bin/raccoon_pixels.bin
```

The binary uses the same RGBA run format as the cat and banana atlases.
The Zig decoder premultiplies alpha when uploading the texture.
