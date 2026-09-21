# Wallify

[![CI](https://github.com/n0thhhing/wallify/actions/workflows/ci.yml/badge.svg)](https://github.com/n0thhhing/wallify/actions/workflows/ci.yml)

A native macOS music widget written in Zig with an AppKit window and Metal GPU renderer. Displays live track metadata, album art, playback controls, an animated aurora background, and idle companion sprites. No terminal needed to run the built app.

## Features

- **Native glass** — true `NSVisualEffectView` blur matching macOS desktop widgets (Battery, Clock, etc.)
- **Media sources** — System Now Playing, Spotify (AppleScript), Spotifast (fast local IPC), or **Auto** (pings Spotifast, falls back to Now Playing automatically)
- **Media key redirect** — intercepts F7/F8/F9 via `CGEventTap` and routes them to your chosen source instead of waking Apple Music (requires Accessibility permission)
- **Artwork transitions** — Smooth Crossfade, Cinematic, Liquid Ripple, 3D Card Flip, Vinyl Spin, Cyber Glitch (Metal shader animations)
- **Idle companions** — Pixel Cat, Banana Cat, Raccoon, or Spotify button when nothing is playing
- **Five widget form factors** — 1×1, 2×1, 3×1, 1×2, and 2×2 with animated resizing
- **Aurora background** — multi-stop gradient shifting to album art dominant colors
- **Power-aware renderer** — static artwork/glow is cached, animation runs in tiered frame budgets, and fully occluded widgets put the render loop to sleep
- **Configurable** — hide text, hide progress bar, font scale, glow intensity, animation speed, glass border strength

## Run

**Requirements:** Zig **0.16.0**, Clang, and the Xcode Metal toolchain (`xcrun metal` / `xcrun metallib`). Metal-capable Mac required.

```sh
./run                    # Build ReleaseFast, package, and launch Wallify.app
./run -f                 # Foreground — stream logs to terminal
./run -d                 # Debug build with runtime assertions
./run -t                 # Run test suite before launching
./run -k                 # Stop running instance
./run -c                 # Clean before building
./run -R                 # Relaunch only (no rebuild)
./run -h                 # Show all options
```

After building, open `zig-out/Wallify.app` from Finder. Drag to move, right-click for the full Settings panel, use the on-screen buttons and seek bar to control playback. Quit from the music-note menu-bar item.

## Configuration

Settings are saved to `widget-settings.conf`. The app checks these locations in order:

1. **`~/.config/Wallify/widget-settings.conf`** — XDG path; use for dotfiles or symlinks
2. **`~/Library/Application Support/Wallify/widget-settings.conf`** — macOS default; seeded from bundle on first launch

Rebuilding never overwrites saved preferences. Bare-binary development runs fall back to `./widget-settings.conf` in the working directory.

### Settings reference

```ini
[Appearance]
artwork_glow        = true          # Ambient glow from album art colors
native_glass        = false         # NSVisualEffectView frosted glass background
aurora              = true          # Animated multi-stop color gradient
animations          = true          # Spring-physics UI animations
dim_paused_artwork  = true          # Dim art when paused
frame_strength      = subtle        # off | subtle | strong
glow_intensity      = normal        # low | normal | high
animation_speed     = normal        # slow | normal | fast

[Behavior]
widget_mode         = expanded      # compact | expanded
media_source        = auto          # now_playing | spotify | spotifast | auto
idle_style          = pixel_cat     # cat | banana_cat | raccoon | spotify
track_transition    = cinematic     # default | cinematic | ripple | flip | vinyl | glitch
hide_text           = false         # Hide track title and artist labels
hide_progress       = false         # Hide the progress/seek bar
font_scale          = normal        # small | normal | large
media_key_target    = off           # off | active | spotify | spotifast

[Position]
widget_margin_left  = 8
widget_margin_top   = 8
widget_grid_x       = 0
widget_grid_y       = 0

[Debug]
widget_debug        = false         # Show snapping diagnostics HUD
```

## Develop

```sh
zig build -Doptimize=ReleaseFast
zig build test
zig build preview-cat               # Sprite contact sheet → /tmp/wallify-poses.ppm
bash scripts/package-app.sh
```

If compiler caches are restricted, supply writable `--cache-dir` and `--global-cache-dir` paths. `zig build` without an optimization flag builds Debug; use ReleaseFast for performance measurements.

Set `WALLIFY_PROFILE=1` to enable scene-preparation timing, GPU frame timing, texture upload counters, and periodic renderer statistics. Native lifecycle logs also report cache rebuilds, texture uploads/swaps, resize requests, and visibility changes.

### Performance model

Wallify deliberately does not redraw at the display refresh rate all the time. Input-critical motion such as dragging, snapping, and widget resizing can run at 60 FPS; short decorative transitions use 30 FPS; steady playback/progress and ambient effects use 20 FPS. The active player is split into a cached static layer and a small dynamic layer so artwork, glow, controls, and the frame do not get shaded again on every playback tick.

When macOS reports the widget as fully occluded, Wallify keeps the latest scene marked dirty but stops waking the animation loop and issuing Metal work. Visibility changes wake the loop once so the next frame incorporates any metadata or settings changes that arrived while covered.

## Architecture

See [`docs/architecture.md`](docs/architecture.md) for a breakdown of the rendering pipeline, media source multiplexer, settings bridge, and native glass implementation.
