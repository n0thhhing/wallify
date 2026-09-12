# Wallify

A macOS desktop music widget written in Zig, displayed through Kitty. It combines
Spotify / system media metadata, playback controls, and animated idle artwork.

## Run

Requires Zig **0.16.0**, Swift (Xcode or Command Line Tools), macOS frameworks, and Kitty with the `kitten` executable
(on `PATH` or in `/Applications/kitty.app`).

```sh
zig build
./run.sh           # Run in the current Kitty terminal
./run-desktop.sh   # Build ReleaseFast and launch the desktop panel
```

Both launch scripts resolve paths from the project root. The desktop launcher
replaces the existing player process. Runtime assets and the metadata library are
loaded relative to the project root; launch through these scripts.

## Develop

```sh
zig build test          # Unit tests
zig fmt --check build.zig build.zig.zon src
zig build preview-cat   # Render /tmp/wallify-poses.ppm without launching the widget
./scripts/preview.sh    # Render, convert to PNG, and open the cat preview
```

If the default global cache is not writable, append
`--global-cache-dir /tmp/wallify-global-cache` to build commands.

## Layout

| Path | Purpose |
| --- | --- |
| `src/main.zig` | Application and unit-test entry point |
| `src/state.zig` | Shared runtime state and settings persistence |
| `src/graphics/` | Rendering, animation, text, symbols, and pixel engine |
| `src/graphics/pets/` | Cat renderers |
| `src/media/` | Media controller, providers, metadata bridge, and playback state |
| `src/platform/` | macOS interoperability facade |
| `src/ui/` | Input, windows, menus, and hit testing |
| `src/preview_cat.zig` | Standalone preview entry point sharing the app renderer |
| `assets/` | Source artwork, runtime Spotify icon, and reference previews |
| `config/` | Kitty panel configuration |
| `scripts/` | Development and launch helpers |
| `tools/` | Asset conversion utilities |
| `docs/` | Architecture and maintenance notes |
| `archive/` | Historical notes and incomplete experiments; excluded from packages |

`widget-settings.conf` remains at the root because both the player and desktop
launcher read it there. It contains saved preferences and is rewritten by the app.
Build output (`zig-out/`) and caches (`.zig-cache/`) are generated and ignored.
Cat PNGs are decoded at build time into cached RGBA data and embedded in the
executable; raw `.bin` / `.rgba` assets are not stored in the source tree.

See [architecture](docs/architecture.md) and [cat assets](assets/cat/README.md).
