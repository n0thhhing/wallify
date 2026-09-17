# Architecture

`main.zig` initializes AppKit and assets, boots background animation and media telemetry workers, and runs the native event loop. `state.Layout` owns logical-point geometry used across rendering, input hitboxes, and native panel sizing.

## GPU Renderer & Native Glass

`graphics/render.zig` composes an ordered scene using `graphics/canvas.zig`. A scene contains at most 128 small commands, each with geometry, color, texture coordinates, and shared rounded card clipping. `platform/gpu.h` defines the shared C-ABI struct consumed by Zig, Objective-C, and `platform/shaders.metal`.

- **Metal Pipeline**: `platform/native.m` snapshots the command list and immutable texture references under a lock. Only the latest pending scene is retained, drawing directly into a framebuffer-only `CAMetalLayer` drawable with at most two command buffers in flight.
- **Native Frosted Glass**: When `native_glass` is enabled, an `NSVisualEffectView` (`NSVisualEffectMaterialPopover`) is inserted behind the Metal view in `native.m`. The Metal card background alpha drops to 0.0, and shader output enforces premultiplied alpha (`color.rgb *= color.a;`) to blend seamlessly with macOS vibrancy without additive artifacts.

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

