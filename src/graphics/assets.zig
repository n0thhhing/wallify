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

pub fn clearArtwork() void {
    has_art = false;
    art_hash = null;
}

pub fn refreshArtwork() void {
    if (!artwork_dirty.swap(false, .acq_rel)) return;

    // Use CoreGraphics to decode the raw JPEG/PNG directly in memory.
    // This entirely eliminates the ~100ms stutter of spawning `sips` via posix fork/exec
    // in the background, and saves us from shipping libjpeg/libpng.
    const macos = @import("../platform/macos.zig");
    const path = "/tmp/art.raw";

    // Quick hash check on the raw file to avoid unnecessary CoreGraphics work
    const fd = std.posix.openatZ(std.posix.AT.FDCWD, path, .{ .ACCMODE = .RDONLY }, 0) catch {
        clearArtwork();
        state.global_has_artwork = false;
        return;
    };

    var stat: std.posix.Stat = undefined;
    if (std.posix.system.fstat(fd, &stat) != 0 or stat.size == 0 or stat.size > 64 * 1024 * 1024) {
        _ = std.posix.system.close(fd);
        clearArtwork();
        state.global_has_artwork = false;
        return;
    }

    _ = std.posix.system.close(fd);

    const mtime_hash = @as(u64, @bitCast(stat.mtime().sec)) ^ @as(u64, @bitCast(stat.mtime().nsec));
    if (art_hash != null and art_hash.? == mtime_hash) return;
    const hash = mtime_hash;

    const url = macos.CFURLCreateFromFileSystemRepresentation(null, path, path.len, 0);
    if (url == null) {
        clearArtwork();
        state.global_has_artwork = false;
        return;
    }
    defer macos.CFRelease(url);

    const src = macos.CGImageSourceCreateWithURL(url, null);
    if (src == null) {
        clearArtwork();
        state.global_has_artwork = false;
        return;
    }
    defer macos.CFRelease(src);

    const max_size: i32 = 180;
    const size_num = macos.CFNumberCreate(null, 3, &max_size);
    defer macos.CFRelease(size_num);

    const keys = [_]macos.Ref{ macos.kCGImageSourceCreateThumbnailFromImageAlways, macos.kCGImageSourceThumbnailMaxPixelSize };
    const values = [_]macos.Ref{ macos.kCFBooleanTrue, size_num };
    const options = macos.CFDictionaryCreate(null, &keys, &values, 2, &macos.kCFTypeDictionaryKeyCallBacks, &macos.kCFTypeDictionaryValueCallBacks);
    defer macos.CFRelease(options);

    const img = macos.CGImageSourceCreateThumbnailAtIndex(src, 0, options);
    if (img == null) {
        clearArtwork();
        state.global_has_artwork = false;
        return;
    }
    defer macos.CGImageRelease(img);

    const w = 180;
    const h = 180;
    const pixels = std.heap.page_allocator.alloc(u32, w * h) catch {
        clearArtwork();
        state.global_has_artwork = false;
        return;
    };
    defer std.heap.page_allocator.free(pixels);
    @memset(pixels, 0);

    const space = macos.CGColorSpaceCreateDeviceRGB();
    defer macos.CGColorSpaceRelease(space);

    const ctx = macos.CGBitmapContextCreate(@ptrCast(pixels.ptr), w, h, 8, w * 4, space, macos.kCGImageAlphaPremultipliedLast | macos.kCGBitmapByteOrder32Big);
    if (ctx == null) {
        clearArtwork();
        state.global_has_artwork = false;
        return;
    }
    defer macos.CGContextRelease(ctx);

    macos.CGContextDrawImage(ctx, macos.rect(0, 0, w, h), img);

    var sums = [_]u64{ 0, 0, 0 };
    for (0..h) |y| for (0..w) |x| {
        const p = pixels[y * w + x];
        inline for (0..3) |c| sums[c] += (p >> (c * 8)) & 255;
    };

    native.wallify_swap_textures(@intFromEnum(Texture.artwork), @intFromEnum(Texture.previous_artwork));
    native.wallify_swap_textures(@intFromEnum(Texture.glow), @intFromEnum(Texture.previous_glow));
    upload(.artwork, pixels, w, h);
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
