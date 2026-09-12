const std = @import("std");
const Cat = @import("graphics/pets/idle_cat.zig");
const Engine = @import("graphics/pixel_engine.zig").PixelEngine;

pub fn main() !void {
    const width = 5 * 164 * 3;
    const height = 164 * 3;
    var engine = try Engine.init(std.heap.page_allocator, width, height);
    defer engine.deinit(std.heap.page_allocator);
    engine.scale = 3;
    @memset(engine.pixels, 0xff1e1b1e);
    for ([_]f64{ 0, 0.34, 0.67, 1.0, 1.34 }, 0..) |time, index| {
        Cat.draw(&engine, @as(isize, @intCast(index)) * 164, 0, 164, time, false, 90, false);
    }
    const fd = try std.posix.openatZ(std.posix.AT.FDCWD, "/tmp/wallify-poses.ppm", .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true }, 0o644);
    defer _ = std.posix.system.close(fd);
    var header: [64]u8 = undefined;
    const formatted = try std.fmt.bufPrint(&header, "P6\n{d} {d}\n255\n", .{ width, height });
    _ = std.posix.system.write(fd, formatted.ptr, formatted.len);
    for (engine.pixels) |pixel| {
        const rgb = [3]u8{ @truncate(pixel), @truncate(pixel >> 8), @truncate(pixel >> 16) };
        _ = std.posix.system.write(fd, &rgb, 3);
    }
    std.debug.print("Generated /tmp/wallify-poses.ppm\n", .{});
}
