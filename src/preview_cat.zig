// Offline asset contact sheet. This does not link the app or GPU renderer.
const std = @import("std");
const sprites = @import("graphics/sprites.zig");
pub fn main() !void {
    const scale = 3;
    const tile = 164;
    const width = sprites.cat_regions.len * tile * scale;
    const height = tile * scale;
    const sheet = try std.heap.page_allocator.alloc(u32, width * height);
    defer std.heap.page_allocator.free(sheet);
    @memset(sheet, 0xff1e1b1e);
    const atlas = try std.heap.page_allocator.alloc(u32, sprites.cat_width * sprites.cat_height);
    defer std.heap.page_allocator.free(atlas);
    try sprites.decode(sprites.cat_data, atlas);
    for (sprites.cat_regions, 0..) |region, index| {
        const left = (index * tile + (tile - region.w) / 2) * scale;
        const top = (tile - region.h - 5) * scale;
        for (0..region.h * scale) |y| for (0..region.w * scale) |x| {
            const pixel = atlas[(y / scale) * sprites.cat_width + region.x + x / scale];
            const alpha = pixel >> 24;
            const dest = &sheet[(top + y) * width + left + x];
            var blended: u32 = 0xff000000;
            inline for (0..3) |c| {
                const shift = c * 8;
                blended |= @as(u32, @min(255, ((pixel >> shift) & 255) + ((dest.* >> shift) & 255) * (255 - alpha) / 255)) << shift;
            }
            dest.* = blended;
        };
    }
    const output = try std.heap.page_allocator.alloc(u8, width * height * 3 + 64);
    defer std.heap.page_allocator.free(output);
    const header = try std.fmt.bufPrint(output, "P6\n{d} {d}\n255\n", .{ width, height });
    for (sheet, 0..) |p, i| {
        output[header.len + i * 3] = @truncate(p);
        output[header.len + i * 3 + 1] = @truncate(p >> 8);
        output[header.len + i * 3 + 2] = @truncate(p >> 16);
    }
    const fd = try std.posix.openatZ(std.posix.AT.FDCWD, "/tmp/wallify-poses.ppm", .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true }, 0o644);
    defer _ = std.posix.system.close(fd);
    var sent: usize = 0;
    const length = header.len + sheet.len * 3;
    while (sent < length) {
        const written = std.posix.system.write(fd, output.ptr + sent, length - sent);
        if (written <= 0) return error.WriteFailed;
        sent += @intCast(written);
    }
}
