const std = @import("std");
const state = @import("../state.zig");
const render = @import("../graphics/render.zig");
const spotify = @import("spotify.zig");
const spotifast = @import("spotifast.zig");
const window = @import("../ui/window.zig");
const media_remote = @import("../platform/media_remote.zig");

extern "c" fn popen(command: [*c]const u8, modes: [*c]const u8) ?*anyopaque;
extern "c" fn pclose(stream: *anyopaque) c_int;
extern "c" fn fgets(buffer: [*]u8, size: c_int, stream: *anyopaque) ?[*]u8;

extern "c" fn dispatch_semaphore_create(value: isize) ?*anyopaque;
extern "c" fn dispatch_semaphore_signal(dsema: *anyopaque) isize;
extern "c" fn dispatch_semaphore_wait(dsema: *anyopaque, timeout: u64) isize;

const SPOTIFY_POLL_INTERVAL_MS: u64 = 250;
const SPOTIFAST_POLL_INTERVAL_MS: u64 = 500;
const QUERY_FAILURE_RETRY_MS: u64 = 500;
const METADATA_HELPER_FALLBACK_INTERVAL_S: []const u8 = "2";
const ARTWORK_BITMAP_SIZE: []const u8 = "328";
const ARTWORK_REQUEST_BUFFER_SIZE: usize = 1024;
const METADATA_LINE_BUFFER_SIZE: usize = 2048;
const ARTWORK_URL_BUFFER_SIZE: usize = 512;
const ELAPSED_CHANGE_THRESHOLD: f64 = 1.5;
const RATE_PLAYING: f64 = 1.0;
const RATE_STOPPED: f64 = 0.0;
const RATE_LOCKED: u32 = 1;
const RATE_LOCK_DURATION: f64 = 1.5;
const AUTO_SOURCE_RECHECK_US: u64 = 250_000;

var cached_auto_source = std.atomic.Value(c_int).init(@intFromEnum(state.MediaSource.now_playing));
var cached_auto_source_checked_us = std.atomic.Value(u64).init(0);

fn sleep_ms(ms: u64) void {
    const ts = std.posix.timespec{
        .sec = @intCast(ms / 1000),
        .nsec = @intCast((ms % 1000) * 1_000_000),
    };
    _ = std.posix.system.nanosleep(&ts, null);
}

pub const MediaRemoteCommand = media_remote.MediaRemoteCommand;

const ActionKind = enum {
    command,
    seek,
};

const MediaAction = struct {
    kind: ActionKind,
    cmd: MediaRemoteCommand = .play,
    seek_target: f64 = 0.0,
};

const ACTION_QUEUE_CAPACITY: usize = 32;
var action_queue: [ACTION_QUEUE_CAPACITY]MediaAction = undefined;
var queue_tail: usize = 0;
var queue_count: usize = 0;
var queue_lock: std.atomic.Mutex = .unlocked;
var command_sema: ?*anyopaque = null;
var worker_started = std.atomic.Value(bool).init(false);

fn lockQueue() void {
    while (!queue_lock.tryLock()) {
        std.atomic.spinLoopHint();
    }
}

fn unlockQueue() void {
    queue_lock.unlock();
}

pub fn triggerSeekInner(target: f64) void {
    const active = getActiveSource();
    if (active == .spotify) {
        spotify.widget_spotify_seek(target);
        return;
    }
    if (active == .spotifast) {
        spotifast.widget_spotifast_seek(target);
        return;
    }
    media_remote.setElapsedTime(target);
}

pub fn triggerCommandInner(cmd: MediaRemoteCommand) void {
    const active = getActiveSource();
    if (active == .spotify) {
        switch (cmd) {
            .play => spotify.widget_spotify_control(.play),
            .pause => spotify.widget_spotify_control(.pause),
            .toggle_play_pause => spotify.widget_spotify_control(.play_pause),
            .previous_track => spotify.widget_spotify_control(.previous_track),
            .next_track => spotify.widget_spotify_control(.next_track),
            .stop => spotify.widget_spotify_control(.pause),
        }
        return;
    }
    if (active == .spotifast) {
        switch (cmd) {
            .play => spotifast.widget_spotifast_control(.play),
            .pause => spotifast.widget_spotifast_control(.pause),
            .toggle_play_pause => spotifast.widget_spotifast_control(.play_pause),
            .previous_track => spotifast.widget_spotifast_control(.previous_track),
            .next_track => spotifast.widget_spotifast_control(.next_track),
            .stop => spotifast.widget_spotifast_control(.pause),
        }
        return;
    }
    media_remote.sendCommand(cmd);
}

fn getActiveSource() state.MediaSource {
    const s = state.setting_source;
    if (s != .auto) return s;

    const now_us = @as(u64, @intFromFloat(window.widget_monotonic_time() * 1_000_000.0));
    const checked_us = cached_auto_source_checked_us.load(.acquire);
    if (now_us >= checked_us and now_us - checked_us < AUTO_SOURCE_RECHECK_US) {
        return @enumFromInt(cached_auto_source.load(.acquire));
    }

    var tmp_buf: [32]u8 = undefined;
    const tmp_len = spotifast.widget_query_spotifast(&tmp_buf, tmp_buf.len);
    const source: state.MediaSource =
        if (tmp_len > 0 and !std.mem.eql(u8, tmp_buf[0..tmp_len], "CLOSED"))
            .spotifast
        else
            .now_playing;

    cached_auto_source.store(@intFromEnum(source), .release);
    cached_auto_source_checked_us.store(now_us, .release);
    return source;
}

fn commandWorkerLoop() void {
    while (true) {
        if (command_sema) |s| {
            _ = dispatch_semaphore_wait(s, ~@as(u64, 0));
        }

        var action: ?MediaAction = null;
        {
            lockQueue();
            defer unlockQueue();
            if (queue_count > 0) {
                action = action_queue[queue_tail];
                queue_tail = (queue_tail + 1) % ACTION_QUEUE_CAPACITY;
                queue_count -= 1;
            }
        }

        if (action) |act| {
            switch (act.kind) {
                .command => triggerCommandInner(act.cmd),
                .seek => triggerSeekInner(act.seek_target),
            }
        }
    }
}

pub fn ensureWorkerStarted() void {
    if (worker_started.swap(true, .acq_rel)) return;
    command_sema = dispatch_semaphore_create(0);
    std.log.info("media: command worker starting", .{});
    const t = std.Thread.spawn(.{}, commandWorkerLoop, .{}) catch {
        worker_started.store(false, .release);
        return;
    };
    t.detach();
}

fn enqueueAction(action: MediaAction) void {
    ensureWorkerStarted();

    lockQueue();
    defer unlockQueue();

    // If it's a seek action and the most recent queued action is also a seek, coalesce it!
    // Rapidly scrubbing the progress bar generates hundreds of seek commands per second.
    // Sending all of these to MediaRemote would saturate the macOS IPC queue, causing the media daemon
    // to freeze or crash. By collapsing contiguous seek requests, we only ever dispatch the very last
    // thumb position when the queue worker wakes up.
    if (action.kind == .seek and queue_count > 0) {
        const last_idx = (queue_tail + queue_count - 1) % ACTION_QUEUE_CAPACITY;
        if (action_queue[last_idx].kind == .seek) {
            action_queue[last_idx].seek_target = action.seek_target;
            return;
        }
    }

    if (queue_count < ACTION_QUEUE_CAPACITY) {
        const idx = (queue_tail + queue_count) % ACTION_QUEUE_CAPACITY;
        action_queue[idx] = action;
        queue_count += 1;
        if (command_sema) |s| {
            _ = dispatch_semaphore_signal(s);
        }
    }
}

pub fn triggerSeek(target: f64) void {
    std.log.info("media: queue seek={d:.2}s, source={s}", .{ target, @tagName(getActiveSource()) });
    enqueueAction(.{ .kind = .seek, .seek_target = target });
}

pub fn triggerCommand(cmd: MediaRemoteCommand) void {
    std.log.info("media: queue command={s}, source={s}", .{
        @tagName(cmd),
        @tagName(getActiveSource()),
    });
    enqueueAction(.{ .kind = .command, .cmd = cmd });
}

pub fn togglePlayback() void {
    const now = window.widget_monotonic_time();
    std.log.info("media: toggle playback at position={d:.2}s, current_rate={d:.2}", .{
        state.playback_clock.position(now, state.global_duration),
        state.global_rate,
    });
    const target_rate: f64 = if (state.global_rate > 0) RATE_STOPPED else RATE_PLAYING;
    const position = state.playback_clock.position(now, state.global_duration);
    state.playback_state.request(target_rate > 0, now);
    state.global_rate = target_rate;
    state.global_elapsed = position;
    state.playback_clock.sync(position, target_rate, now, state.global_duration, true);
    triggerCommand(if (target_rate > 0) .play else .pause);
    state.global_rate_lock = RATE_LOCKED;
    state.global_rate_lock_until = now + RATE_LOCK_DURATION;
    state.requestFrame();
}

/// Called from the CGEventTap in native.m when a hardware media key is pressed.
/// keyCode: 16=play-pause, 19=next, 20=previous (NX_KEYTYPE constants).
/// Routes the command based on setting_media_key_target, bypassing the normal
/// active-source resolution so the user's explicit override is always honored.
pub export fn wallify_media_key_event(keyCode: c_int) callconv(.c) void {
    // Play/pause and track controls honor the same explicit target selection.
    // The event tap should normally be absent while .off, but keep this safe
    // if a stale event arrives during teardown.
    if (state.setting_media_key_target == .off) return;

    if (keyCode == 16) {
        switch (state.setting_media_key_target) {
            .active => togglePlayback(),
            .spotify => spotify.widget_spotify_control(.play_pause),
            .spotifast => spotifast.widget_spotifast_control(.play_pause),
            .off => {},
        }
        return;
    }

    const cmd: MediaRemoteCommand = switch (keyCode) {
        19 => .next_track,
        20 => .previous_track,
        else => return,
    };

    switch (state.setting_media_key_target) {
        .off => {}, // tap shouldn't be installed when off, but be safe
        .active => triggerCommand(cmd),
        .spotify => switch (cmd) {
            .next_track => spotify.widget_spotify_control(.next_track),
            .previous_track => spotify.widget_spotify_control(.previous_track),
            else => {},
        },
        .spotifast => switch (cmd) {
            .next_track => spotifast.widget_spotifast_control(.next_track),
            .previous_track => spotifast.widget_spotifast_control(.previous_track),
            else => {},
        },
    }
}

pub fn utf8Prefix(text: []const u8, max_len: usize) []const u8 {
    var len = @min(text.len, max_len);
    if (len < text.len) {
        while (len > 0 and (text[len] & 0xc0) == 0x80) len -= 1;
    }
    return text[0..len];
}

pub const SpotifyPayload = struct {
    title: []const u8,
    artist: []const u8,
    playing: bool,
    elapsed: f64,
    duration: f64,
    artwork_url: []const u8,
};

var spotify_download_gen = std.atomic.Value(u32).init(0);

fn spotifyDownloadWorker(url: []const u8, gen: u32, _: std.Io) void {
    defer std.heap.page_allocator.free(url);

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const tmp_path_c = std.fmt.allocPrint(arena.allocator(), "/tmp/art_sp_{}.raw\x00", .{gen}) catch return;

    const macos = @import("../platform/macos.zig");
    const pool = macos.send(macos.Ref, macos.send(macos.Ref, macos.objc_getClass("NSAutoreleasePool"), "alloc", .{}), "init", .{});

    const ns_url_str = macos.string(url);
    const nsurl = macos.send(macos.Ref, macos.objc_getClass("NSURL"), "URLWithString:", .{ns_url_str});
    const data = macos.send(macos.Ref, macos.objc_getClass("NSData"), "dataWithContentsOfURL:", .{nsurl});

    var curl_ok = false;
    if (data != null) {
        const dest_path = macos.string(tmp_path_c[0 .. tmp_path_c.len - 1]);
        curl_ok = macos.send(bool, data, "writeToFile:atomically:", .{ dest_path, true });
        macos.CFRelease(dest_path);
    }

    macos.CFRelease(ns_url_str);
    macos.send(void, pool, "release", .{});

    if (spotify_download_gen.load(.acquire) != gen) {
        _ = std.posix.system.unlink(@ptrCast(tmp_path_c.ptr));
        return;
    }

    if (curl_ok) {
        std.log.info("media: artwork download complete, generation={d}", .{gen});
        _ = std.posix.system.rename(@ptrCast(tmp_path_c.ptr), "/tmp/art.raw");
        state.global_has_artwork = true;
        state.artwork_refresh_pending = true;
        render.extractColor();
    } else {
        std.log.warn("media: artwork download failed, generation={d}", .{gen});
        _ = std.posix.system.unlink(@ptrCast(tmp_path_c.ptr));
        state.global_has_artwork = false;
        _ = std.posix.system.unlink("/tmp/art.raw");
    }
    state.requestFrame();
}

pub fn parseSpotifyPayload(raw: []const u8) ?SpotifyPayload {
    var spl = std.mem.splitSequence(u8, raw, "|||");
    const title = spl.next() orelse return null;
    const artist = spl.next() orelse return null;
    const pstate = spl.next() orelse return null;
    const pos_raw = spl.next() orelse "0.0";
    const dur_raw = spl.next() orelse "0.0";
    const art = spl.next() orelse "";

    return .{
        .title = title,
        .artist = artist,
        .playing = std.mem.eql(u8, pstate, "playing"),
        .elapsed = std.fmt.parseFloat(f64, pos_raw) catch 0.0,
        .duration = std.fmt.parseFloat(f64, dur_raw) catch 0.0,
        .artwork_url = art,
    };
}

pub fn metadataLoop(io: std.Io) void {
    // MediaRemote is a locked private framework. Processes can only access it if their bundle ID starts with `com.apple.`.
    // We pipe a script with DynaLoader into `/usr/bin/perl` because its `com.apple.perl` bundle ID bypasses the restriction.
    // If the main Zig process crashes, the pipe breaks and Perl immediately exits ($SIG{PIPE}), avoiding zombie processes.
    const perl_cmd =
        "use strict; use warnings; use Cwd qw(abs_path); use DynaLoader; $| = 1; " ++
        "$SIG{PIPE} = sub { exit(0); }; " ++
        "my $abs; for my $p ($ENV{WALLIFY_FETCHER_DYLIB} || (), qw(zig-out/lib/libmetadata_fetcher.dylib ../Frameworks/libmetadata_fetcher.dylib ../Resources/libmetadata_fetcher.dylib ../Resources/zig-out/lib/libmetadata_fetcher.dylib /Applications/Wallify.app/Contents/Frameworks/libmetadata_fetcher.dylib)) { if ($p && -f $p) { $abs = abs_path($p); last; } } " ++
        "if (!$abs) { exit(1); } " ++
        "my $libref = DynaLoader::dl_load_file($abs) or exit(2); " ++
        "my $sym = DynaLoader::dl_find_symbol($libref, \"mrc_printNowPlayingInfo\") or exit(3); " ++
        "DynaLoader::dl_install_xsub(\"main::fetch\", $sym); " ++
        "print \"$$\\n\"; " ++
        "my $wake = 1; " ++
        "$SIG{USR1} = sub { $wake = 1; }; " ++
        "while (1) { if ($wake) { $wake = 0; fetch(); } sleep(" ++ METADATA_HELPER_FALLBACK_INTERVAL_S ++ "); }";

    // macOS `mediaremoted` is queried through the helper because the framework is private.
    // Keep the helper mostly asleep and use Spotify's distributed notification to wake it immediately on playback changes.
    // A short fallback sleep keeps the metadata fresh even when no notification is emitted.
    const command = "PERL_SIGNALS=unsafe perl -e '" ++ perl_cmd ++ "'";
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    var last_art_url: [ARTWORK_URL_BUFFER_SIZE]u8 = undefined;
    var last_art_url_len: usize = 0;
    var last_source: ?state.MediaSource = null;

    while (true) {
        const active_source = getActiveSource();
        if (last_source == null or active_source != last_source.?) {
            std.log.info("media: active source -> {s}", .{@tagName(active_source)});
            last_source = active_source;
            state.spotify_closed.store(false, .release);
            last_art_url_len = 0; // Force Spotify art re-download
            state.artwork_refresh_pending = true; // Force Now Playing art reload
            state.global_title_len = 0; // Force title change to trigger updates
        }

        if (active_source == .spotify or active_source == .spotifast) {
            _ = arena.reset(.retain_capacity);
            var res_buf: [ARTWORK_REQUEST_BUFFER_SIZE]u8 = undefined;
            const res_len = if (active_source == .spotifast)
                spotifast.widget_query_spotifast(&res_buf, res_buf.len)
            else
                spotify.widget_query_spotify(&res_buf, res_buf.len);

            // Query failures do not mean the application closed.
            if (res_len == 0) {
                sleep_ms(QUERY_FAILURE_RETRY_MS);
                continue;
            }
            const closed = std.mem.eql(u8, res_buf[0..res_len], "CLOSED");
            if (state.spotify_closed.swap(closed, .acq_rel) != closed) {
                std.log.info("media: {s} is now {s}", .{
                    if (active_source == .spotifast) "Spotifast" else "Spotify",
                    if (closed) "closed" else "open",
                });
                last_art_url_len = 0;
                state.requestFrame();
            }
            if (closed) {
                const title_span = if (active_source == .spotifast) "Spotifast is Closed" else "Spotify is Closed";
                const artist_span = "Click to Launch";
                if (!std.mem.eql(u8, state.global_title[0..state.global_title_len], title_span)) {
                    @memcpy(state.global_title[0..title_span.len], title_span);
                    state.global_title_len = title_span.len;
                    @memcpy(state.global_artist[0..artist_span.len], artist_span);
                    state.global_artist_len = artist_span.len;
                    state.global_rate = 0.0;
                    state.global_elapsed = 0.0;
                    state.global_duration = 0.0;
                    state.global_has_artwork = false;
                    render.clearArtwork();
                    state.requestFrame();
                }
                sleep_ms(QUERY_FAILURE_RETRY_MS);
                continue;
            }

            if (std.mem.eql(u8, res_buf[0..res_len], "NO_TRACK")) {
                const title_span = if (active_source == .spotifast) "Spotifast" else "Spotify";
                const artist_span = "No Track Playing";
                if (!std.mem.eql(u8, state.global_title[0..state.global_title_len], title_span)) {
                    @memcpy(state.global_title[0..title_span.len], title_span);
                    state.global_title_len = title_span.len;
                    @memcpy(state.global_artist[0..artist_span.len], artist_span);
                    state.global_artist_len = artist_span.len;
                    state.global_rate = 0.0;
                    state.global_elapsed = 0.0;
                    state.global_duration = 0.0;
                    state.global_has_artwork = false;
                    render.clearArtwork();
                    state.requestFrame();
                }
                sleep_ms(SPOTIFY_POLL_INTERVAL_MS);
                continue;
            }

            const maybe_payload: ?SpotifyPayload = if (active_source == .spotifast) blk: {
                if (spotifast.parseSpotifastPayload(res_buf[0..res_len])) |p| {
                    break :blk SpotifyPayload{
                        .title = p.title,
                        .artist = p.artist,
                        .playing = p.playing,
                        .elapsed = p.elapsed,
                        .duration = p.duration,
                        .artwork_url = p.artwork_url,
                    };
                }
                break :blk null;
            } else parseSpotifyPayload(res_buf[0..res_len]);

            if (maybe_payload) |item| {
                const title_changed = item.title.len != state.global_title_len or !std.mem.eql(u8, item.title, state.global_title[0..state.global_title_len]);
                const artist_changed = item.artist.len != state.global_artist_len or !std.mem.eql(u8, item.artist, state.global_artist[0..state.global_artist_len]);
                const now = window.widget_monotonic_time();
                const accept_state = state.playback_state.accept(item.playing, state.global_rate > 0, now, title_changed);
                if (now >= state.global_rate_lock_until or title_changed) {
                    state.global_rate_lock = 0;
                    state.global_rate_lock_until = 0;
                }
                const rate = if (item.playing) RATE_PLAYING else RATE_STOPPED;
                const rate_changed = rate != state.global_rate;
                const elapsed_changed = @abs(item.elapsed - state.global_elapsed) > ELAPSED_CHANGE_THRESHOLD;

                if (title_changed or artist_changed or rate_changed or elapsed_changed) {
                    if (title_changed or artist_changed or rate_changed) {
                        std.log.info("media: {s} — {s} | playing={} | position={d:.2}/{d:.2}s", .{
                            item.title,
                            item.artist,
                            item.playing,
                            item.elapsed,
                            item.duration,
                        });
                    }
                    if (title_changed) {
                        const title_span = utf8Prefix(item.title, state.global_title.len);
                        @memcpy(state.global_title[0..title_span.len], title_span);
                        state.global_title_len = title_span.len;
                    }

                    if (artist_changed) {
                        const artist_span = utf8Prefix(item.artist, state.global_artist.len);
                        @memcpy(state.global_artist[0..artist_span.len], artist_span);
                        state.global_artist_len = artist_span.len;
                    }

                    if (accept_state and !state.global_is_dragging and (state.global_rate_lock == 0 or title_changed)) {
                        state.playback_clock.sync(item.elapsed, rate, window.widget_monotonic_time(), item.duration, title_changed);
                        state.global_rate = rate;
                        state.global_elapsed = item.elapsed;
                    }
                    state.global_duration = item.duration;

                    if (item.artwork_url.len > 0) {
                        const art_changed = item.artwork_url.len != last_art_url_len or !std.mem.eql(u8, item.artwork_url, last_art_url[0..last_art_url_len]);
                        if (art_changed) {
                            std.log.info("media: artwork changed, url_length={d}", .{item.artwork_url.len});
                            @memcpy(last_art_url[0..item.artwork_url.len], item.artwork_url);
                            last_art_url_len = item.artwork_url.len;

                            const url_dup = std.heap.page_allocator.dupe(u8, item.artwork_url) catch continue;
                            const gen = spotify_download_gen.fetchAdd(1, .acq_rel) + 1;

                            const thread = std.Thread.spawn(.{}, spotifyDownloadWorker, .{ url_dup, gen, io }) catch {
                                std.heap.page_allocator.free(url_dup);
                                continue;
                            };
                            thread.detach();
                        }
                    } else if (title_changed) {
                        state.global_has_artwork = false;
                        last_art_url_len = 0;
                    }

                    state.requestFrame();
                }
            }
            if (active_source == .spotify) {
                // Sleep until Spotify signals a playback change, with a bounded
                // fallback refresh so state cannot become stale if a notification is missed.
                _ = spotify.widget_spotify_wait_for_event(SPOTIFY_POLL_INTERVAL_MS);
            } else {
                // Spotifast has no equivalent event stream, so use a low-rate refresh.
                sleep_ms(SPOTIFAST_POLL_INTERVAL_MS);
            }
        } else {
            const stream = popen(command, "r") orelse {
                sleep_ms(SPOTIFAST_POLL_INTERVAL_MS);
                continue;
            };
            var line: [METADATA_LINE_BUFFER_SIZE]u8 = undefined;

            var perl_pid: ?std.posix.pid_t = null;
            if (fgets(&line, line.len, stream) != null) {
                const len = std.mem.indexOfScalar(u8, &line, 0) orelse line.len;
                const pid_str = std.mem.trim(u8, line[0..len], " \r\n");
                perl_pid = std.fmt.parseInt(std.posix.pid_t, pid_str, 10) catch null;
            }

            // Spotify now wakes the Perl helper directly from its distributed
            // notification callback; no polling watcher thread is necessary.
            if (perl_pid) |pid| {
                spotify.widget_spotify_set_helper_pid(@intCast(pid));
            }

            var empty_polls: usize = 0;
            var empty_art_polls: usize = 0;
            while (fgets(&line, line.len, stream) != null) {
                if (getActiveSource() != .now_playing) break;

                _ = arena.reset(.retain_capacity);
                const line_len = std.mem.indexOfScalar(u8, &line, 0) orelse line.len;
                const raw = std.mem.trim(u8, line[0..line_len], " \r\n");

                if (raw.len == 0) {
                    empty_polls += 1;
                    if (empty_polls >= 3) {
                        if (state.global_title_len > 0 or state.global_rate > 0 or state.global_has_artwork) {
                            state.global_title_len = 0;
                            state.global_artist_len = 0;
                            state.global_rate = 0.0;
                            state.global_elapsed = 0.0;
                            state.global_duration = 0.0;
                            state.global_has_artwork = false;
                            render.clearArtwork();
                            state.requestFrame();
                        }
                    }
                    continue;
                }
                empty_polls = 0;

                var spl = std.mem.splitSequence(u8, raw, "|||");

                const title_raw = spl.next() orelse "";
                const artist_raw = spl.next() orelse "";
                const title_span = utf8Prefix(title_raw, state.global_title.len);
                const artist_span = utf8Prefix(artist_raw, state.global_artist.len);
                const has_artwork_span = spl.next() orelse "0";
                const rate_span = spl.next() orelse "0.0";
                const elapsed_span = spl.next() orelse "0.0";
                const duration_span = spl.next() orelse "0.0";

                const rate = std.fmt.parseFloat(f64, rate_span) catch 0.0;
                const elapsed = std.fmt.parseFloat(f64, elapsed_span) catch 0.0;
                const duration = std.fmt.parseFloat(f64, duration_span) catch 0.0;

                if (title_span.len == 0) continue;
                const title_changed = title_span.len != state.global_title_len or !std.mem.eql(u8, title_span, state.global_title[0..state.global_title_len]);
                const artist_changed = artist_span.len != state.global_artist_len or !std.mem.eql(u8, artist_span, state.global_artist[0..state.global_artist_len]);
                const now = window.widget_monotonic_time();
                const accept_state = state.playback_state.accept(rate > 0, state.global_rate > 0, now, title_changed);
                if (now >= state.global_rate_lock_until or title_changed) {
                    state.global_rate_lock = 0;
                    state.global_rate_lock_until = 0;
                }
                const rate_changed = rate != state.global_rate;
                const elapsed_changed = elapsed != state.global_elapsed;

                if (title_changed or artist_changed or rate_changed or elapsed_changed or (state.artwork_refresh_pending and std.mem.eql(u8, has_artwork_span, "1"))) {
                    if (title_changed) {
                        @memcpy(state.global_title[0..title_span.len], title_span);
                        state.global_title_len = title_span.len;
                    }

                    if (artist_changed) {
                        @memcpy(state.global_artist[0..artist_span.len], artist_span);
                        state.global_artist_len = artist_span.len;
                    }

                    if (accept_state and !state.global_is_dragging and (state.global_rate_lock == 0 or title_changed)) {
                        state.playback_clock.sync(elapsed, rate, window.widget_monotonic_time(), duration, title_changed);
                        state.global_rate = rate;
                        state.global_elapsed = elapsed;
                    }
                    state.global_duration = duration;

                    if (title_changed or artist_changed) {
                        state.artwork_refresh_pending = true;
                        empty_art_polls = 0;
                    }
                    const artwork_available = std.mem.eql(u8, has_artwork_span, "1");
                    if (artwork_available and state.artwork_refresh_pending) {
                        state.artwork_refresh_pending = false;
                        if (std.posix.system.rename("/tmp/mrc_artwork", "/tmp/art.raw") == 0) {
                            state.global_has_artwork = true;
                            render.extractColor();
                        } else {
                            // rename fails if metadata_fetcher bypassed writing (e.g. same album art hash)
                            // In this case, /tmp/art.raw already has the correct image!
                            state.global_has_artwork = true;
                            render.extractColor();
                        }
                    } else if (!artwork_available and state.artwork_refresh_pending) {
                        empty_art_polls += 1;
                        if (empty_art_polls >= 30) {
                            state.artwork_refresh_pending = false;
                            state.global_has_artwork = false;
                            render.clearArtwork();
                        }
                    }
                    state.requestFrame();
                }
            }
            spotify.widget_spotify_set_helper_pid(-1);
            _ = pclose(stream);
            sleep_ms(SPOTIFY_POLL_INTERVAL_MS); // Restart the helper if its stream closes.
        }
    }
}

test "utf8Prefix preserves short strings and chops safely on boundaries" {
    const ascii = "Hello World";
    try std.testing.expectEqualStrings("Hello World", utf8Prefix(ascii, 20));
    try std.testing.expectEqualStrings("Hello", utf8Prefix(ascii, 5));

    // Multi-byte characters: "café" (c a f \xc3 \xa9) -> 5 bytes
    const cafe = "café";
    try std.testing.expectEqualStrings("café", utf8Prefix(cafe, 5));
    // Slicing at max_len=4 falls on the second byte of '\xe9'. utf8Prefix should back up to 3 ("caf")
    try std.testing.expectEqualStrings("caf", utf8Prefix(cafe, 4));
}

test "parseSpotifyPayload parses full format correctly" {
    const payload = "Track Title|||Artist Name|||playing|||45.5|||200.0|||https://example.com/art.jpg";
    const res = parseSpotifyPayload(payload).?;
    try std.testing.expectEqualStrings("Track Title", res.title);
    try std.testing.expectEqualStrings("Artist Name", res.artist);
    try std.testing.expect(res.playing);
    try std.testing.expectApproxEqAbs(@as(f64, 45.5), res.elapsed, 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, 200.0), res.duration, 0.001);
    try std.testing.expectEqualStrings("https://example.com/art.jpg", res.artwork_url);
}

test "parseSpotifyPayload returns null for truncated inputs" {
    try std.testing.expect(parseSpotifyPayload("") == null);
    try std.testing.expect(parseSpotifyPayload("Only Title") == null);
}

test "action queue coalesces seeks and ensures bounded capacity" {
    lockQueue();
    queue_tail = 0;
    queue_count = 0;
    unlockQueue();

    enqueueAction(.{ .kind = .seek, .seek_target = 10.0 });
    enqueueAction(.{ .kind = .seek, .seek_target = 20.0 });

    lockQueue();
    defer unlockQueue();
    try std.testing.expectEqual(@as(usize, 1), queue_count);
    try std.testing.expectApproxEqAbs(@as(f64, 20.0), action_queue[0].seek_target, 0.001);
}
