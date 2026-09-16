# Wallify

A native macOS music widget written in Zig with an AppKit window and Metal GPU
renderer. Includes Spotify / system media metadata, playback controls, animated
artwork, and cat sprites. No terminal is needed to run the built app.

## Run

Build requirements: Zig **0.16.0**, Swift/Clang, and the Xcode Metal toolchain
(`xcrun metal` and `xcrun metallib`). A Metal-capable Mac is required.

```sh
./run                    # Build ReleaseFast, package, and launch Wallify.app
./run -f                 # Run in foreground to stream logs to terminal
./run -d                 # Debug build with runtime assertions enabled
./run -t                 # Run test suite before launching
./run -k                 # Stop running instance
./run -h                 # Show all options
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

