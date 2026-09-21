const std = @import("std");
const macos = @import("../platform/macos.zig");

pub const SpotifyControl = enum(c_int) {
    play = 0,
    pause = 1,
    play_pause = 2,
    previous_track = 3,
    next_track = 4,
};

var pending_state: std.atomic.Value(c_int) = std.atomic.Value(c_int).init(-1);
var media_helper_pid = std.atomic.Value(c_int).init(-1);
var playback_event_sema: ?*anyopaque = null;

extern "c" fn kill(pid: c_int, sig: c_int) c_int;
extern "c" fn dispatch_semaphore_create(value: isize) ?*anyopaque;
extern "c" fn dispatch_semaphore_signal(dsema: *anyopaque) isize;
extern "c" fn dispatch_semaphore_wait(dsema: *anyopaque, timeout: u64) isize;
extern "c" fn dispatch_time(when: u64, delta: i64) u64;

const SIGUSR1: c_int = 30;
const DISPATCH_TIME_NOW: u64 = 0;
const NSEC_PER_MS: i64 = 1_000_000;

fn spotifyCallback(_: macos.Ref, _: macos.Ref, _: macos.Ref, _: macos.Ref, _: macos.Ref) callconv(.c) void {
    // Signal the metadata worker immediately instead of making it poll.
    if (pending_state.swap(1, .monotonic) == -1) {
        if (playback_event_sema) |sema| {
            _ = dispatch_semaphore_signal(sema);
        }
    }

    // Wake the MediaRemote Perl bridge immediately instead of a dedicated 10 ms
    // polling thread. kill(2) is async-signal-safe and this callback stays tiny.
    const pid = media_helper_pid.load(.acquire);
    if (pid > 0) _ = kill(pid, SIGUSR1);
}

pub export fn widget_spotify_observe() callconv(.c) void {
    if (playback_event_sema == null) {
        playback_event_sema = dispatch_semaphore_create(0);
    }
    const center = macos.CFNotificationCenterGetDistributedCenter();
    const name = macos.string("com.spotify.client.PlaybackStateChanged");
    defer macos.CFRelease(name);
    macos.CFNotificationCenterAddObserver(center, null, spotifyCallback, name, null, 0);
}

pub export fn widget_spotify_take_state() callconv(.c) c_int {
    return pending_state.swap(-1, .monotonic);
}

pub export fn widget_spotify_wait_for_event(timeout_ms: u64) callconv(.c) c_int {
    const sema = playback_event_sema orelse return 0;
    const timeout = dispatch_time(DISPATCH_TIME_NOW, @intCast(timeout_ms * @as(u64, @intCast(NSEC_PER_MS))));
    const signaled = dispatch_semaphore_wait(sema, timeout) == 0;
    if (signaled) {
        _ = pending_state.swap(-1, .monotonic);
        return 1;
    }
    return 0;
}

/// Install the PID of the MediaRemote Perl helper that should be interrupted
/// when Spotify broadcasts PlaybackStateChanged.
pub export fn widget_spotify_set_helper_pid(pid: c_int) void {
    media_helper_pid.store(pid, .release);
}

pub export fn widget_open_spotify() callconv(.c) void {
    const main_q = macos.dispatch_get_main_queue();
    const Work = struct {
        fn run(_: macos.Ref) callconv(.c) void {
            const url_str = macos.string("spotify:");
            defer macos.CFRelease(url_str);
            const url = macos.send(macos.Ref, macos.objc_getClass("NSURL"), "URLWithString:", .{url_str});
            const ws = macos.send(macos.Ref, macos.objc_getClass("NSWorkspace"), "sharedWorkspace", .{});
            _ = macos.send(bool, ws, "openURL:", .{url});
        }
    };
    macos.dispatch_async_f(main_q, null, Work.run);
}

pub export fn widget_is_spotify_running() callconv(.c) c_int {
    const pool = macos.send(macos.Ref, macos.send(macos.Ref, macos.objc_getClass("NSAutoreleasePool"), "alloc", .{}), "init", .{});
    defer macos.send(void, pool, "release", .{});

    const bundle_id = macos.string("com.spotify.client");
    defer macos.CFRelease(bundle_id);

    const apps = macos.send(macos.Ref, macos.objc_getClass("NSRunningApplication"), "runningApplicationsWithBundleIdentifier:", .{bundle_id});
    if (apps == null) return 0;
    const count = macos.send(usize, apps, "count", .{});
    return if (count > 0) 1 else 0;
}

pub fn scriptForControl(cmd: SpotifyControl) []const u8 {
    return switch (cmd) {
        .play => "if application \"Spotify\" is running then\ntell application \"Spotify\" to play\nelse\ntell application \"Spotify\" to activate\nend if",
        .pause => "if application \"Spotify\" is running then tell application \"Spotify\" to pause",
        .play_pause => "if application \"Spotify\" is running then\ntell application \"Spotify\" to playpause\nelse\ntell application \"Spotify\" to activate\nend if",
        .previous_track => "if application \"Spotify\" is running then tell application \"Spotify\" to previous track",
        .next_track => "if application \"Spotify\" is running then tell application \"Spotify\" to next track",
    };
}

pub export fn widget_spotify_control(cmd: SpotifyControl) callconv(.c) void {
    const pool = macos.send(macos.Ref, macos.send(macos.Ref, macos.objc_getClass("NSAutoreleasePool"), "alloc", .{}), "init", .{});
    defer macos.send(void, pool, "release", .{});

    const script_text = scriptForControl(cmd);
    const str = macos.string(script_text);
    defer macos.CFRelease(str);

    const script = macos.send(macos.Ref, macos.send(macos.Ref, macos.objc_getClass("NSAppleScript"), "alloc", .{}), "initWithSource:", .{str});
    if (script != null) {
        defer macos.send(void, script, "release", .{});
        _ = macos.send(macos.Ref, script, "executeAndReturnError:", .{@as(?*macos.Ref, null)});
    }
}

pub export fn widget_spotify_seek(position: f64) callconv(.c) void {
    const pool = macos.send(macos.Ref, macos.send(macos.Ref, macos.objc_getClass("NSAutoreleasePool"), "alloc", .{}), "init", .{});
    defer macos.send(void, pool, "release", .{});

    var buf: [128]u8 = undefined;
    const script_fmt = std.fmt.bufPrintZ(&buf, "tell application \"Spotify\" to set player position to {d:.2}", .{position}) catch return;

    const str = macos.string(script_fmt);
    defer macos.CFRelease(str);

    const script = macos.send(macos.Ref, macos.send(macos.Ref, macos.objc_getClass("NSAppleScript"), "alloc", .{}), "initWithSource:", .{str});
    if (script != null) {
        defer macos.send(void, script, "release", .{});
        _ = macos.send(macos.Ref, script, "executeAndReturnError:", .{@as(?*macos.Ref, null)});
    }
}

var cached_query_script: ?macos.Ref = null;

pub export fn widget_query_spotify(buf: [*]u8, max_len: usize) callconv(.c) usize {
    const pool = macos.send(macos.Ref, macos.send(macos.Ref, macos.objc_getClass("NSAutoreleasePool"), "alloc", .{}), "init", .{});
    defer macos.send(void, pool, "release", .{});

    if (cached_query_script == null) {
        const script_text =
            \\if application "Spotify" is running then
            \\  tell application "Spotify"
            \\      try
            \\          set {tName, tArtist, tState, tPos, tDur, tArt} to {name of current track, artist of current track, player state as string, player position as string, duration of current track, artwork url of current track}
            \\          set tDur to (tDur / 1000.0) as string
            \\          return tName & "|||" & tArtist & "|||" & tState & "|||" & tPos & "|||" & tDur & "|||" & tArt
            \\      on error
            \\          return "NO_TRACK"
            \\      end try
            \\  end tell
            \\else
            \\  return "CLOSED"
            \\end if
        ;

        const str = macos.string(script_text);
        if (str != null) {
            const script_cls = macos.objc_getClass("NSAppleScript");
            cached_query_script = macos.send(macos.Ref, macos.send(macos.Ref, script_cls, "alloc", .{}), "initWithSource:", .{str});
            macos.CFRelease(str);
        }
    }

    const script = cached_query_script orelse return 0;

    const desc = macos.send(macos.Ref, script, "executeAndReturnError:", .{@as(?*macos.Ref, null)});
    if (desc == null) return 0;

    const str_val = macos.send(macos.Ref, desc, "stringValue", .{});
    if (str_val == null) return 0;

    const len = macos.CFStringGetLength(str_val);
    if (len <= 0) return 0;

    var cstr_buf: [1024]u8 = undefined;
    if (macos.CFStringGetCString(str_val, &cstr_buf, cstr_buf.len, 0x08000100) == 0) return 0;

    const slice = std.mem.sliceTo(&cstr_buf, 0);
    const copy_len = @min(slice.len, max_len);
    @memcpy(buf[0..copy_len], slice[0..copy_len]);
    return copy_len;
}

test "scriptForControl generates valid AppleScript commands" {
    const controls = [_]SpotifyControl{ .play, .pause, .play_pause, .previous_track, .next_track };
    for (controls) |cmd| {
        const script = scriptForControl(cmd);
        try std.testing.expect(script.len > 0);
        try std.testing.expect(std.mem.indexOf(u8, script, "tell application \"Spotify\"") != null);
    }
}
