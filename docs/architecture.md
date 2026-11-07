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
| `assets/` | App artwork and sprite resources; runtime PNG atlases live in `assets/sprites/bin/`. |
| `scripts/` | Build, packaging, relaunch, dependency fetching, and sprite preparation tools. |
| `tests/` | Swift checks plus helper-loading, terminal-protocol, and build-cache probes. |
| `config/` | Terminal configuration; local widget preferences are ignored by Git. |
| `third_party/` | Checked-in external source; the optional Inspector builds from the pinned ImGui checkout in `build/vendor/`. |
| `docs/` | Architecture, performance notes, Swift port verification, and the GitHub Pages website (`index.html`, `style.css`, `site.js`). |
| `.github/workflows/` | CI on every push, the rolling nightly pre-release, and tagged releases. |
| `build/` | Separate configuration/architecture variants, selected-output links, app bundles, and vendor cache; ignored by Git. |

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

`settings.swift` describes every setting once in `settingSpecs`: key, config name, title, option labels, accepted config spellings, default, and the state and snapshot fields. Config parsing and writing, apply, Restore Defaults, the settings snapshot, both menus and the Settings window read that table; a setting missing from the documented config template is still written under `[Other]`. A golden test pins every config spelling. It parses named and legacy numeric settings and saves with Foundation atomic replacement. `platform/application.swift` resolves the XDG override first, then macOS Application Support for a bundle, or the working directory for a bare executable. Bundled defaults seed only missing preferences. SwiftUI Settings and native menus share snapshots and mutations. Menu items for settings carry tag `1000 + key × 100 + value`, decoded by `settingTag`; context selections are consumed once by the animation worker. The scene lock is released before synchronous menu tracking.

Settings separates appearance and motion from playback visibility and desktop
placement. Diagnostics, updates and configuration access live under Advanced.
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

`graphics/assets.swift` loads bundled PNG atlases, rasterizes symbols, decodes artwork through ImageIO, and publishes transitions and dominant colors. `text_cache.swift` bounds Core Text textures to 16 entries. Artwork generations invalidate the static cache.

`graphics/animation.swift` assigns 60 FPS to interaction, 30 FPS to decorative transitions, and 20 FPS to ambient effects. Playback redraws when the progress bar gains a pixel (assuming a 2× display), at least once a second with time labels, and at 20 FPS while the waveform shows. Lyrics animate at 30 FPS during a line change and otherwise wake when the next line starts; the like button's pop and burst run at 30 FPS for half a second. Unchanged scenes sleep until an event. Occluded widgets retain dirty state without drawing and wake on visibility changes. `platform/frame_wakeup.swift` coalesces wakeups and supports monotonic timed waits.

`graphics/idle_compositor.swift` chooses when native pet animation can run. `platform/idle_animation.swift` builds Core Animation layers from the sprite commands also used by direct Metal drawing. Interaction temporarily returns pets to the scheduler. Native glass uses `NSGlassEffectView` on macOS 26 and restores the Metal card on earlier systems or when disabled.

## Media

`media/controller.swift` coordinates Now Playing, Spotify AppleScript, and Spotifast loopback transport. For Spotify, the `PlaybackStateChanged` notification payload (name, artist, state, position, duration, track ID) is applied directly; AppleScript runs when the track ID changes, to get the artwork URL, and as a check every 15 seconds while visible or 30 while covered, because Spotify posts nothing for seeks. Auto routing probes Spotifast with a two-second cache and falls back to Now Playing. The bounded serial action queue coalesces contiguous seeks and preserves command order.

`media/helper.swift` owns and reaps its Perl process, which loads the Swift metadata dylib to preserve Apple's MediaRemote identity requirements. Source changes cancel downloads and stop the owned helper. Bounded line parsing rejects oversized incomplete replies.

The helper queries native playing state alongside metadata to override stale rates. Notifications trigger an immediate snapshot and a follow-up after 100 ms. Separate completion tokens prevent late replies from satisfying a newer query.

`media/playback.swift` interpolates elapsed time, smooths small corrections, and reconciles optimistic local intent. External playback changes apply on the first snapshot without a pending intent. `payload.swift` validates UTF-8 spans, finite numbers, and protocol bounds.

`media_stopped` distinguishes absent metadata from a paused, present track.
Stopping retains the last track for the session; `setting_stopped_behavior`
selects companion, retained track, or hidden presentation. Native visibility
changes run on the main thread and wake independently of the sleeping renderer,
so new metadata can restore a hidden widget. Position locking cancels dragging
and snapping without disabling playback or optional name links.

`media/spotify_account.swift` implements the optional Spotify Web API login: PKCE through the browser, a one-shot callback listener bound to 127.0.0.1:43219 with a state check, the refresh token in the Keychain (the test binary, which has no bundle identifier, never touches it), access tokens in memory, refresh on expiry, one retry on 401, and disconnect when access is revoked. `LikeStore` checks and toggles Liked Songs per track, flipping immediately and reverting on failure; `UpNextStore` reads the first queued track for the 2×2 size. `media/lyrics.swift` fetches synced lyrics from lrclib.net per track and computes the current line, the previous line and the transition progress from the playback position.

Scrolling over the widget calls `adjustVolume`, which coalesces scroll deltas into one AppleScript change of the Mac's output volume at a time on a background queue, or `seekWidget`, which reuses the seek queue.

Artwork downloads use URLSession, cancellation, generation checks, and atomic publication. Publication follows scene-lock ordering so stale artwork cannot cross sources. An optional Accessibility event tap routes only play/pause, previous, and next hardware keys; unrelated keys pass through.

## Accessibility, onboarding and updates

`platform/widget_window.swift` exposes the Metal-drawn widget to VoiceOver as reusable `NSAccessibilityElement`s: track and artist (links when clickable), the three playback buttons, the like button, the lyric line, Up Next, a seekable progress slider, and the idle launcher. The widget's value summarizes play state and track; track and play-state changes post accessibility notifications.

`platform/onboarding_window.swift` shows the setup screen once on first launch (reopened from Settings → General → Permissions). It reads Automation permission for Spotify with `AEDeterminePermissionToAutomateTarget`, off the main thread because prompting blocks. `platform/updates.swift` compares the running version or build commit with the latest GitHub release or the `nightly` pre-release and only opens github.com release pages. `platform/application.swift` installs a hidden Edit menu so copy and paste work in text fields of this menu-bar-only app, and draws the menu bar icon as a template image.

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

`scripts/build.sh` invokes Xcode Swift, Clang, and Metal compilers. No Zig compiler is required. Packaging embeds the helper, shaders, and sprites, generates `Info.plist` with the version from `VERSION`, signs the app with an available Developer ID or Apple Development identity (or ad hoc), and verifies its signature. `scripts/release.sh` bumps `VERSION`, tags and pushes; `.github/workflows/release.yml` builds and publishes the tagged release, `nightly.yml` refreshes the `nightly` pre-release on every push to `main` or `combine`, and `ci.yml` builds and tests every push on GitHub's `macos-26` runners. See [Swift port verification](swift-port.md) for commands and checks.

Each mode/Inspector/architecture combination owns a directory under
`build/variants`. Only a successful build (and requested tests) updates the
`build/current` symlink; stable `bin`, `lib`, and `resources` links follow it.
Generated `BuildIdentity.swift` embeds the same identity as `build-info.json`,
including the commit the Nightly update channel compares, without a timestamp that would invalidate every cached build.

`scripts/build-tools.py` provides filesystem operations shared by the shell
scripts: identity generation, selected-output links, watch snapshots, and package
digests/publication. Packaging pins the selected variant, hashes its inputs and
the signed output, and skips unchanged bundles. A staging bundle is signed and
verified before Darwin's `renamex_np(RENAME_SWAP)` publishes it atomically. An
unsupported swap fails with the old app intact. A second input hash rejects
changes that arrive during packaging; staging and the displaced old bundle are
cleaned afterward. The package cache is outside the signed app.
