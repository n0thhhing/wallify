const std = @import("std");

pub const SpotifastControl = enum(c_int) {
    play = 0,
    pause = 1,
    play_pause = 2,
    previous_track = 3,
    next_track = 4,
};

pub const SpotifastPayload = struct {
    title: []const u8,
    artist: []const u8,
    playing: bool,
    elapsed: f64,
    duration: f64,
    artwork_url: []const u8,
};

pub extern "c" fn widget_open_spotifast() void;
pub extern "c" fn widget_is_spotifast_running() c_int;
pub extern "c" fn widget_spotifast_control(cmd: SpotifastControl) void;
pub extern "c" fn widget_spotifast_seek(position: f64) void;
pub extern "c" fn widget_query_spotifast(buf: [*]u8, max_len: usize) usize;

pub fn parseSpotifastPayload(raw: []const u8) ?SpotifastPayload {
    // Format: "fastpotify:now <state>\t<title>\t<artists>\t<album>\t<position_ms>\t<duration_ms>\t<volume>\t<shuffle>\t<repeat>\t<art_url>\t<saved>\t<device>"
    const prefix = "fastpotify:now ";
    const data = if (std.mem.startsWith(u8, raw, prefix))
        raw[prefix.len..]
    else
        raw;

    const trimmed = std.mem.trim(u8, data, " \r\n");
    if (std.mem.eql(u8, trimmed, "stopped") or trimmed.len == 0) {
        return null;
    }

    var spl = std.mem.splitScalar(u8, trimmed, '\t');
    const pstate = spl.next() orelse return null;
    const title = spl.next() orelse return null;
    const artist = spl.next() orelse return null;
    _ = spl.next(); // album
    const pos_ms_raw = spl.next() orelse "0";
    const dur_ms_raw = spl.next() orelse "0";
    _ = spl.next(); // volume
    _ = spl.next(); // shuffle
    _ = spl.next(); // repeat
    const art = spl.next() orelse "";

    const pos_ms = std.fmt.parseFloat(f64, pos_ms_raw) catch 0.0;
    const dur_ms = std.fmt.parseFloat(f64, dur_ms_raw) catch 0.0;

    return .{
        .title = title,
        .artist = artist,
        .playing = std.mem.eql(u8, pstate, "playing"),
        .elapsed = pos_ms / 1000.0,
        .duration = dur_ms / 1000.0,
        .artwork_url = art,
    };
}

test "parseSpotifastPayload basic" {
    const raw = "fastpotify:now playing\tTrack Name\tArtist Name\tAlbum Name\t35000\t210000\t70\toff\toff\thttps://example.com/art.jpg\tno\tSpotifast\n";
    const payload = parseSpotifastPayload(raw) orelse return error.TestFailed;
    try std.testing.expectEqualStrings("Track Name", payload.title);
    try std.testing.expectEqualStrings("Artist Name", payload.artist);
    try std.testing.expect(payload.playing);
    try std.testing.expectApproxEqAbs(35.0, payload.elapsed, 0.001);
    try std.testing.expectApproxEqAbs(210.0, payload.duration, 0.001);
    try std.testing.expectEqualStrings("https://example.com/art.jpg", payload.artwork_url);
}

test "parseSpotifastPayload stopped" {
    const raw = "fastpotify:now stopped\n";
    try std.testing.expect(parseSpotifastPayload(raw) == null);
}
