# Wallify

A native macOS music widget written in Zig with an AppKit window and Metal GPU
renderer. Includes Spotify / system media metadata, playback controls, animated
artwork, and cat sprites. No terminal is needed to run the built app.

## Run

Build requirements: Zig **0.16.0**, Swift/Clang, and the Xcode Metal toolchain
(`xcrun metal` and `xcrun metallib`). A Metal-capable Mac is required.

```sh
./run.sh                 # Build ReleaseFast, package, and open Wallify.app
```

After building, open `zig-out/Wallify.app` from Finder. Drag the card to move it,
right-click for settings, and use the buttons and seek bar to control playback.
Quit from the music-note menu-bar item. There are no keyboard shortcuts, and the
widget does not take keyboard focus.

Bundled runs save preferences in `~/Library/Application Support/Wallify/`.
The bundled `widget-settings.conf` seeds the first launch; rebuilding does not
replace saved preferences. Bare executable development runs use the project root.

## Develop

```sh
zig build -Doptimize=ReleaseFast
zig build test
zig build preview-cat    # Offline sprite contact sheet: /tmp/wallify-poses.ppm
bash scripts/package-app.sh
```

If compiler caches are restricted, supply writable `--cache-dir` and
`--global-cache-dir` paths. The native bridge and Metal compiler use module
caches under `/tmp`. `zig build` without an optimization option builds Debug;
use ReleaseFast for performance measurements.

## Rendering

The live renderer submits a bounded list of drawing commands. Metal draws rounded
shapes, clipping, gradients, artwork transitions, text, controls, and both sprite
animations. Metal Performance Shaders blurs artwork when it changes.

Artwork and sprite atlases stay in GPU textures. Text and SF Symbols are rasterized
only when needed and cached as textures; layout and marquee animation move GPU
quads. There is no full-frame CPU pixel engine, pixel conversion pass, or bitmap
upload on each frame.

For optional renderer timing, stop the running app and launch:

```sh
WALLIFY_PROFILE=1 ./zig-out/Wallify.app/Contents/MacOS/Wallify
```

Every 300 prepared scenes this reports mean scene-preparation CPU time, completed
GPU time, draw count, and asset upload bytes. These are renderer measurements,
not total app CPU usage or end-to-end input latency. Normal app launches are quiet.

See [architecture](docs/architecture.md) for module ownership.
