# Architecture

Wallify is a macOS Swift application. `src/wallify.swift` prepares configuration, creates the AppKit panel and Metal surface, starts animation and metadata workers, and runs the event loop. `native_bindings.swift` connects native controls and the optional C++ Inspector to Swift state and actions.

## Finding and placing files

| Location | Responsibility |
| --- | --- |
| `src/wallify.swift` | Startup and worker launch. |
| `src/widget_state.swift`, `src/settings.swift`, `src/native_bindings.swift` | Shared state, persisted configuration, and native callback bindings. |
| `src/media/` | Source routing, metadata helper, playback reconciliation, artwork downloads, audio capture, and queued controls. |
| `src/graphics/` | Scene commands, rendering preparation, animation policy, rasterization, textures, and sprites. |
| `src/ui/` | Layout, hit testing, menus, and Inspector UI. |
| `src/platform/` | AppKit/SwiftUI windows, desktop integration, terminal transport, Metal implementation, shaders, and C bridge headers. |
| `assets/` | App artwork and sprite resources; runtime RLE atlases live in `assets/sprites/bin/`. |
| `scripts/` | Build, packaging, relaunch, dependency fetching, and sprite preparation tools. |
| `tests/` | Swift checks plus helper-loading, terminal-protocol, and build-cache probes. |
| `config/` | Terminal configuration; local widget preferences are ignored by Git. |
| `third_party/` | Checked-in external source; the optional Inspector builds from the pinned ImGui checkout in `build/vendor/`. |
| `docs/` | Architecture, performance notes, and Swift port verification. |
| `build/` | Generated binaries, compiler intermediates, copied resources, and app bundles; ignored by Git. |

Keep rendering policy in `graphics/` and OS mechanisms in `platform/`: for
example, `graphics/idle_compositor.swift` decides when a native pet can run,
while `platform/idle_animation.swift` owns its Core Animation layers. Likewise,
`ui/layout.swift` supplies geometry shared by drawing and pointer handling.
New source files are discovered recursively by the build script; no separate
source manifest needs updating. Sprite paths must agree in `graphics/assets.swift`,
`scripts/build.sh`, and `scripts/package-app.sh`.

For a track update, follow `media/controller.swift` → `media/playback.swift`
and `media/artwork_download.swift` → `graphics/assets.swift` →
`graphics/render.swift` → `platform/metal_renderer.swift`. For an interaction,
start at `ui/input.swift` and `ui/layout.swift`, then follow the queued media
action or state change into `graphics/animation.swift`.

## State and settings

`widget_state.swift` owns widget state. A recursive scene lock serializes settings, metadata, input, and frame preparation. Separate locked flags coalesce dirty-frame requests and visibility changes. Rendering caches belong to the animation worker.

`settings.swift` parses named and legacy numeric settings and saves with Foundation atomic replacement. `platform/application.swift` resolves the XDG override first, then macOS Application Support for a bundle, or the working directory for a bare executable. Bundled defaults seed only missing preferences. SwiftUI Settings and native menus share snapshots and mutations. Context selections are consumed once by the animation worker. The scene lock is released before synchronous menu tracking.

Settings separates appearance and motion from playback visibility and desktop
placement. Advanced diagnostics and configuration access live under Performance.
See the [Settings guide](settings.md). The Inspector snapshot includes clickable
names, position locking, waveform, companion selection, and stopped behavior;
the C header and Swift producer must change together.

`platform/display_placement.swift` persists desktop margins per ColorSync display
UUID in a bounded JSON sidecar. UUIDs survive screen-array reordering; the
preferred display remains selected while disconnected so reconnecting restores
it. Saves use requested state margins because AppKit movement may still be
queued. Restores clamp to the display's usable area. CLI placement is separate.

## Rendering and scheduling

`ui/layout.swift` supplies one cached geometry for drawing and hit testing across five modes. `graphics/render.swift`, `canvas.swift`, and `player.swift` compose at most 128 commands. `platform/gpu.h` defines their layout for Swift and Metal shaders.

The Metal renderer retains only the latest pending scene and permits two command buffers in flight. Small lists use inline bytes; larger lists use owned buffers. Artwork, glow, controls, and frame treatments form a cached static texture. Progress, labels, hover, and aurora use the dynamic pass. GPU readback checks verify output and cache invalidation.

`graphics/assets.swift` loads bundled RLE atlases, rasterizes symbols, decodes artwork through ImageIO, and publishes transitions and dominant colors. `text_cache.swift` bounds Core Text textures to 16 entries. Artwork generations invalidate the static cache.

`graphics/animation.swift` assigns 60 FPS to interaction, 30 FPS to decorative transitions, and 20 FPS to playback and ambient effects. Timestamp-only playback wakes once per second; unchanged scenes sleep until an event. Occluded widgets retain dirty state without drawing and wake on visibility changes. `platform/frame_wakeup.swift` coalesces wakeups and supports monotonic timed waits.

`graphics/idle_compositor.swift` chooses when native pet animation can run. `platform/idle_animation.swift` builds Core Animation layers from the sprite commands also used by direct Metal drawing. Interaction temporarily returns pets to the scheduler. Native glass uses `NSGlassEffectView` on macOS 26 and restores the Metal card on earlier systems or when disabled.

## Media

`media/controller.swift` coordinates Now Playing, Spotify AppleScript, and Spotifast loopback transport. Auto routing probes Spotifast with a two-second cache and falls back to Now Playing. The bounded serial action queue coalesces contiguous seeks and preserves command order.

`media/helper.swift` owns and reaps its Perl process, which loads the Swift metadata dylib to preserve Apple's MediaRemote identity requirements. Source changes cancel downloads and stop the owned helper. Bounded line parsing rejects oversized incomplete replies.

The helper queries native playing state alongside metadata to override stale rates. Notifications trigger an immediate snapshot and a follow-up after 100 ms. Separate completion tokens prevent late replies from satisfying a newer query.

`media/playback.swift` interpolates elapsed time, smooths small corrections, and reconciles optimistic local intent. External playback changes apply on the first snapshot without a pending intent. `payload.swift` validates UTF-8 spans, finite numbers, and protocol bounds.

`media_stopped` distinguishes absent metadata from a paused, present track.
Stopping retains the last track for the session; `setting_stopped_behavior`
selects companion, retained track, or hidden presentation. Native visibility
changes run on the main thread and wake independently of the sleeping renderer,
so new metadata can restore a hidden widget. Position locking cancels dragging
and snapping without disabling playback or optional name links.

Artwork downloads use URLSession, cancellation, generation checks, and atomic publication. Publication follows scene-lock ordering so stale artwork cannot cross sources. An optional Accessibility event tap routes only play/pause, previous, and next hardware keys; unrelated keys pass through.

## Input and diagnostics

Window resizing and layout geometry share a quintic easing curve so their
positions stay synchronized, with gentle starts and stops. Idle/player content
crossfades throughout the transition. Hover and aurora blends use exponential
smoothing; the seek bar uses an exact critically damped spring, preserving
timing across frame rates and settling to exact endpoints. Event-driven wakes
start new motion at frame zero while retaining elapsed native pet animation
time. Existing steady playback/ambient frame rates are unchanged.

`ui/input.swift` reduces pointer events using shared geometry. Press/release pairing guards clicks, seeking clamps to duration, dragging uses screen coordinates, and snapping respects offsets and card insets. `ui/inspector.swift` owns drag diagnostics and snapshots.

The optional Dear ImGui Inspector remains C++/Objective-C++ and builds with `--debug-inspector`. It provides renderer, scheduler, layout, input, and bounded console diagnostics. `WALLIFY_PROFILE=1` enables preparation/GPU timings, draw counts, and upload statistics.

Native symbol rasterization uses owned bitmap contexts rather than NSImage's
deprecated lockFocus/offscreen-window cache. Window-show logs include widget,
snap-preview, and inspector window IDs and frames; idle-layer start/stop logs
record sprite and geometry. These event-only logs help investigate rare visual
flashes without adding a polling timer. The reported intermittent red flash has
not been reproduced, so the bitmap change is a precaution, not a confirmed fix.

## Build

`scripts/build.sh` invokes Xcode Swift, Clang, and Metal compilers. No Zig compiler is required. Packaging embeds the helper, shaders, and sprites, generates `Info.plist`, signs the app, and verifies its signature. See [Swift port verification](swift-port.md) for commands and checks.
