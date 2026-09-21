# Architecture

`main.zig` initializes AppKit and assets, boots background animation and media telemetry workers, and runs the native event loop. `state.Layout` owns logical-point geometry used across rendering, input hitboxes, and native panel sizing.

## GPU Renderer & Native Glass

`graphics/render.zig` composes an ordered scene using `graphics/canvas.zig`. A scene contains at most 128 small commands, each with geometry, color, texture coordinates, and shared rounded card clipping. `platform/gpu.h` defines the shared C-ABI struct consumed by Zig, Objective-C, and `platform/shaders.metal`.

- **Metal Pipeline**: `platform/native.m` snapshots the command list and immutable texture references under a lock. Only the latest pending scene is retained, drawing directly into a framebuffer-only `CAMetalLayer` drawable with at most two command buffers in flight.
- **Static scene cache**: Active playback is submitted as two layers. The static layer contains artwork, glow, controls, background treatment, and the frame; it is rendered once into a private Metal texture and reused. The dynamic layer composites that texture and only redraws content that actually changes, such as progress, timestamps, hover states, and Aurora.
- **Occlusion-aware scheduler**: AppKit's `NSWindow.occlusionState` is bridged into `state.window_visible`. When the widget is fully covered, frame requests only mark the scene dirty and the animation thread sleeps. A visibility transition wakes it once, allowing accumulated metadata/settings changes to appear without burning CPU or GPU time while hidden.
- **Frame-budget tiers**: The animation loop assigns 60 FPS to input-critical motion, 30 FPS to short decorative transitions, and 20 FPS to steady playback/ambient effects. This keeps expensive effects bounded instead of tying all animation to the display refresh rate.
- **Native Frosted Glass**: When `native_glass` is enabled, an `NSVisualEffectView` (`NSVisualEffectMaterialPopover`) is inserted behind the Metal view in `native.m`. The Metal card background alpha drops to 0.0, and shader output enforces premultiplied alpha (`color.rgb *= color.a;`) to blend seamlessly with macOS vibrancy without additive artifacts.

## Debugging & Performance

Set `WALLIFY_PROFILE=1` when measuring renderer behavior. The profile stream reports scene-preparation CPU time, completed GPU time, average draw-call count, and uploaded texture bytes. Native logs identify expensive lifecycle events without logging every frame: Metal setup failures, surface resize requests, texture uploads/swaps, static-cache rebuilds, and occlusion changes.

The intended steady-state path is a small dynamic pass over a cached scene. A cache rebuild is expected after metadata/artwork changes that alter static commands, widget resizing, or a backing-scale change. Repeated cache rebuilds during otherwise idle playback are a signal to investigate rather than a normal steady-state condition.

## Media Subsystem & Auto Source

`media/controller.zig` coordinates playback state and metadata across multiple backends:
- **System Now Playing**: Interrogates macOS `MediaRemote` private framework via `platform/media_remote.zig`.
- **Spotify Direct**: Queries and controls Spotify via AppleScript (`media/spotify.zig`).
- **Spotifast**: Communicates over high-speed local TCP IPC (`media/spotifast.zig`).
- **Auto Source**: Dynamically pings the Spotifast TCP socket with a non-blocking connection. If Spotifast is responsive, it routes requests there; if inactive, it instantly falls back to System Now Playing.

## Hardware Media Key Redirect

To prevent macOS from automatically waking Apple Music when hardware media keys (F7 / F8 / F9) are pressed:
- `platform/native.m` optionally installs a low-level `CGEventTap` on `kCGSessionEventTap` watching for `NSSystemDefined` events with subtype `NX_SUBTYPE_AUX_CONTROL_BUTTONS`.
- When key codes for play/pause (16), next track (19), or previous track (20) are intercepted, the event is consumed (`return NULL;`) so `rpcd` / Apple Music never receive it.
- The event is forwarded to `wallify_media_key_event()` in `media/controller.zig`, which routes playback through the user's chosen target (`active`, `spotify`, or `spotifast`).
- Requires macOS Accessibility permission (`NSAccessibilityUsageDescription` declared in `Info.plist`).

## Configuration & Storage

`src/settings.zig` handles serialization and deserialization of `widget-settings.conf`. The active path is resolved at startup by `wallify_prepare()` in `platform/native.m`:
1. `~/.config/Wallify/widget-settings.conf` (XDG standard — takes precedence if present)
2. `~/Library/Application Support/Wallify/widget-settings.conf` (macOS default fallback)
3. `./widget-settings.conf` (bare development executable fallback)

Settings mutations in the UI or context menu immediately update `state.zig`, request a GPU frame re-render, and flush atomically to disk.

## Build and Verification

The build compiles Zig, the Objective-C bridge, and a Metal library:
- `./run` builds `ReleaseFast`, packages `Wallify.app`, and signs all binaries.
- `scripts/package-app.sh` packages the bundle, generates `Info.plist`, and embeds assets.
- `zig build test` executes unit tests covering playback clocks, layout/hitboxes, GPU command clipping, and settings snapshot synchronization.

