const std = @import("std");
const gpu = @import("../canvas.zig");
const native = @import("../../platform/native.zig");
const sprites = @import("../sprites.zig");
pub fn draw(canvas: *gpu.Canvas, card: gpu.Rect, time: f64) void {
    const sprite = sprites.catFrame(time);
    const w: f64 = @floatFromInt(sprite.w);
    const h: f64 = @floatFromInt(sprite.h);
    const c = canvas.add(native.gpu.WALLIFY_NEAREST, @intFromEnum(gpu.Texture.cat), .{ .x = card.x + (card.w - w) / 2, .y = card.y + card.h - h - 5, .w = w, .h = h }, .{ 1, 1, 1, 1 });
    c.sx = @as(f32, @floatFromInt(sprite.x)) / sprites.cat_width;
    c.sw = @as(f32, @floatFromInt(sprite.w)) / sprites.cat_width;
    c.sh = @as(f32, @floatFromInt(sprite.h)) / sprites.cat_height;
    for (0..3) |i| {
        const phase = @mod(time / 3.6 + @as(f64, @floatFromInt(i)) / 3, 1);
        const opacity = @min(1, @min(phase * 6, (1 - phase) * 4));
        const size: f64 = if (i == 2) 2 else 1;
        const x = card.x + (card.w - 110) / 2 + 20 + phase * 23;
        const y = card.y + 105 - phase * 42;
        for (0..5) |row| for (0..5) |col| {
            if (row != 0 and row != 4 and col != 4 - row) continue;
            canvas.fill(.{ .x = x + @as(f64, @floatFromInt(col)) * size, .y = y + @as(f64, @floatFromInt(row)) * size, .w = size, .h = size }, .{ 235.0 / 255.0, 219.0 / 255.0, 178.0 / 255.0, @floatCast(opacity * 210.0 / 255.0) });
        };
    }
}
