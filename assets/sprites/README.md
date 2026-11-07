# Sprite assets

`bin/` holds the checked-in PNG atlases used at runtime: Pixel Cat, Banana
Cat, and Raccoon. Keep these beside the sprite artwork rather than under
`src/`, which contains application code. The build copies them into
`build/resources/assets/`; packaging copies them into the app's
`Contents/Resources/assets/`. The runtime also checks `bin/` here when
running directly from the repository.

## Raccoon

`raccoon.png` contains five horizontal 110×68 RGBA frames, drawn at native
size with nearest-neighbor texture sampling, matching the Pixel Cat's width.
The raccoon is a rounded sleeping
face, closed smiling eyes, silver-gray fur, cream cheeks, pink ears, tiny dark
paws and a fluffy striped tail. Fine shading stays readable at native size.

The five frames play at 3 fps (a 1⅔-second breathing cycle), matching the cat.
The torso rises by up to two native pixels and settles back down; the face,
paws and tail stay anchored. The first and last poses match at the seam.
Sleep Zs and petting hearts use the shared Pixel Cat effect.

`raccoon-source.png` contains the source artwork. The preparation script
removes low-alpha halo pixels before scaling the artwork.
`raccoon-preview.gif` shows the breathing loop;
its timing rounds to GIF's 10ms resolution.

Regenerate the raccoon atlas with Python and Pillow, then copy it to the runtime assets:

```sh
python3 scripts/prepare-raccoon.py
cp assets/sprites/raccoon.png assets/sprites/bin/raccoon.png
```

The cat and banana atlases in `bin/` are the full-resolution PNGs recovered
from the previous runtime assets. ImageIO decodes all three into premultiplied
RGBA pixels before texture upload.
