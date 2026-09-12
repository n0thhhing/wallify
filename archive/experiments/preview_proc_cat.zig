const std = @import("std");
const cat = @import("graphics/proc_cat.zig");
const Engine = @import("graphics/pixel_engine.zig").PixelEngine;
fn save(path: [*:0]const u8, data: []const u8) !void {
    const fd = try std.posix.openatZ(std.posix.AT.FDCWD, path, .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true }, 0o644);
    defer _ = std.posix.system.close(fd);
    var offset: usize = 0;
    while (offset < data.len) {
        const n = std.posix.system.write(fd, data.ptr + offset, data.len - offset);
        if (n <= 0) return error.WriteFailed;
        offset += @intCast(n);
    }
}
pub fn main() !void {
    var e = try Engine.init(std.heap.page_allocator, 164, 200);
    defer e.deinit(std.heap.page_allocator);
    const N = 864;
    const frame_px = 164 * 200;
    const movie = try std.heap.page_allocator.alloc(u8, N * frame_px * 4);
    defer std.heap.page_allocator.free(movie);
    for (0..N) |i| {
        @memset(e.pixels, 0xff282828);
        const time = @as(f64, @floatFromInt(i)) / 24.0;
        const pointer: f64 = if (time < 12) 0 else 164;
        cat.draw(&e, 0, 35, 164, time, false, pointer, false);
        const fb = std.mem.sliceAsBytes(e.pixels);
        @memcpy(movie[i * fb.len ..][0..fb.len], fb);
    }
    try save("/tmp/proc-cat.rgba", movie);
    std.debug.print("done\n", .{});
}
