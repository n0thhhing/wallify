# Architecture and maintenance

`main.zig` coordinates shared state, media updates, input, animation, and rendering.
`media/controller.zig` manages metadata acquisition and updates shared playback
state; provider-specific Spotify integration and the metadata library live beside
it. `graphics/render.zig` composes the widget using the pixel engine and specialized
text, symbol, glow, transition, and pet renderers.

`platform/` provides clean macOS interoperability modules (`core_foundation.zig`,
`core_graphics.zig`, `core_text.zig`, `objc.zig`, and `media_remote.zig`), with
`platform/macos.zig` acting as the aggregated facade. Graphics, UI, and media
modules import platform declarations as a leaf dependency without circular re-exports.

`state.zig` owns shared runtime data and settings serialization. Keep preference
keys coordinated with `run-desktop.sh`, which reads panel geometry before startup.
The root `widget-settings.conf` path is deliberately retained for compatibility.
The Kitty configuration lives in `config/kitty.conf`.

## Adding code

- Put graphics primitives in `graphics/`, pet artwork/renderers in `graphics/pets/`,
  media providers in `media/`, and user interaction code in `ui/`.
- Keep macOS bridge declarations in `platform/`.
- Keep tests beside the implementation and import new test modules in `main.zig`.
- Put asset converters in `tools/` and executable workflow wrappers in `scripts/`.
- Keep cat artwork as PNGs in `assets/cat/`. The build runs the Swift decoder
  with expected dimensions and exposes cached output through named embed imports.
  Never check the generated RGBA data into the source tree.
- Run the build and unit tests after moving modules; update relative imports,
  embed paths, launch scripts, and asset documentation together.

## Build and helper commands

`build.zig` defines the player, metadata dylib, unit tests, and cat preview.
The player and tests share their framework-linking configuration.
PNG decoding is a cached build dependency shared by the player, tests, and preview.
Swift and Apple image frameworks are needed at build time; animation does not
read PNG files at runtime. The preview
uses the same pixel engine and cat renderer without requiring a running player.
Its entry point stays under `src/` to keep relative imports within Zig's module
root; no source-directory symlink is needed.

`scripts/relaunch.sh` restarts an already installed launch agent for the current
user. Its default label is `com.levi.spotify-panel`; override it with
`WALLIFY_LAUNCH_AGENT`. It does not install a launch agent.

The package manifest retains the original `.foo` name and fingerprint to avoid
changing package identity during an organizational cleanup. Distribution paths
include the assets, configuration, launchers, and documentation needed by users.
