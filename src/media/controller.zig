const std = @import("std");
const state = @import("../state.zig");
const render = @import("../graphics/render.zig");
const spotify = @import("spotify.zig");
const window = @import("../ui/window.zig");
const media_remote = @import("../platform/media_remote.zig");

extern "c" fn popen(command: [*c]const u8, modes: [*c]const u8) ?*anyopaque;
extern "c" fn pclose(stream: *anyopaque) c_int;
extern "c" fn fgets(buffer: [*]u8, size: c_int, stream: *anyopaque) ?[*]u8;

fn sleep_ms(ms: u64) void {
    const ts = std.posix.timespec{
        .sec = @intCast(ms / 1000),
        .nsec = @intCast((ms % 1000) * 1_000_000),
    };
    _ = std.posix.system.nanosleep(&ts, null);
}

pub const MediaRemoteCommand = media_remote.MediaRemoteCommand;

pub const MRMediaRemoteCommandPlay = MediaRemoteCommand.play;
pub const MRMediaRemoteCommandPause = MediaRemoteCommand.pause;
pub const MRMediaRemoteCommandTogglePlayPause = MediaRemoteCommand.toggle_play_pause;
pub const MRMediaRemoteCommandStop = MediaRemoteCommand.stop;
pub const MRMediaRemoteCommandNextTrack = MediaRemoteCommand.next_track;
pub const MRMediaRemoteCommandPreviousTrack = MediaRemoteCommand.previous_track;

pub fn triggerSeekInner(target: f64) void {
    if (state.setting_source == .spotify) {
        spotify.widget_spotify_seek(target);
        return;
    }
    media_remote.setElapsedTime(target);
}

pub fn triggerSeek(target: f64) void {
    const t = std.Thread.spawn(.{}, triggerSeekInner, .{target}) catch return;
    t.detach();
}

pub fn triggerCommandInner(cmd: MediaRemoteCommand) void {
    if (state.setting_source == .spotify) {
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
    media_remote.sendCommand(cmd);
}

pub fn triggerCommand(cmd: MediaRemoteCommand) void {
    const t = std.Thread.spawn(.{}, triggerCommandInner, .{cmd}) catch return;
    t.detach();
}

pub fn togglePlayback() void {
    const now = window.widget_monotonic_time();
    const target_rate: f64 = if (state.global_rate > 0) 0 else 1;
    const position = state.playback_clock.position(now, state.global_duration);
    state.playback_state.request(target_rate > 0, now);
    state.global_rate = target_rate;
    state.global_elapsed = position;
    state.playback_clock.sync(position, target_rate, now, state.global_duration, true);
    triggerCommand(if (target_rate > 0) .play else .pause);
    state.global_rate_lock = 1;
    state.global_rate_lock_until = now + 1.5;
    state.requestFrame();
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
    var last_source: ?state.MediaSource = null;

    while (true) {
        if (last_source == null or state.setting_source != last_source.?) {
            last_source = state.setting_source;
            state.spotify_closed.store(false, .release);
            last_art_url_len = 0; // Force Spotify art re-download
            state.artwork_refresh_pending = true; // Force Now Playing art reload
            state.global_title_len = 0; // Force title change to trigger updates
        }

        if (state.setting_source == .spotify) {
            _ = arena.reset(.retain_capacity);
            var res_buf: [1024]u8 = undefined;
            const res_len = spotify.widget_query_spotify(&res_buf, res_buf.len);

            // Query failures do not mean the application closed.
            if (res_len == 0) {
                sleep_ms(500);
                continue;
            }
            const closed = std.mem.eql(u8, res_buf[0..res_len], "CLOSED");
            if (state.spotify_closed.swap(closed, .acq_rel) != closed) {
                last_art_url_len = 0;
                state.requestFrame();
            }
            if (closed) {
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
                sleep_ms(500);
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
                sleep_ms(250);
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
                const now = window.widget_monotonic_time();

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
                        state.playback_clock.sync(elapsed, rate, window.widget_monotonic_time(), duration, title_changed);
                        state.global_rate = rate;
                        state.global_elapsed = elapsed;
                    }
                    state.global_duration = duration;

                    if (art_raw.len > 0 and std.mem.startsWith(u8, art_raw, "http")) {
                        if (art_raw.len != last_art_url_len or !std.mem.eql(u8, art_raw, last_art_url[0..last_art_url_len])) {
                            @memcpy(last_art_url[0..art_raw.len], art_raw);
                            last_art_url_len = art_raw.len;

                            _ = std.process.run(arena.allocator(), io, .{ .argv = &[_][]const u8{ "curl", "-s", "-f", art_raw, "-o", "/tmp/mrc_art_raw" } }) catch {};
                            _ = std.process.run(arena.allocator(), io, .{ .argv = &[_][]const u8{ "sips", "-z", "328", "328", "-s", "format", "bmp", "/tmp/mrc_art_raw", "--out", "/tmp/art-next.bmp" } }) catch {};
                            if (std.posix.system.rename("/tmp/art-next.bmp", "/tmp/art.bmp") == 0) {
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
            sleep_ms(250);
        } else {
            const stream = popen(command, "r") orelse {
                sleep_ms(250);
                continue;
            };
            var line: [2048]u8 = undefined;
            while (fgets(&line, line.len, stream) != null) {
                if (state.setting_source == .spotify) break;

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
                    const now = window.widget_monotonic_time();
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
                            state.playback_clock.sync(elapsed, rate, window.widget_monotonic_time(), duration, title_changed);
                            state.global_rate = rate;
                            state.global_elapsed = elapsed;
                        }
                        state.global_duration = duration;

                        if (title_changed or artist_changed) state.artwork_refresh_pending = true;
                        const artwork_available = std.mem.eql(u8, has_artwork_span, "1");
                        if (artwork_available and state.artwork_refresh_pending) {
                            _ = std.process.run(arena.allocator(), io, .{ .argv = &[_][]const u8{ "sips", "-z", "328", "328", "-s", "format", "bmp", "/tmp/mrc_artwork", "--out", "/tmp/art-next.bmp" } }) catch {};
                            if (std.posix.system.rename("/tmp/art-next.bmp", "/tmp/art.bmp") == 0) {
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
            sleep_ms(250); // Restart the helper if its stream closes.
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
    // Slicing at max_len=4 falls on the second byte of 'é'. utf8Prefix should back up to 3 ("caf")
    try std.testing.expectEqualStrings("caf", utf8Prefix(cafe, 4));

    // Emoji: "🎶" is 4 bytes (\xf0 \x9f \x8e \xb6)
    const emoji = "🎶 Beats";
    try std.testing.expectEqualStrings("🎶 Beats", utf8Prefix(emoji, 20));
    try std.testing.expectEqualStrings("🎶", utf8Prefix(emoji, 4));
    // Slicing at 1, 2, or 3 must not output malformed bytes
    try std.testing.expectEqualStrings("", utf8Prefix(emoji, 1));
    try std.testing.expectEqualStrings("", utf8Prefix(emoji, 2));
    try std.testing.expectEqualStrings("", utf8Prefix(emoji, 3));
}

test "parseSpotifyPayload parses playback attributes" {
    const raw = "Starboy|||The Weeknd|||playing|||45.5|||230.2|||https://example.com/art.jpg";
    const parsed = parseSpotifyPayload(raw).?;
    try std.testing.expectEqualStrings("Starboy", parsed.title);
    try std.testing.expectEqualStrings("The Weeknd", parsed.artist);
    try std.testing.expect(parsed.playing);
    try std.testing.expectApproxEqAbs(@as(f64, 45.5), parsed.elapsed, 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, 230.2), parsed.duration, 0.001);
    try std.testing.expectEqualStrings("https://example.com/art.jpg", parsed.artwork_url);

    const paused_raw = "Blinding Lights|||The Weeknd|||paused|||10.0|||200.0|||";
    const paused = parseSpotifyPayload(paused_raw).?;
    try std.testing.expect(!paused.playing);
    try std.testing.expectEqualStrings("", paused.artwork_url);
}

test "parseSpotifyPayload returns null for truncated inputs" {
    try std.testing.expect(parseSpotifyPayload("") == null);
    try std.testing.expect(parseSpotifyPayload("Only Title") == null);
}
