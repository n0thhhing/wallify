const std = @import("std");

pub const SpotifastControl = enum(c_int) {
    play = 0,
    pause = 1,
    play_pause = 2,
    previous_track = 3,
    next_track = 4,
};

pub const SpotifastPayload = @import("payload.zig").Payload;

pub extern "c" fn widget_open_spotifast() void;
pub extern "c" fn widget_is_spotifast_running() c_int;
pub extern "c" fn widget_spotifast_control(cmd: SpotifastControl) void;
pub extern "c" fn widget_spotifast_seek(position: f64) void;
pub extern "c" fn widget_query_spotifast(buf: [*]u8, max_len: usize) usize;

pub fn parseSpotifastPayload(raw: []const u8) ?SpotifastPayload {
    return @import("payload.zig").parse(raw, .spotifast);
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
