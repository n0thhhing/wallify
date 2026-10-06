# Settings guide

Open **Settings…** from the widget context menu or music-note menu bar item.
Changes take effect immediately and save automatically. The menus keep common
actions close at hand; detailed customization lives in Settings.

## Pages

| Page | Controls |
| --- | --- |
| General | Widget Size, Media Source, Idle Behavior, Media Keys, Startup |
| Appearance | Material, Artwork, Motion, including Track Transition and Animation Speed |
| Playback | Text and controls, clickable names, progress and waveform, Font Size |
| Performance | Renderer status and measurements; Advanced contains diagnostics and configuration access |
| Desktop | Lock Position, current display, Move to Display, margins and Reset Position |

**When Music Stops** offers Show Companion, Keep Last Track, or Hide Widget.
Pausing keeps the current track visible. Last-track metadata stays available
for the current session, including when switching this preference after a stop.
Hide Widget returns automatically when a track becomes available; use the
menu bar to reopen Settings while hidden. Companion selection is enabled only
with Show Companion.

**Clickable Track and Artist Names** is off by default. Track titles open an
exact Spotify link when available, otherwise a title-and-artist search. Artist
names open artist searches. Hidden text cannot be clicked. Playback controls
remain usable while Lock Position prevents dragging.

Desktop placement is stored per display UUID in `display-placements.json`
beside `widget-settings.conf`. Move to Display selects the preferred monitor.
When it disconnects, Wallify uses the primary display; reconnection restores
the preferred monitor. Positions are clamped to usable display bounds. Terminal
movement does not change desktop placement.

## Disabled controls

- Glow Intensity requires Artwork Glow.
- Aurora and Custom Border require Native Glass to be off.
- Track Transition and Animation Speed require Animations.
- Clickable names require Hide Track Text to be off.
- System Audio Waveform requires a visible progress bar and Animations. It also
  requires macOS 14.2 or later and system audio capture permission. Audio is
  never saved, and the normal progress fill returns when capture is unavailable.

Each unavailable control explains what to enable. These dependencies preserve
your saved choice rather than resetting it.

## Startup, diagnostics, and resets

Launch at Login is in General → Startup. macOS may require approval in Login
Items Settings. Failures appear below the control.

Performance → Advanced contains Debug Console, Open Inspector, profiling
instructions, and buttons to reveal or open the configuration file. The optional
Dear ImGui Inspector requires a build with `--debug-inspector`; edits there use
the same settings bridge and save automatically.

Reset Position resets the current widget margins. Restore Defaults in the
sidebar requires confirmation and resets preferences; it is absent from quick
menus to prevent accidental resets. Rebuilding preserves saved preferences.
Quit and reopen Wallify after rebuilding to load new code.
