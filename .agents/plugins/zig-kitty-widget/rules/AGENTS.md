# Workspace Rules: Zig 0.16 & Kitty Media Widget Development

## Core Tech Stack
- **Language & Compiler:** Zig `0.16.0` (Do not assume or use APIs from Zig 0.11–0.15).
- **Primary Terminal:** Kitty (treat Kitty protocols as first-class citizens).
- **macOS Frameworks:** `MediaRemote.framework` (private symbols via `dlopen`/`dlsym`), `CoreFoundation`, `ImageIO`.
- **Primary Tooling:** Zed / Antigravity + MCP context servers (`mcpls` for ZLS, `zig-docs`, `kitty-docs`).

---

## 1. Zig 0.16.0 Development Standards

- **Target Version:** Strict target is **Zig 0.16.0**. Always verify standard library APIs against 0.16 (specifically `std.Io`, `std.mem.Allocator`, `std.Build`, process spawning, and POSIX wrappers).
- **Anti-Hallucination:** When unsure of Zig standard library signatures or behavior, consult `zig-docs` or check via ZLS semantic analysis (`mcpls`). Do not guess syntax from older Zig versions.
- **Memory Management:** Explicitly manage memory lifetimes. Prefer Arena allocators for per-frame or request-scoped operations and GPA for persistent widget state. Ensure proper cleanup on terminal shutdown or unexpected panics.
- **Build Verification:** Always verify changes by executing `zig build` or `zig test` in the workspace.

---

## 2. Kitty Protocol Standards

Treat Kitty as the primary environment. Always consult `kitty-docs` for authoritative protocol details:

### Kitty Graphics Protocol
- Escape sequence structure: `\x1b_G<control-keys>;<base64-payload>\x1b\`
- **Keys:** Action (`a=T` for transmit & display), Format (`f=32` for 32-bit RGBA, `f=100` for PNG), Image ID (`i=`), Placement ID (`p=`), Dimensions (`s=`, `v=`), Display Dimensions (`c=`, `r=`), More chunks (`m=1` or `m=0`), Z-index (`z=`).
- **Chunking:** Chunk payloads into $\le 4096$ byte chunks when writing to stdout.
- **Aspect Ratio & Cell Metrics:** Respect font/cell aspect ratio queries (`term.queryCellAspect`) to render true square album art across varying font dimensions.

### Kitty Text Sizing Protocol (`OSC 66`)
- Use `OSC 66` for scalable glyphs and larger button controls.
- Strictly gate Kitty-specific text sizing extensions to true Kitty instances (check `KITTY_WINDOW_ID` / terminal query response) to avoid garbled escape codes in non-supporting emulators.

### SGR Mouse Protocol (1006)
- Enable with `\x1b[?1000h\x1b[?1002h\x1b[?1006h`.
- Parse extended SGR sequences `\x1b[<Btn;Col;RowM` (press/drag) and `\x1b[<Btn;Col;Rowm` (release).
- Implement precise hit-testing for buttons (Play/Pause, Prev, Next), progress bar scrubbing, and album art focus.

---

## 3. macOS MediaRemote & C ABI Interop

- **Dynamic Linking:** Dynamically load `MediaRemote.framework` via `/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote` using `dlopen` and `dlsym`.
- **Exported Symbols:**
  - `MRMediaRemoteGetNowPlayingInfo`
  - `MRMediaRemoteRegisterForNowPlayingNotifications`
  - `MRMediaRemoteSendCommand`
- **CoreFoundation Lifetimes:** Ensure proper ARC/manual CF retain and release (`CFRelease`) on returned dictionaries, strings, and data objects to avoid memory leaks during track polling.
- **C ABI Types:** Use explicit C-compatible types (`[*c]const u8`, `c_int`, `*anyopaque`) and `extern "c"` declarations.

---

## 4. Terminal Cleanliness & Diagnostics

- **Raw Mode Safety:** The terminal runs in raw mode (`termios`). Never write unstructured debug logs directly to `stdout` or `stderr` during active widget rendering, as this corrupts escape sequences and visual layouts.
- **File-Based Logging:** Direct all trace/debug logs to log files (e.g. `log.zig` / `/tmp/wallify.log`) or use the toggleable on-screen debug overlay.
- **Signal Handling & Teardown:** Ensure `SIGINT`, `SIGTERM`, and `panic` handlers reliably restore terminal state (show cursor `\x1b[?25h`, disable mouse reporting `\x1b[?1000l\x1b[?1002l\x1b[?1006l`, leave alternate screen `\x1b[?1049l`).
