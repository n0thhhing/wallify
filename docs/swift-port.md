# Swift port

Work happens in the original checkout on `swift-port`. Each completed slice keeps the app runnable, preserves settings and media protocols, and is verified before committing.

## Completed native components

| Area | Swift implementation | Remaining Zig responsibility |
| --- | --- | --- |
| App lifecycle and status menu | `src/platform/application.swift` | Startup assets and worker coordination |
| Settings UI | `src/platform/settings_window.swift` | Settings snapshots, mutation, persistence |
| Widget window and input events | `src/platform/widget_window.swift` | Hitboxes, drag and playback actions |
| Right-click menu | `src/ui/context_menu.swift` | Action queue and state changes |
| Metal renderer | `src/platform/metal_renderer.swift` | Scene composition and texture cache policy |
| Glass and snap preview | `src/platform/desktop_glass.swift`, `desktop_snap.swift` | Snap grid solver and Inspector state |
| Idle layer animation | `src/platform/idle_animation.swift` | Sprite definitions and command sampling |
| Text, symbols and artwork decoding | `src/graphics/raster.swift` | Asset caching, colors and transitions |
| MediaRemote helper and controls | `src/media/metadata_fetcher.swift`, `src/platform/media_remote.swift` | Metadata controller and playback state |
| Spotify and Spotifast | `src/media/spotify.swift`, `spotifast.swift` | Spotifast payload parser and backend routing |
| Hardware media keys | `src/platform/media_keys.swift` | Target routing |

The Objective-C renderer has been removed. Metal shaders remain Metal source. The optional development Inspector still uses Dear ImGui/C++.

## Remaining migration order

1. Media payload parsing, playback clocks and state coordination.
2. Configuration serialization and shared widget state.
3. Layout, hitboxes and input actions.
4. Animation, asset caches and scene composition.
5. Swift executable startup and build/package cleanup after Zig responsibilities are gone.

Keep shared C interfaces only while both languages need them; remove each bridge when its last Zig caller migrates. Native Swift files live in their existing `platform`, `media`, `graphics` or `ui` area rather than a second copy of the source tree.

## Verification

- `zig build test -Doptimize=Debug`: Zig core tests and real Swift/AppKit/Metal checks, including GPU readback and helper loading.
- `zig build -Doptimize=Debug -Ddebug-inspector=true`: development Inspector build.
- `zig build -Doptimize=ReleaseFast`: optimized executable and libraries.
- `scripts/package-app.sh`: package and sign the app, then inspect a live widget when native rendering changes.

`libWallifySettings.dylib` is the historical name of the shared native Swift library; it now includes the renderer and native integrations as well as Settings. The metadata helper is a separate Swift library loaded through the existing Perl protocol.
