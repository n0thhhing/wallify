# Wallify

[![CI](https://github.com/n0thhhing/wallify/actions/workflows/ci.yml/badge.svg)](https://github.com/n0thhhing/wallify/actions/workflows/ci.yml)

A native macOS music widget written in Swift, with AppKit controls, SwiftUI Settings, and a Metal renderer. Displays live track metadata, album art, playback controls, an animated aurora background, and idle companion sprites. No terminal needed to run the built app.

## Features

- **Native glass** — true `NSVisualEffectView` blur matching macOS desktop widgets (Battery, Clock, etc.)
- **Media sources** — System Now Playing, Spotify (AppleScript), Spotifast (fast local IPC), or **Auto** (pings Spotifast, falls back to Now Playing automatically)
- **Media key redirect** — intercepts F7/F8/F9 via `CGEventTap` and routes them to your chosen source instead of waking Apple Music (requires Accessibility permission)
- **Artwork transitions** — Smooth Crossfade, Cinematic, Liquid Ripple, 3D Card Flip, Vinyl Spin, Cyber Glitch (Metal shader animations)
- **Idle companions** — Pixel Cat, Banana Cat, Raccoon, or Spotify button when nothing is playing
- **Stopped-music behavior** — show a companion, retain the last track, or hide; paused tracks stay visible
- **Desktop placement** — lock against accidental dragging and remember placement separately for each display
- **Optional clickable names** — open tracks and artist searches from the widget
- **Five widget form factors** — 1×1, 2×1, 3×1, 1×2, and 2×2 with animated resizing
- **Aurora background** — multi-stop gradient shifting to album art dominant colors
- **Power-aware renderer** — static artwork/glow is cached, animation runs in tiered frame budgets, and fully occluded widgets put the render loop to sleep
- **Configurable** — hide text, hide progress bar, font scale, glow intensity, animation speed, glass border strength

## Run

**Requirements:** Swift (via Xcode), Clang, and the Xcode Metal toolchain (`xcrun metal` / `xcrun metallib`). Metal-capable Mac required.

```sh
./run                    # Build ReleaseFast, package, and launch Wallify.app
./run -f                 # Foreground — stream logs to terminal
./run --cli              # Display in a compatible terminal; drag to move within it
./run -d                 # Debug build with runtime assertions
./run -t                 # Run test suite before launching
./run -k                 # Stop running instance
./run -c                 # Clean before building
./run -R                 # Relaunch only (no rebuild)
./run -h                 # Show all options
```

After building, open `build/Wallify.app` from Finder. Drag to move, right-click and choose **Settings…**, and use the on-screen buttons and seek bar to control playback. Both menus put Settings and a checked **Lock Position** item near the top, with quick appearance controls, Media Source, Widget Size, and Companion choices. Detailed effects and animation controls live in Settings. Quit from either menu. After rebuilding, quit and reopen the app to load the new interface; an already running instance keeps its previous code.

Enable **Clickable Track and Artist Names** in **Settings → Playback → Visibility** to open a track's Spotify page or search for its artist in your browser. This option is off by default; disabled names remain draggable. Spotify provides exact track links; Spotifast and other Now Playing sources fall back to a title-and-artist search. The links also work in terminal mode. Hovering underlines the name; desktop users can focus the widget, press Tab or Shift-Tab to choose a label, then Return or Space to open it. VoiceOver exposes both names as links. Hidden text and idle placeholders stay inactive.

**Lock Position** in **Settings → Desktop → Position** (or directly in either menu) prevents dragging while keeping playback controls usable. Use **Move to Display** in the same Position section to choose a monitor. Wallify remembers a separate placement for each display in `display-placements.json` beside your settings file, restores the selected display at startup, and returns to it after reconnection. A disconnected monitor falls back to the primary display. Positions are kept within the display's usable area, including after a resolution or widget-size change. Terminal movement stays separate from desktop placement.

Choose **When Music Stops** under **Settings → General → Idle Behavior**: show the companion, keep the last track, or hide the widget. Pausing keeps the track visible. Hidden widgets return when a track becomes available; the menu-bar Settings remain accessible. The most recent track is retained for the current session, so switching from companion to Keep Last Track after music stops still works. See the [Settings guide](docs/settings.md) for page locations, disabled controls, and reset behavior.

Terminal mode uses the Kitty graphics protocol and SGR mouse reporting in any terminal that supports them, following the terminal support on `main` (`2e3f389`). Startup queries protocol support directly and waits up to two seconds for a positive reply; unsupported or unresponsive terminals exit with an explanation. It does not restrict startup by terminal name. The query follows the [protocol specification](https://sw.kovidgoyal.net/kitty/graphics-protocol/#querying-support-and-available-transmission-mediums). It shares the Swift renderer, media sources, waveform transitions, companions, and saved preferences. Drag the card to move within the terminal without snapping; click playback buttons or the seek bar as usual. Space toggles playback, left/right arrows (or `p`/`n`) change tracks, `1`–`5` change form factor, `m` cycles media sources, `s` opens Settings, and `q` or Ctrl+C exits. Terminal glass uses the rendered background. Desktop position is preserved, and CLI launch leaves the desktop instance running. Logs go to `/tmp/wallify-cli.log`. Inside tmux, enable `allow-passthrough` for graphics.

## Configuration

The optional **System Audio Waveform** in Settings → Playback → Progress replaces the elapsed progress fill with live audio; the remaining track stays plain. It is off by default, requires macOS 14.2+ and system audio capture permission, and saves no audio. Capture stops when playback pauses, the widget is hidden, or progress/animations are disabled. The normal fill returns when audio is unavailable.

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
widget_mode         = expanded      # compact | two_by_one | expanded | one_by_two | two_by_two
media_source        = auto          # now_playing | spotify | spotifast | auto
idle_style          = cat           # cat | banana_cat | raccoon | spotify
track_transition    = cinematic     # default | cinematic | ripple | flip | vinyl | glitch
hide_text           = false         # Hide track title and artist labels
clickable_names     = false         # Enable track links and artist searches
position_locked     = false         # Prevent accidental dragging
stopped_behavior    = companion     # companion | keep_last_track | hide
hide_progress       = false         # Hide the progress/seek bar
font_scale          = normal        # small | normal | large
media_key_target    = off           # off | active | spotify | spotifast
show_controls       = true          # Show playback buttons
show_timestamps     = true          # Show time labels
waveform            = false         # Optional system audio capture
artwork_border      = true
compact_gradient    = true
artwork_radius      = 1             # 0: soft | 1: rounded | 2: large
progress_thickness  = 1             # 0: thin | 1: standard | 2: thick

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
./scripts/build.sh -O ReleaseFast
./scripts/build.sh -O Debug --test
./scripts/build.sh -O Debug --debug-inspector
bash scripts/package-app.sh
```

Build output lives under `build/`. Use ReleaseFast for performance measurements; Debug retains runtime assertions.

Every build also writes an ignored `compile_commands.json` at the repository
root. SourceKit-LSP uses it to see the complete Swift targets and the C bridging
header defining types such as `DrawCommand`. Native entries also give clangd
the C++17, SDK, ARC, and ImGui include settings for the Inspector and the
checked-in ImGui snapshot, even on builds without the Inspector. Run
`./scripts/build.sh -O Debug --debug-inspector` once in a fresh checkout to
fetch the pinned ImGui headers and backends. Open the repository folder in your
editor, run the build once, and restart its language servers if existing
diagnostics persist. Zed's Debug and Profile configurations use the same build
script and `build/bin/wallify` executable.

Builds skip unchanged targets and reuse Swift's incremental dependency graph when sources change. Source contents, headers, compiler options, and the selected toolchain invalidate the relevant outputs. `--test` always runs the checks, even when the test binary is already current. Delete `build/` for a clean rebuild.

Set `WALLIFY_PROFILE=1` to enable scene-preparation timing, GPU frame timing, texture upload counters, and periodic renderer statistics. Native lifecycle logs also report cache rebuilds, texture uploads/swaps, resize requests, and visibility changes.

Debug builds can enable the Dear ImGui Inspector with `--debug-inspector`. Open it from the menu bar or **Settings → Performance → Advanced → Diagnostics**. It includes Widget, Renderer, Performance, Input, Layout, and Console / Events tabs. Widget controls include clickable names, waveform, companions, stopped-music behavior, and position locking. Media readouts distinguish paused and stopped playback and report hiding caused by stop behavior. Layout shows the current display and placement margins. The Performance tab exposes scheduler tier, occlusion state, static-scene cache status and rebuilds, renderer timing, draw-call averages, and texture memory. Inspector setting edits use the same persisted settings bridge as Settings.

### Performance model

Wallify deliberately does not redraw at the display refresh rate all the time. Input-critical motion such as dragging, snapping, and widget resizing can run at 60 FPS; short decorative transitions use 30 FPS; steady playback/progress and ambient effects use 20 FPS. The active player is split into a cached static layer and a small dynamic layer so artwork, glow, controls, and the frame do not get shaded again on every playback tick.

When macOS reports the widget as fully occluded, Wallify keeps the latest scene marked dirty but stops waking the animation loop and issuing Metal work. Visibility changes wake the loop once so the next frame incorporates any metadata or settings changes that arrived while covered.

## Architecture

See [`docs/architecture.md`](docs/architecture.md) for a breakdown of the rendering pipeline, media source multiplexer, settings bridge, and native glass implementation.
