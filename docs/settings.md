# Settings guide

Open **Settings…** from the widget context menu or the three-bar menu bar item.
Changes take effect immediately and save automatically. The menus keep common
actions close at hand; detailed customization lives in Settings.

## Pages

| Page | Controls |
| --- | --- |
| General | Widget Size, Media Source, Idle Behavior, Media Keys, Spotify Account, Startup (Launch at Login, Login Items, Permissions) |
| Appearance | Material, Artwork, Motion, including Track Transition and Animation Speed |
| Playback | Visibility and Clickable Names, Progress (waveform, capture permission, thickness), Scrolling, Text (Synced Lyrics, Font Size) |
| Desktop | Lock Position, Display, Reset Position |
| Advanced | Renderer, Diagnostics (Debug Console, Inspector, build, placement), Updates, Configuration and Restore Defaults |

Settings uses the standard macOS sidebar and grouped rows. Every setting is
defined once in the settings table in `src/settings.swift`, which also supplies
its title and options to both menus.

**When Music Stops** offers Show Companion, Keep Last Track, or Hide Widget.
Pausing keeps the current track visible. Last-track metadata stays available
for the current session, including when switching this preference after a stop.
Hide Widget returns automatically when a track becomes available; use the
menu bar to reopen Settings while hidden. Companion selection is enabled only
with Show Companion.

**Clickable Names** is off by default. Track titles open an
exact Spotify link when available, otherwise a title-and-artist search. Artist
names open artist searches. Hidden text cannot be clicked. Playback controls
remain usable while Lock Position prevents dragging.

Desktop placement is stored per display UUID in `display-placements.json`
beside `widget-settings.conf`. The Display picker selects the preferred monitor.
When it disconnects, Wallify uses the primary display; reconnection restores
the preferred monitor. Positions are clamped to usable display bounds. Terminal
movement does not change desktop placement.

**Synced Lyrics** is off by default. While on, each new song's title, artist
and length are sent to lrclib.net, and the current line replaces the time labels
under the progress bar while that song has synced lyrics. Gaps and intros show a
note; songs without synced lyrics keep the time labels.

**Scroll Action** chooses Off, Volume or Seek. Volume changes the Mac's output
volume (Spotify's own volume usually stays at 100 %) and briefly shows the level
on the progress bar. Momentum scrolling is ignored.

**Spotify Account** needs your own Spotify developer app. Paste its 32-character
client ID, then add `http://127.0.0.1:43219/callback` as a redirect URI in the
app's dashboard and click Connect. The login uses PKCE in your browser; the
refresh token is stored in your Keychain. The account enables the like button,
the Save to Liked Songs menu item and Up Next (2×2 only). Disconnect removes it.

**Updates** checks the latest GitHub release 30 seconds after launch and once a
day while Check for Updates is on. Update Channel chooses Stable (versioned
releases) or Nightly (the build of the latest push, compared by commit). An
available update appears in both menus and opens its release page; nothing is
downloaded automatically.

## Disabled controls

- Glow Intensity requires Artwork Glow.
- Aurora and Custom Border require Native Glass to be off.
- Widget Size requires Lock Position to be off.
- Track Transition and Animation Speed require Animations.
- Clickable names require Hide Track Text to be off.
- System Audio Waveform requires a visible progress bar and Animations. It also
  requires macOS 14.2 or later and system audio capture permission. Audio is
  never saved, and the normal progress fill returns when capture is unavailable.

Each unavailable control explains what to enable. These dependencies preserve
your saved choice rather than resetting it.

## Startup, diagnostics, and resets

Launch at Login is in General → Startup. macOS may require approval in Login
Items Settings. Failures appear below the control. Permissions → Review… reopens
the setup screen shown on first launch, with live status for Spotify control,
system audio and the Spotify account.

Advanced contains renderer status, Debug Console, Open Inspector, the build and
placement readouts, Updates, and buttons to reveal or open the configuration file. The optional
Dear ImGui Inspector requires a build with `--debug-inspector`; edits there use
the same settings bridge and save automatically.

Reset Position resets the current widget margins. Restore Defaults in
Advanced → Configuration requires confirmation and resets preferences; it is absent from quick
menus to prevent accidental resets. Rebuilding preserves saved preferences.
Quit and reopen Wallify after rebuilding to load new code.
