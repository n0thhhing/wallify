# Swift port

The macOS Swift port is complete; Swift is the active application implementation.

Swift owns executable startup, shared widget state, configuration parsing and atomic persistence, AppKit and SwiftUI controls, media routing and helper lifecycle, playback reconciliation, pointer actions and snapping, scene composition, asset and text caches, animation scheduling, and Metal presentation.

The retired Zig implementation and build files have been removed. The optional development Inspector uses Dear ImGui/C++ and Objective-C++; GPU shaders remain Metal. C headers describe native callbacks and value layouts. The MediaRemote helper remains a separate Swift dylib loaded through Apple's Perl process identity and the existing line protocol.

## Build and verify

```sh
./scripts/build.sh -O Debug --test
./scripts/build.sh -O Debug --debug-inspector
./scripts/build.sh -O Debug --debug-inspector --test
./scripts/build.sh -O ReleaseFast
bash scripts/package-app.sh
```

Artifacts are written under `build/`; the signed app is `build/Wallify.app`. Swift checks exercise real AppKit windows, menus, Metal submission and GPU readback, sprite decoding, configuration, source changes, helper cleanup, playback intent, seeking, dragging, snapping, scheduler budgets, and artwork publication. The Perl loader check verifies the helper's exported entry points.

Saved preferences retain XDG precedence, the macOS Application Support path, legacy aliases, and the bare-executable working-directory fallback. Rebuilding does not replace saved preferences.

Current checks also cover optional track/artist links, position locking,
paused-versus-stopped presentation, per-display placement, and the Inspector's
shared snapshot fields and companion mapping. See the [Settings guide](settings.md)
for the current page organization. Restart an existing app after packaging to
load the new executable.
