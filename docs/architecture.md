# Architecture

`main.zig` initializes AppKit and assets, starts animation and media workers, and
runs the native event loop. `state.Layout` owns logical-point geometry used by
rendering, input hitboxes, and native panel sizing.

## GPU renderer

`graphics/render.zig` composes an ordered scene using `graphics/canvas.zig`.
A scene contains at most 128 small commands, each with geometry, color, texture
coordinates, and the shared rounded card clip. `platform/gpu.h` is the single ABI
definition imported by Zig, Objective-C, and the Metal shader.

`platform/native.m` snapshots the command list and its immutable texture references
under a lock. Only the latest pending scene is retained, with at most two GPU
command buffers in flight. A single render pass draws the commands directly into
a framebuffer-only CAMetalLayer drawable. Rounded coverage, borders, gradients,
texture sampling, opacity, and clipping execute in `platform/shaders.metal`.
No CPU frame buffer or per-frame texture allocation is involved.

## Cached resources

`graphics/assets.zig` uploads static sprites and controls once. Media events mark
artwork dirty; only then is the BMP read, validated, decoded, and hashed. Changed
artwork gets a new texture and GPU Gaussian blur. The previous textures remain
available for crossfades. Asset updates and rendering share a Metal command queue,
so blur completes before a draw samples its result.

`graphics/text_cache.zig` shares one bounded cache for captions, timestamps, and
marquee text. White Core Text masks are tinted in the shader; positions, widths,
and animation scale do not change the cache key. Font masks and SF Symbols still
need CPU rasterization on cache misses, and compressed assets need initial decoding.
Those operations do not repaint the widget every frame.

`graphics/sprites.zig` defines atlas regions and validates the RLE data emitted by
the Swift build helper. Both pet renderers emit textured quads; sleep marks emit
small GPU rectangles. `preview_cat.zig` is an independent offline contact-sheet
writer sharing the atlas decoder, without the app or former pixel engine.

## Interaction and media

AppKit supplies top-left logical pointer coordinates to `ui/input.zig`. It handles
playback, seeking, hover, dragging, and right-click menus. Native panel moves and
resizes are dispatched to AppKit's main thread. There is no terminal input parser
or keyboard shortcut handler.

`media/controller.zig` coordinates Spotify / MediaRemote metadata and playback.
`platform/` contains macOS bindings. `state.zig` owns runtime state and preferences;
bundled runs resolve settings through the native Application Support path.

## Build and verification

The build compiles Zig, the Objective-C bridge, and a Metal library. Swift decodes
PNG sprite sheets into cached embedded assets. `run.sh` builds ReleaseFast and
`scripts/package-app.sh` packages and ad-hoc signs `Wallify.app`, including its
Metal library, Spotify icon, and metadata dylib.

Unit tests cover playback, layout/hitboxes, GPU command clipping, BMP validation,
and sprite decoding. `WALLIFY_PROFILE=1` enables scene-preparation and GPU timing
plus upload counters; normal rendering does not print performance logs.
