const std = @import("std");
const gpu = @import("../canvas.zig");
const native = @import("../../platform/native.zig");
const sprites = @import("../sprites.zig");

pub fn draw(canvas: *gpu.Canvas, card: gpu.Rect, time: f64, petted: bool) void {
    const sprite = sprites.catFrame(time);
    const w: f64 = @floatFromInt(sprite.w);
    const h: f64 = @floatFromInt(sprite.h);

    const c = canvas.add(native.gpu.WALLIFY_NEAREST, @intFromEnum(gpu.Texture.cat), .{
        .x = card.x + (card.w - w) / 2,
        .y = card.y + card.h - h - 5,
        .w = w,
        .h = h,
    }, .{ 1, 1, 1, 1 });
    c.sx = @as(f32, @floatFromInt(sprite.x)) / sprites.cat_width;
    c.sw = @as(f32, @floatFromInt(sprite.w)) / sprites.cat_width;
    c.sh = @as(f32, @floatFromInt(sprite.h)) / sprites.cat_height;

    drawSleepEffects(canvas, card, time, petted);
}

pub fn drawSleepEffects(canvas: *gpu.Canvas, card: gpu.Rect, time: f64, petted: bool) void {
    // Floating sleep Z's (or floating pink hearts when petted!)
    const z_color = [4]f32{ 235.0 / 255.0, 219.0 / 255.0, 178.0 / 255.0, 210.0 / 255.0 };
    const heart_color = [4]f32{ 211.0 / 255.0, 134.0 / 255.0, 155.0 / 255.0, 235.0 / 255.0 };
    const color = if (petted) heart_color else z_color;

    for (0..3) |i| {
        const phase = @mod(time / 3.6 + @as(f64, @floatFromInt(i)) / 3.0, 1.0);
        const opacity = @min(1.0, @min(phase * 6.0, (1.0 - phase) * 4.0));
        const size: f64 = if (i == 2) 2.0 else 1.0;
        // Pixel-snap coordinates to prevent sub-pixel raster jitter / flickering
        const x = @floor(card.x + (card.w - 110.0) / 2.0 + 20.0 + phase * 23.0);
        const y = @floor(card.y + 105.0 - phase * 42.0);

        for (0..5) |row| for (0..5) |col| {
            const draw_pixel = if (petted)
                (row == 0 and (col == 1 or col == 3)) or
                    (row == 1 and col >= 0 and col <= 4) or
                    (row == 2 and col >= 0 and col <= 4) or
                    (row == 3 and col >= 1 and col <= 3) or
                    (row == 4 and col == 2)
            else
                (row == 0 or row == 4 or col == 4 - row);
            if (!draw_pixel) continue;

            canvas.fill(.{
                .x = x + @as(f64, @floatFromInt(col)) * size,
                .y = y + @as(f64, @floatFromInt(row)) * size,
                .w = size,
                .h = size,
            }, .{ color[0], color[1], color[2], @floatCast(opacity * color[3]) });
        };
    }
}
