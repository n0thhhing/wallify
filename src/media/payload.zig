const Span = extern struct { offset: usize, count: usize };
const NativePayload = extern struct {
    title: Span,
    artist: Span,
    artwork: Span,
    rate: f64,
    elapsed: f64,
    duration: f64,
    has_artwork: bool,
};

extern fn wallify_parse_media_payload(bytes: [*]const u8, count: usize, format: c_int, output: *NativePayload) callconv(.c) bool;

pub const Format = enum(c_int) { spotify = 0, spotifast = 1, now_playing = 2 };
pub const Payload = struct {
    title: []const u8,
    artist: []const u8,
    artwork_url: []const u8,
    playing: bool,
    rate: f64,
    elapsed: f64,
    duration: f64,
    has_artwork: bool,
};

pub fn parse(raw: []const u8, format: Format) ?Payload {
    var output: NativePayload = undefined;
    if (!wallify_parse_media_payload(raw.ptr, raw.len, @intFromEnum(format), &output)) return null;
    return .{
        .title = raw[output.title.offset..][0..output.title.count],
        .artist = raw[output.artist.offset..][0..output.artist.count],
        .artwork_url = raw[output.artwork.offset..][0..output.artwork.count],
        .playing = output.rate > 0,
        .rate = output.rate,
        .elapsed = output.elapsed,
        .duration = output.duration,
        .has_artwork = output.has_artwork,
    };
}
