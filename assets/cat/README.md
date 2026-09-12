# Cat artwork

The animations use PNG images containing multiple frames:

- `cat.png`: 1426×138; all five sleeping frames, packed side by side.
- `banana-cat.png`: 98×5130; 45 vertically stacked 98×114 frames at 24 fps.

`build.zig` runs `tools/decode-cat.swift`, checks dimensions, and stores decoded
pixel data in Zig's build cache. The renderers embed named build inputs
`cat_pixels` and `banana_pixels`. No raw `.bin` or `.rgba` files belong in this
folder or `src/`, and no image decoding happens during animation.

From the project root:

```sh
zig build              # Decode changed PNGs and build the player
zig build test
zig build preview-cat  # Sample the current cat renderer
./scripts/preview.sh   # Render, convert to PNG, and open
```

The preview writes `/tmp/wallify-poses.ppm`. Asset conversion requires Swift and
Apple's CoreGraphics/ImageIO frameworks (Xcode or Command Line Tools).
