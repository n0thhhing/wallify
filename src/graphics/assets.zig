const std = @import("std");
const native = @import("../platform/native.zig");
const state = @import("../state.zig");
const symbols = @import("symbols.zig");
const sprites = @import("sprites.zig");
pub const Texture = @import("canvas.zig").Texture;
pub var artwork_dirty = std.atomic.Value(bool).init(true);
pub var has_art = false;
var initialized = false;
var art_hash: ?u64 = null;
pub const transition_duration = 0.5;

fn upload(texture: Texture, pixels: []const u32, w: usize, h: usize) void {
    native.wallify_load_texture(@intFromEnum(texture), pixels.ptr, w, h);
}
pub fn init() !void {
    if (initialized) return;
    upload(.white, &.{0xffffffff}, 1, 1);
    const cat = try std.heap.page_allocator.alloc(u32, sprites.cat_width * sprites.cat_height);
    defer std.heap.page_allocator.free(cat);
    try sprites.decode(sprites.cat_data, cat);
    upload(.cat, cat, sprites.cat_width, sprites.cat_height);
    const banana_h = sprites.banana_frame_height * sprites.banana_frames;
    const banana = try std.heap.page_allocator.alloc(u32, sprites.banana_width * banana_h);
    defer std.heap.page_allocator.free(banana);
    try sprites.decode(sprites.banana_data, banana);
    upload(.banana, banana, sprites.banana_width, banana_h);
    var icon: [96 * 96]u32 = undefined;
    for ([_]Texture{ .play, .pause, .previous, .next }, 0..) |texture, i| {
        @memset(&icon, 0);
        symbols.widget_icon(&icon, 96, 96, 48, 48, @enumFromInt(i), 0, 1, 2);
        upload(texture, &icon, 96, 96);
    }
    const spotify = try std.heap.page_allocator.alloc(u32, 384 * 384);
    defer std.heap.page_allocator.free(spotify);
    @memset(spotify, 0);
    _ = symbols.widget_spotify_icon(spotify.ptr, 384, 384, 0, 0, 384);
    upload(.spotify, spotify, 384, 384);
    initialized = true;
}

pub const Bitmap = struct {
    data: []const u8,
    w: usize,
    h: usize,
    stride: usize,
    offset: usize,
    top_down: bool,
    pub fn parse(data: []const u8) !Bitmap {
        if (data.len < 54 or !std.mem.eql(u8, data[0..2], "BM")) return error.InvalidBitmap;
        const w = std.mem.readInt(i32, data[18..22], .little);
        const h = std.mem.readInt(i32, data[22..26], .little);
        const offset = std.mem.readInt(u32, data[10..14], .little);
        if (w <= 0 or h == 0 or h == std.math.minInt(i32) or w > 4096 or @abs(h) > 4096 or std.mem.readInt(u16, data[28..30], .little) != 24 or std.mem.readInt(u32, data[30..34], .little) != 0) return error.InvalidBitmap;
        const width: usize = @intCast(w);
        const height: usize = @intCast(@abs(h));
        const stride = (width * 3 + 3) & ~@as(usize, 3);
        if (offset < 54 or offset > data.len or height > (data.len - offset) / stride) return error.InvalidBitmap;
        return .{ .data = data, .w = width, .h = height, .stride = stride, .offset = offset, .top_down = h < 0 };
    }
    pub fn pixel(self: Bitmap, x: usize, y: usize) u32 {
        const row = if (self.top_down) y else self.h - 1 - y;
        const p = self.data[self.offset + row * self.stride + x * 3 ..][0..3];
        return @as(u32, p[2]) | (@as(u32, p[1]) << 8) | (@as(u32, p[0]) << 16) | 0xff000000;
    }
};
pub fn refreshArtwork() void {
    if (!artwork_dirty.swap(false, .acq_rel)) return;
    const fd = std.posix.openatZ(std.posix.AT.FDCWD, "/tmp/art.bmp", .{ .ACCMODE = .RDONLY }, 0) catch return;
    defer _ = std.posix.system.close(fd);
    var stat: std.posix.Stat = undefined;
    if (std.posix.system.fstat(fd, &stat) != 0 or stat.size < 54 or stat.size > 64 * 1024 * 1024) return;
    const data = std.heap.page_allocator.alloc(u8, @intCast(stat.size)) catch return;
    defer std.heap.page_allocator.free(data);
    var read: usize = 0;
    while (read < data.len) {
        const n = std.posix.read(fd, data[read..]) catch return;
        if (n == 0) return;
        read += n;
    }
    const hash = std.hash.Wyhash.hash(0, data);
    if (art_hash != null and art_hash.? == hash) return;
    const bmp = Bitmap.parse(data) catch return;
    const pixels = std.heap.page_allocator.alloc(u32, bmp.w * bmp.h) catch return;
    defer std.heap.page_allocator.free(pixels);
    var sums = [_]u64{ 0, 0, 0 };
    for (0..bmp.h) |y| for (0..bmp.w) |x| {
        const p = bmp.pixel(x, y);
        pixels[y * bmp.w + x] = p;
        inline for (0..3) |c| sums[c] += (p >> (c * 8)) & 255;
    };
    native.wallify_swap_textures(@intFromEnum(Texture.artwork), @intFromEnum(Texture.previous_artwork));
    native.wallify_swap_textures(@intFromEnum(Texture.glow), @intFromEnum(Texture.previous_glow));
    upload(.artwork, pixels, bmp.w, bmp.h);
    native.wallify_blur_texture(@intFromEnum(Texture.artwork), @intFromEnum(Texture.glow), @as(f32, state.Layout.art_size_expanded));
    state.art_transition_until = if (has_art and state.setting_animations) state.animation_time + transition_duration else 0;
    has_art = true;
    art_hash = hash;
    const max_c = @max(sums[0], @max(sums[1], sums[2]));
    const boost = if (max_c > 0) @max(1.0, 160.0 * @as(f64, @floatFromInt(pixels.len)) / @as(f64, @floatFromInt(max_c))) else 1;
    state.extracted_r = @intFromFloat(@min(255, @as(f64, @floatFromInt(sums[0])) / @as(f64, @floatFromInt(pixels.len)) * boost));
    state.extracted_g = @intFromFloat(@min(255, @as(f64, @floatFromInt(sums[1])) / @as(f64, @floatFromInt(pixels.len)) * boost));
    state.extracted_b = @intFromFloat(@min(255, @as(f64, @floatFromInt(sums[2])) / @as(f64, @floatFromInt(pixels.len)) * boost));
}
test "BMP decoder handles row padding and rejects truncated data" {
    var data = [_]u8{0} ** 62;
    @memcpy(data[0..2], "BM");
    std.mem.writeInt(u32, data[10..14], 54, .little);
    std.mem.writeInt(i32, data[18..22], 1, .little);
    std.mem.writeInt(i32, data[22..26], 2, .little);
    std.mem.writeInt(u16, data[28..30], 24, .little);
    @memcpy(data[54..62], &[_]u8{ 255, 0, 0, 0, 0, 0, 255, 0 });
    const bmp = try Bitmap.parse(&data);
    try std.testing.expectEqual(@as(u32, 0xff0000ff), bmp.pixel(0, 0));
    try std.testing.expectEqual(@as(u32, 0xffff0000), bmp.pixel(0, 1));
    try std.testing.expectError(error.InvalidBitmap, Bitmap.parse(data[0..60]));
}
