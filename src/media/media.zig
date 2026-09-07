const std = @import("std");
const state = @import("../state.zig");
const macos = @import("../macos.zig");
const render = @import("../graphics/render.zig");

extern "c" fn rename(old: [*c]const u8, new: [*c]const u8) c_int;
extern "c" fn dlopen(path: [*c]const u8, mode: c_int) ?*anyopaque;
extern "c" fn dlsym(handle: *anyopaque, symbol: [*c]const u8) ?*anyopaque;
extern "c" fn popen(command: [*:0]const u8, mode: [*:0]const u8) ?*anyopaque;
extern "c" fn pclose(stream: *anyopaque) c_int;
extern "c" fn fgets(buffer: [*]u8, size: c_int, stream: *anyopaque) ?[*]u8;
extern "c" fn usleep(useconds: c_uint) c_int;

pub const MRMediaRemoteCommandPlay = 0;
pub const MRMediaRemoteCommandPause = 1;
pub const MRMediaRemoteCommandTogglePlayPause = 2;
pub const MRMediaRemoteCommandStop = 3;
pub const MRMediaRemoteCommandNextTrack = 4;
pub const MRMediaRemoteCommandPreviousTrack = 5;

pub fn triggerSeekInner(target: f64) void {
    if (state.setting_source == 1) {
        macos.widget_spotify_seek(target);
        return;
    }
    const handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", 1);
    if (handle) |h| {
        if (dlsym(h, "MRMediaRemoteSetElapsedTime")) |set_ptr| {
            const MRSetElapsedTime = @as(*const fn (f64) callconv(.c) void, @ptrCast(@alignCast(set_ptr)));
            MRSetElapsedTime(target);
        }
    }
}

pub fn triggerSeek(target: f64) void {
    const t = std.Thread.spawn(.{}, triggerSeekInner, .{target}) catch return;
    t.detach();
}

pub fn triggerCommandInner(cmd: u32) void {
    if (state.setting_source == 1) {
        if (cmd == MRMediaRemoteCommandPlay) macos.widget_spotify_control(0);
        if (cmd == MRMediaRemoteCommandPause) macos.widget_spotify_control(1);
        if (cmd == MRMediaRemoteCommandPreviousTrack) macos.widget_spotify_control(3);
        if (cmd == MRMediaRemoteCommandNextTrack) macos.widget_spotify_control(4);
        return;
    }
    const handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", 1);
    if (handle) |h| {
        if (dlsym(h, "MRMediaRemoteSendCommand")) |cmd_ptr| {
            const MRMediaRemoteSendCommandFunc = @as(*const fn (c_uint, ?*anyopaque) callconv(.c) void, @ptrCast(@alignCast(cmd_ptr)));
            MRMediaRemoteSendCommandFunc(cmd, null);
        }
    }
}

pub fn triggerCommand(cmd: u32) void {
    const t = std.Thread.spawn(.{}, triggerCommandInner, .{cmd}) catch return;
    t.detach();
}

pub fn togglePlayback() void {
    const now = macos.widget_monotonic_time();
    const target_rate: f64 = if (state.global_rate > 0) 0 else 1;
    const position = state.playback_clock.position(now, state.global_duration);
    state.playback_state.request(target_rate > 0, now);
    state.global_rate = target_rate;
    state.global_elapsed = position;
    state.playback_clock.sync(position, target_rate, now, state.global_duration, true);
    triggerCommand(if (target_rate > 0) MRMediaRemoteCommandPlay else MRMediaRemoteCommandPause);
    state.global_rate_lock = 1;
    state.global_rate_lock_until = now + 1.5;
    state.requestFrame();
}

fn utf8Prefix(text: []const u8, max_len: usize) []const u8 {
    var len = @min(text.len, max_len);
    if (len < text.len) {
        while (len > 0 and (text[len] & 0xc0) == 0x80) len -= 1;
    }
    return text[0..len];
}

pub fn metadataLoop(io: std.Io) void {
    const perl_cmd =
        "use strict; use warnings; use Cwd \"abs_path\"; use DynaLoader; $| = 1; " ++
        "my $abs = abs_path(\"zig-out/lib/libmetadata_fetcher.dylib\"); " ++
        "if (!$abs) { exit(1); } " ++
        "my $libref = DynaLoader::dl_load_file($abs) or exit(2); " ++
        "my $sym = DynaLoader::dl_find_symbol($libref, \"mrc_printNowPlayingInfo\") or exit(3); " ++
        "DynaLoader::dl_install_xsub(\"main::fetch\", $sym); " ++
        "use Time::HiRes qw(usleep); while (1) { fetch(); usleep(100000); }";

    const command = "perl -e '" ++ perl_cmd ++ "'";
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    var last_art_url: [512]u8 = undefined;
    var last_art_url_len: usize = 0;
    var last_source: u8 = 255; // Force initial mismatch

    while (true) {
        if (state.setting_source != last_source) {
            last_source = state.setting_source;
            last_art_url_len = 0; // Force Spotify art re-download
            state.artwork_refresh_pending = true; // Force Now Playing art reload
            state.global_title_len = 0; // Force title change to trigger updates
        }

        if (state.setting_source == 1) {
            _ = arena.reset(.retain_capacity);
            var res_buf: [1024]u8 = undefined;
            const res_len = macos.widget_query_spotify(&res_buf, res_buf.len);

            if (res_len == 0 or std.mem.eql(u8, res_buf[0..res_len], "CLOSED")) {
                const title_span = "Spotify is Closed";
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
                    state.requestFrame();
                }
                _ = usleep(500_000);
                continue;
            }

            if (std.mem.eql(u8, res_buf[0..res_len], "NO_TRACK")) {
                const title_span = "Spotify";
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
                    state.requestFrame();
                }
                _ = usleep(250_000);
                continue;
            }

            // Format: Title|||Artist|||State|||Position|||Duration|||ArtworkURL
            var spl = std.mem.splitSequence(u8, res_buf[0..res_len], "|||");
            const title_raw = spl.next() orelse "";
            const artist_raw = spl.next() orelse "";
            const pstate_raw = spl.next() orelse "";
            const pos_raw = spl.next() orelse "0.0";
            const dur_raw = spl.next() orelse "0.0";
            const art_raw = spl.next() orelse "";

            const title_span = utf8Prefix(title_raw, state.global_title.len);
            const artist_span = utf8Prefix(artist_raw, state.global_artist.len);

            const rate: f64 = if (std.mem.eql(u8, pstate_raw, "playing")) 1.0 else 0.0;
            const elapsed = std.fmt.parseFloat(f64, pos_raw) catch 0.0;
            const duration = std.fmt.parseFloat(f64, dur_raw) catch 0.0;

            if (title_span.len > 0) {
                const title_changed = title_span.len != state.global_title_len or !std.mem.eql(u8, title_span, state.global_title[0..state.global_title_len]);
                const artist_changed = artist_span.len != state.global_artist_len or !std.mem.eql(u8, artist_span, state.global_artist[0..state.global_artist_len]);
                const now = macos.widget_monotonic_time();

                if (now >= state.global_rate_lock_until or title_changed) {
                    state.global_rate_lock = 0;
                    state.global_rate_lock_until = 0;
                }
                const rate_changed = rate != state.global_rate;
                const elapsed_changed = @abs(elapsed - state.global_elapsed) > 1.5;

                if (title_changed or artist_changed or rate_changed or elapsed_changed) {
                    @memcpy(state.global_title[0..title_span.len], title_span);
                    state.global_title_len = title_span.len;

                    @memcpy(state.global_artist[0..artist_span.len], artist_span);
                    state.global_artist_len = artist_span.len;

                    if (!state.global_is_dragging and (state.global_rate_lock == 0 or title_changed)) {
                        state.playback_clock.sync(elapsed, rate, macos.widget_monotonic_time(), duration, title_changed);
                        state.global_rate = rate;
                        state.global_elapsed = elapsed;
                    }
                    state.global_duration = duration;

                    if (art_raw.len > 0 and std.mem.startsWith(u8, art_raw, "http")) {
                        if (art_raw.len != last_art_url_len or !std.mem.eql(u8, art_raw, last_art_url[0..last_art_url_len])) {
                            @memcpy(last_art_url[0..art_raw.len], art_raw);
                            last_art_url_len = art_raw.len;

                            _ = std.process.run(arena.allocator(), io, .{ .argv = &[_][]const u8{ "curl", "-s", "-f", art_raw, "-o", "/tmp/mrc_art_raw" } }) catch {};
                            _ = std.process.run(arena.allocator(), io, .{ .argv = &[_][]const u8{ "sips", "-z", "512", "512", "-s", "format", "bmp", "/tmp/mrc_art_raw", "--out", "/tmp/art-next.bmp" } }) catch {};
                            if (rename("/tmp/art-next.bmp", "/tmp/art.bmp") == 0) {
                                state.global_has_artwork = true;
                                render.extractColor();
                            }
                        }
                    } else if (title_changed) {
                        state.global_has_artwork = false;
                        last_art_url_len = 0;
                    }

                    state.requestFrame();
                }
            }
            _ = usleep(250_000);
        } else {
            const stream = popen(command, "r") orelse {
                _ = usleep(250_000);
                continue;
            };
            var line: [2048]u8 = undefined;
            while (fgets(&line, line.len, stream) != null) {
                if (state.setting_source == 1) break;

                _ = arena.reset(.retain_capacity);
                const line_len = std.mem.indexOfScalar(u8, &line, 0) orelse line.len;
                const raw = std.mem.trim(u8, line[0..line_len], " \r\n");

                if (raw.len > 0) {
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
                    const now = macos.widget_monotonic_time();
                    const accept_state = state.playback_state.accept(rate > 0, state.global_rate > 0, now, title_changed);
                    if (now >= state.global_rate_lock_until or title_changed) {
                        state.global_rate_lock = 0;
                        state.global_rate_lock_until = 0;
                    }
                    const rate_changed = rate != state.global_rate;
                    const elapsed_changed = elapsed != state.global_elapsed;

                    if (title_changed or artist_changed or rate_changed or elapsed_changed or (state.artwork_refresh_pending and std.mem.eql(u8, has_artwork_span, "1"))) {
                        @memcpy(state.global_title[0..title_span.len], title_span);
                        state.global_title_len = title_span.len;

                        @memcpy(state.global_artist[0..artist_span.len], artist_span);
                        state.global_artist_len = artist_span.len;

                        if (accept_state and !state.global_is_dragging and (state.global_rate_lock == 0 or title_changed)) {
                            state.playback_clock.sync(elapsed, rate, macos.widget_monotonic_time(), duration, title_changed);
                            state.global_rate = rate;
                            state.global_elapsed = elapsed;
                        }
                        state.global_duration = duration;

                        if (title_changed or artist_changed) state.artwork_refresh_pending = true;
                        const artwork_available = std.mem.eql(u8, has_artwork_span, "1");
                        if (artwork_available and state.artwork_refresh_pending) {
                            _ = std.process.run(arena.allocator(), io, .{ .argv = &[_][]const u8{ "sips", "-z", "512", "512", "-s", "format", "bmp", "/tmp/mrc_artwork", "--out", "/tmp/art-next.bmp" } }) catch {};
                            if (rename("/tmp/art-next.bmp", "/tmp/art.bmp") == 0) {
                                state.artwork_refresh_pending = false;
                                state.global_has_artwork = true;
                            }
                            render.extractColor();
                        } else if (!artwork_available and title_changed) {
                            state.global_has_artwork = false;
                        }
                        state.requestFrame();
                    }
                }
            }
            _ = pclose(stream);
            _ = usleep(250_000); // Restart the helper if its stream closes.
        }
    }
}
