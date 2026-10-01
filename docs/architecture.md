# Architecture

`main.zig` initializes assets and boots background animation and media telemetry workers. Swift's `platform/application.swift` initializes AppKit, owns the status-bar menu, and runs the native event loop through C entry points. `platform/widget_window.swift` supplies the desktop panel and input view, retains right-click events for synchronous context menus, and forwards visibility changes to the scheduler. `platform/metal_renderer.swift` owns the panel, Metal layer, GPU pipeline, texture slots, and frame presentation. `state.Layout` owns logical-point geometry used across rendering, input hitboxes, and native panel sizing.

## GPU Renderer & Native Glass

`graphics/render.zig` composes an ordered scene using `graphics/canvas.zig`. A scene contains at most 128 small commands, each with geometry, color, texture coordinates, and shared rounded card clipping. `platform/gpu.h` defines the shared C-ABI struct consumed by Zig, Swift, and `platform/shaders.metal`.

- **Metal Pipeline**: `platform/metal_renderer.swift` snapshots command lists and texture references under a lock into reusable buffers. Only the latest pending scene is retained, drawing directly into a framebuffer-only `CAMetalLayer` drawable with at most two command buffers in flight. Lists within Metal's 4 KB inline limit use `setVertexBytes`/`setFragmentBytes`; larger lists use an owned GPU buffer. Both split scenes and direct command lists share this renderer.
- **Static scene cache**: Active playback is submitted as two layers. The static layer contains artwork, glow, controls, background treatment, and the frame; it is rendered once into a private Metal texture and reused. The dynamic layer composites that texture and only redraws content that actually changes, such as progress, timestamps, hover states, and Aurora.
- **Occlusion-aware scheduler**: AppKit's `NSWindow.occlusionState` is bridged into `state.window_visible`. When the widget is fully covered, frame requests only mark the scene dirty and the animation thread sleeps. A visibility transition wakes it once, allowing accumulated metadata/settings changes to appear without burning CPU or GPU time while hidden.
- **Frame-budget tiers**: The animation loop assigns 60 FPS to input-critical motion, 30 FPS to short decorative transitions, and 20 FPS to steady playback/ambient effects. This keeps expensive effects bounded instead of tying all animation to the display refresh rate.
- **Native Frosted Glass**: On macOS 26, `desktop_glass.swift` hosts the Metal view inside a clipped `NSGlassEffectView`. Disabling glass or running an older macOS restores the full-window Metal view. The Metal card background alpha drops to 0.0, and shader output uses premultiplied alpha to blend with the native material.

## Debugging & Performance

Set `WALLIFY_PROFILE=1` when measuring renderer behavior. The profile stream reports scene-preparation CPU time, completed GPU time, average draw-call count, and uploaded texture bytes. Native logs identify expensive lifecycle events without logging every frame: Metal setup failures, surface resize requests, texture uploads/swaps, static-cache rebuilds, and occlusion changes.

The intended steady-state path is a small dynamic pass over a cached scene. A cache rebuild is expected after metadata/artwork changes that alter static commands, widget resizing, or a backing-scale change. Repeated cache rebuilds during otherwise idle playback are a signal to investigate rather than a normal steady-state condition.

`platform/idle_animation.swift` owns the repeating Core Animation layer tree for idle companions. It copies Zig's sampled draw commands before dispatching to the main queue, converts retained Metal sprite textures into cached images, and preserves discrete frame timing, clipping, and nearest-neighbor scaling. The renderer exposes only the texture and surface accessors needed by this bridge.

`graphics/raster.swift` uses Core Text for Unicode measurement, ellipsis truncation, alignment, and text rasterization; AppKit supplies cached SF Symbol images for playback controls. ImageIO decodes artwork directly into the same RGBA buffers consumed by Metal. Zig retains texture-cache policy, artwork transitions, and color extraction.

`platform/desktop_glass.swift` owns native glass creation, clipping, and Metal-view reparenting. It coalesces unchanged geometry before scheduling AppKit work and restores the full-window Metal view when glass is disabled or unavailable. `platform/widget_window.swift` also owns panel movement and the coordinate offsets used for desktop snapping.

`platform/desktop_snap.swift` queries WindowServer for the player and visible desktop-widget candidates, including when foreign window titles are redacted. It owns the reusable, click-through snap-preview panel. `ui/snap.zig` retains the tested grid solver and Inspector state, passing native window rectangles through shared C structs.

## Media Subsystem & Auto Source

`media/controller.zig` coordinates playback state and metadata across multiple backends:
- **System Now Playing**: `media/metadata_fetcher.swift` implements the metadata helper loaded by Perl, preserving its exported C entry points and line protocol. Swift owns notification observers, bounded asynchronous queries, elapsed-time correction, and atomic artwork writes. Every query has its own completion token, so late callbacks cannot satisfy the next query or publish stale metadata. The Zig controller forwards play/pause/track commands and seeking to `platform/media_remote.swift`, which dynamically resolves the private framework symbols and safely skips unavailable functions.
- **Spotify Direct**: Swift queries and controls Spotify via AppleScript (`media/spotify.swift`); `media/spotify.zig` declares its C interface. Distributed playback notifications coalesce through a lock and semaphore to wake the metadata worker and signal the MediaRemote helper.
- **Spotifast transport**: `media/spotifast.swift` owns the persistent loopback metadata connection, separate command connections, and native launching. `media/spotifast.zig` retains payload parsing for the controller. Incomplete response lines close the connection before retrying, so subsequent queries cannot consume stale fragments.
- **Auto Source**: Dynamically pings the Spotifast TCP socket with a non-blocking connection. If Spotifast is responsive, it routes requests there; if inactive, it instantly falls back to System Now Playing.

## Hardware Media Key Redirect

To prevent macOS from automatically waking Apple Music when hardware media keys (F7 / F8 / F9) are pressed:
- Swift's `platform/media_keys.swift` optionally installs a low-level `CGEventTap` on `kCGSessionEventTap` watching for `NSSystemDefined` events with subtype `NX_SUBTYPE_AUX_CONTROL_BUTTONS`.
- When key codes for play/pause (16), next track (19), or previous track (20) are intercepted, the event is consumed (`return NULL;`) so `rpcd` / Apple Music never receive it.
- The event is forwarded to `wallify_media_key_event()` in `media/controller.zig`, which routes playback through the user's chosen target (`active`, `spotify`, or `spotifast`).
- Requires macOS Accessibility permission (`NSAccessibilityUsageDescription` declared in `Info.plist`).
- The tap and callback use the main run loop. Playback key releases are consumed without issuing duplicate commands; volume and brightness events pass through. Timeout-disabled taps are re-enabled automatically.

## App Controls & Diagnostics

The Swift/AppKit status-bar menu is the fast path for common actions. It mirrors the live settings snapshot so checkmarks and the Play/Pause label stay synchronized with Settings, while media commands go through the same Zig media controller as the widget itself. Metadata refresh runs every 0.2 seconds only while the menu is open. Toggle actions read the current snapshot rather than relying on a potentially stale checkmark. In developer builds, the menu also exposes the Dear ImGui Inspector.

The Settings window uses SwiftUI hosted in an AppKit window (`platform/settings_window.swift`). Its controls read the existing C settings snapshot and call the Zig settings bridge, which applies state changes and persists them. Swift is compiled into `libWallifySettings.dylib`, linked by the Zig executable, and packaged in the app’s Frameworks directory. The renderer and widget state remain in Zig during this first migration step. The Performance page surfaces the native renderer's current device/timing information and links directly to the Inspector. The System section uses Apple's `SMAppService` main-app login-item API for Launch at Login; registration errors are logged rather than silently changing the UI.

The Inspector is a separate MetalKit + Dear ImGui window intended for development builds. Its Performance tab combines AppKit window occlusion, the renderer statistics bridge, and the frame scheduler's state to make the power model visible. The Console / Events tab captures stdout/stderr into a bounded in-memory log while mirroring the original terminal stream. This makes cache rebuilds, texture uploads, GPU failures, and visibility transitions inspectable without adding per-frame log spam.

## Configuration & Storage

`src/settings.zig` handles serialization and deserialization of `widget-settings.conf`. Swift's `wallify_prepare()` in `platform/application.swift` resolves the active path at startup and seeds bundled defaults only when the destination does not exist:
1. `~/.config/Wallify/widget-settings.conf` (XDG standard — takes precedence if present)
2. `~/Library/Application Support/Wallify/widget-settings.conf` (macOS default fallback)
3. `./widget-settings.conf` (bare development executable fallback)

Settings mutations in the UI or context menu immediately update `state.zig`, request a GPU frame re-render, and flush atomically to disk.

## Build and Verification

The build compiles the Zig core, Swift native integrations and renderer, SwiftUI Settings, and a Metal library:
- `./run` builds `ReleaseFast`, packages `Wallify.app`, and signs all binaries.
- `scripts/package-app.sh` packages the bundle, generates `Info.plist`, and embeds assets.
- `zig build test` executes unit tests covering playback clocks, layout/hitboxes, GPU command clipping, settings snapshot synchronization, Swift menu actions/checkmarks, configuration path precedence/default seeding, and desktop panel/input event behavior.
