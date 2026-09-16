or keyboard shortcut handler.

`media/controller.zig` coordinates Spotify / MediaRemote metadata and playback.
`platform/` contains macOS bindings. `state.zig` owns runtime state and preferences;
bundled runs resolve settings through the native Application Support path.

## Build and verification

The build compiles Zig, the Objective-C bridge, and a Metal library. Swift decodes
PNG sprite sheets into cached embedded assets. `./run` builds ReleaseFast and
`scripts/package-app.sh` packages and ad-hoc signs `Wallify.app`, including its
Metal library, Spotify icon, and metadata dylib.

Unit tests cover playback, layout/hitboxes, GPU command clipping, BMP validation,
and sprite decoding. `WALLIFY_PROFILE=1` enables scene-preparation and GPU timing
plus upload counters; normal rendering does not print performance logs.
