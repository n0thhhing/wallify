const std = @import("std");
pub const cat_width = 541;
pub const cat_height = 52;
pub const banana_width = 98;
pub const banana_frame_height = 114;
pub const banana_frames = 45;
pub const raccoon_frame_width = 48;
pub const raccoon_height = 32;
pub const raccoon_frames = 5;
pub const raccoon_width = raccoon_frame_width * raccoon_frames;
pub const raccoon_data = @embedFile("../assets/bin/raccoon_pixels.bin");
pub const cat_data = @embedFile("../assets/bin/cat_pixels.bin");
pub const banana_data = @embedFile("../assets/bin/banana_pixels.bin");
pub const Region = struct { x: usize, y: usize = 0, w: usize, h: usize };
pub const cat_regions = [_]Region{
    .{ .x = 0, .w = 110, .h = 52 },
    .{ .x = 110, .w = 108, .h = 52 },
    .{ .x = 218, .w = 107, .h = 50 },
    .{ .x = 326, .w = 107, .h = 50 },
    .{ .x = 434, .w = 107, .h = 51 },
};
pub fn catFrame(time: f64) Region {
    return cat_regions[@as(usize, @intFromFloat(@mod(time * 3, cat_regions.len)))];
}
// Decode and premultiply once when uploading the sprite atlas.
// Using standard formats like PNG means linking bulky C libraries like stb_image.
// A custom RLE format lets us just @embedFile the raw pixels directly, keeping the binary small
// and compile times fast.
pub fn decode(data: []const u8, output: []u32) !void {
    var source: usize = 0;
    var dest: usize = 0;
    while (source < data.len and dest < output.len) {
        const header = data[source];
        source += 1;
        const count: usize = header & 127;
        const repeated = header & 128 != 0;
        const bytes = if (repeated) 4 else count * 4;
        if (count == 0 or count > output.len - dest or bytes > data.len - source) return error.InvalidSprite;
        for (0..count) |i| {
            const p = data[source + (if (repeated) 0 else i * 4) ..][0..4];
            const a: u32 = p[3];
            output[dest] = ((@as(u32, p[0]) * a + 127) / 255) | (((@as(u32, p[1]) * a + 127) / 255) << 8) | (((@as(u32, p[2]) * a + 127) / 255) << 16) | (a << 24);
            dest += 1;
        }
        source += bytes;
    }
    if (dest != output.len or source != data.len) return error.InvalidSprite;
}
test "sprite decoder rejects truncated runs and premultiplies alpha" {
    var pixels: [2]u32 = undefined;
    try decode(&.{ 130, 200, 100, 50, 128 }, &pixels);
    try std.testing.expectEqual(@as(u32, 0x80193264), pixels[0]);
    try std.testing.expectEqual(pixels[0], pixels[1]);
    try std.testing.expectError(error.InvalidSprite, decode(&.{ 130, 200 }, &pixels));
    try std.testing.expectError(error.InvalidSprite, decode(&.{ 131, 200, 100, 50, 128 }, &pixels));
}

test "embedded sprite atlases decode to their declared dimensions" {
    const cat = try std.testing.allocator.alloc(u32, cat_width * cat_height);
    defer std.testing.allocator.free(cat);
    try decode(cat_data, cat);
    const banana = try std.testing.allocator.alloc(u32, banana_width * banana_frame_height * banana_frames);
    defer std.testing.allocator.free(banana);
    try decode(banana_data, banana);
    const raccoon = try std.testing.allocator.alloc(u32, raccoon_width * raccoon_height);
    defer std.testing.allocator.free(raccoon);
    try decode(raccoon_data, raccoon);
    for (cat_regions) |region| {
        try std.testing.expect(region.x + region.w <= cat_width);
        try std.testing.expect(region.h <= cat_height);
    }
}
