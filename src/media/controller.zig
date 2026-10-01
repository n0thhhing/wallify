const std = @import("std");
const render = @import("../graphics/render.zig");
const payload = @import("payload.zig");
pub const MediaRemoteCommand = @import("../platform/media_remote.zig").MediaRemoteCommand;
pub const SpotifyPayload = payload.Payload;

extern fn wallify_enqueue_media_command(command: u32) callconv(.c) void;
extern fn wallify_enqueue_media_seek(target: f64) callconv(.c) void;
extern fn wallify_native_media_command(command: u32) callconv(.c) void;
extern fn wallify_native_media_seek(target: f64) callconv(.c) void;
extern fn wallify_native_toggle_playback() callconv(.c) void;
extern fn wallify_native_media_key(code: c_int) callconv(.c) void;
extern fn wallify_native_artwork_downloaded(available: bool) callconv(.c) void;
extern fn wallify_metadata_loop() callconv(.c) void;

pub fn triggerSeekInner(target: f64) void {
    wallify_native_media_seek(target);
}
pub fn triggerCommandInner(command: MediaRemoteCommand) void {
    wallify_native_media_command(@intFromEnum(command));
}
pub fn triggerSeek(target: f64) void {
    wallify_enqueue_media_seek(target);
}
pub fn triggerCommand(command: MediaRemoteCommand) void {
    wallify_enqueue_media_command(@intFromEnum(command));
}
pub fn togglePlayback() void {
    wallify_native_toggle_playback();
}
pub fn metadataLoop(_: std.Io) void {
    wallify_metadata_loop();
}

pub export fn wallify_execute_media_command(command: u32) callconv(.c) void {
    wallify_native_media_command(command);
}
pub export fn wallify_execute_media_seek(target: f64) callconv(.c) void {
    wallify_native_media_seek(target);
}
pub export fn wallify_menu_play_pause() callconv(.c) void {
    togglePlayback();
}
pub export fn wallify_menu_previous() callconv(.c) void {
    triggerCommand(.previous_track);
}
pub export fn wallify_menu_next() callconv(.c) void {
    triggerCommand(.next_track);
}
pub export fn wallify_media_key_event(code: c_int) callconv(.c) void {
    wallify_native_media_key(code);
}
pub export fn wallify_artwork_downloaded(available: bool) callconv(.c) void {
    wallify_native_artwork_downloaded(available);
}
pub export fn wallify_clear_artwork() callconv(.c) void {
    render.clearArtwork();
}
pub export fn wallify_extract_color() callconv(.c) void {
    render.extractColor();
}
pub fn parseSpotifyPayload(raw: []const u8) ?SpotifyPayload {
    return payload.parse(raw, .spotify);
}

pub fn utf8Prefix(text: []const u8, max_len: usize) []const u8 {
    var len = @min(text.len, max_len);
    if (len < text.len) {
        while (len > 0 and (text[len] & 0xc0) == 0x80) len -= 1;
    }
    return text[0..len];
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
    const raw = "Track Title|||Artist Name|||playing|||45.5|||200.0|||https://example.com/art.jpg";
    const res = parseSpotifyPayload(raw).?;
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
