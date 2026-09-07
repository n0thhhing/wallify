const std = @import("std");
const macos = @import("../macos.zig");

pub const SpotifyControl = enum(c_int) {
    play = 0,
    pause = 1,
    play_pause = 2,
    previous_track = 3,
    next_track = 4,
};

var pending_state: std.atomic.Value(c_int) = std.atomic.Value(c_int).init(-1);

fn spotifyCallback(_: macos.Ref, _: macos.Ref, _: macos.Ref, _: macos.Ref, _: macos.Ref) callconv(.c) void {
    pending_state.store(1, .monotonic);
}

pub export fn widget_spotify_observe() callconv(.c) void {
    const center = macos.CFNotificationCenterGetDistributedCenter();
    const name = macos.string("com.spotify.client.PlaybackStateChanged");
    defer macos.CFRelease(name);
    macos.CFNotificationCenterAddObserver(center, null, spotifyCallback, name, null, 0);
}

pub export fn widget_spotify_take_state() callconv(.c) c_int {
    return pending_state.swap(-1, .monotonic);
}

pub export fn widget_open_spotify() callconv(.c) void {
    const main_q = macos.dispatch_get_main_queue();
    const Work = struct {
        fn run(_: macos.Ref) callconv(.c) void {
            const url_str = macos.string("spotify:");
            defer macos.CFRelease(url_str);
            const url = macos.send1(macos.Ref, macos.objc_getClass("NSURL"), "URLWithString:", macos.Ref, url_str);
            const ws = macos.send0(macos.Ref, macos.objc_getClass("NSWorkspace"), "sharedWorkspace");
            _ = macos.send1(bool, ws, "openURL:", macos.Ref, url);
        }
    };
    macos.dispatch_async_f(main_q, null, Work.run);
}

pub export fn widget_is_spotify_running() callconv(.c) c_int {
    const pool = macos.send0(macos.Ref, macos.send0(macos.Ref, macos.objc_getClass("NSAutoreleasePool"), "alloc"), "init");
    defer macos.send0(void, pool, "release");

    const bundle_id = macos.string("com.spotify.client");
    defer macos.CFRelease(bundle_id);

    const apps = macos.send1(macos.Ref, macos.objc_getClass("NSRunningApplication"), "runningApplicationsWithBundleIdentifier:", macos.Ref, bundle_id);
    if (apps == null) return 0;
    const count = macos.send0(usize, apps, "count");
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
    const pool = macos.send0(macos.Ref, macos.send0(macos.Ref, macos.objc_getClass("NSAutoreleasePool"), "alloc"), "init");
    defer macos.send0(void, pool, "release");

    const script_text = scriptForControl(cmd);
    const str = macos.string(script_text);
    defer macos.CFRelease(str);

    const script = macos.send1(macos.Ref, macos.send0(macos.Ref, macos.objc_getClass("NSAppleScript"), "alloc"), "initWithSource:", macos.Ref, str);
    if (script != null) {
        defer macos.send0(void, script, "release");
        _ = macos.send1(macos.Ref, script, "executeAndReturnError:", ?*macos.Ref, null);
    }
}

pub export fn widget_spotify_seek(position: f64) callconv(.c) void {
    const pool = macos.send0(macos.Ref, macos.send0(macos.Ref, macos.objc_getClass("NSAutoreleasePool"), "alloc"), "init");
    defer macos.send0(void, pool, "release");

    var buf: [128]u8 = undefined;
    const script_fmt = std.fmt.bufPrintZ(&buf, "tell application \"Spotify\" to set player position to {d:.2}", .{position}) catch return;

    const str = macos.string(script_fmt);
    defer macos.CFRelease(str);

    const script = macos.send1(macos.Ref, macos.send0(macos.Ref, macos.objc_getClass("NSAppleScript"), "alloc"), "initWithSource:", macos.Ref, str);
    if (script != null) {
        defer macos.send0(void, script, "release");
        _ = macos.send1(macos.Ref, script, "executeAndReturnError:", ?*macos.Ref, null);
    }
}

pub export fn widget_query_spotify(buf: [*]u8, max_len: usize) callconv(.c) usize {
    const pool = macos.send0(macos.Ref, macos.send0(macos.Ref, macos.objc_getClass("NSAutoreleasePool"), "alloc"), "init");
    defer macos.send0(void, pool, "release");

    const script_text =
        \\if application "Spotify" is running then
        \\  tell application "Spotify"
        \\      try
        \\          set tName to name of current track
        \\          set tArtist to artist of current track
        \\          set tState to player state as string
        \\          set tPos to player position as string
        \\          set tDur to ((duration of current track) / 1000.0) as string
        \\          set tArt to artwork url of current track
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
    if (str == null) return 0;
    defer macos.CFRelease(str);

    const script_cls = macos.objc_getClass("NSAppleScript");
    const script = macos.send1(macos.Ref, macos.send0(macos.Ref, script_cls, "alloc"), "initWithSource:", macos.Ref, str);
    if (script == null) return 0;
    defer macos.send0(void, script, "release");

    const desc = macos.send1(macos.Ref, script, "executeAndReturnError:", ?*macos.Ref, null);
    if (desc == null) return 0;

    const str_val = macos.send0(macos.Ref, desc, "stringValue");
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

test "widget_spotify_take_state resets pending state" {
    pending_state.store(1, .monotonic);
    try std.testing.expectEqual(@as(c_int, 1), widget_spotify_take_state());
    try std.testing.expectEqual(@as(c_int, -1), widget_spotify_take_state());
}
