const std = @import("std");
const PixelEngine = @import("../pixel_engine.zig").PixelEngine;

const pixels = @embedFile("cat_pixels");
const image_width = 1426;

const Sprite = struct { x: usize, y: usize, w: usize, h: usize };

const sprites = [_]Sprite{
    .{ .x = 0, .y = 0, .w = 291, .h = 138 },
    .{ .x = 291, .y = 0, .w = 285, .h = 138 },
    .{ .x = 576, .y = 0, .w = 283, .h = 132 },
    .{ .x = 859, .y = 0, .w = 284, .h = 132 },
    .{ .x = 1143, .y = 0, .w = 283, .h = 135 },
};

pub fn draw(e: *PixelEngine, left: isize, top: isize, width: isize, time: f64, pet: bool, pointer: f64, leaving: bool) void {
    _ = pet;
    _ = pointer;
    _ = leaving;

    // Cycle through every sleeping frame at three frames per second.
    const fidx = @as(usize, @intFromFloat(time * 3)) % sprites.len;

    const sprite = sprites[fidx];
    const scale = 0.38;
    const dw: isize = @intFromFloat(@as(f64, @floatFromInt(sprite.w)) * scale);
    const dh: isize = @intFromFloat(@as(f64, @floatFromInt(sprite.h)) * scale);

    const dx: isize = @intFromFloat(@round((@as(f64, @floatFromInt(left)) + @as(f64, @floatFromInt(width - dw)) / 2.0) * @as(f64, @floatFromInt(e.scale))));
    // Anchor to bottom (164 logical px tall tile)
    const dy = (top + 164 - dh - 5) * e.scale;

    var sy: isize = 0;
    while (sy < dh) : (sy += 1) {
        const src_y: usize = @intCast(@as(isize, @intCast(sprite.y)) + @as(isize, @intFromFloat(@as(f64, @floatFromInt(sy)) / scale)));
        var sx: isize = 0;
        while (sx < dw) : (sx += 1) {
            const src_x_logical = sx;
            const src_x: usize = @intCast(@as(isize, @intCast(sprite.x)) + @as(isize, @intFromFloat(@as(f64, @floatFromInt(src_x_logical)) / scale)));
            const i = (src_y * image_width + src_x) * 4;
            const a = pixels[i + 3];
            if (a < 64) continue;
            var v: isize = 0;
            while (v < e.scale) : (v += 1) {
                var u: isize = 0;
                while (u < e.scale) : (u += 1) {
                    e.blendPixel(dx + sx * e.scale + u, dy + sy * e.scale + v, pixels[i], pixels[i + 1], pixels[i + 2], a);
                }
            }
        }
    }
    drawSleepMarks(e, left + @divTrunc(width - 110, 2) + 20, top + 105, time);
}

fn drawSleepMarks(e: *PixelEngine, head_x: isize, head_y: isize, time: f64) void {
    // Stagger three pixel-letter Zs, gently rising and fading above the head.
    for (0..3) |index| {
        const phase = @mod(time / 3.6 + @as(f64, @floatFromInt(index)) / 3.0, 1.0);
        const opacity = @min(1.0, @min(phase * 6.0, (1.0 - phase) * 4.0));
        const alpha: u8 = @intFromFloat(opacity * 210.0);
        const size: isize = if (index == 2) 2 else 1;
        const x = head_x + @as(isize, @intFromFloat(phase * 23.0));
        const y = head_y - @as(isize, @intFromFloat(phase * 42.0));
        for (0..5) |row| {
            for (0..5) |column| {
                if (row != 0 and row != 4 and column != 4 - row) continue;
                var py: isize = 0;
                while (py < size * e.scale) : (py += 1) {
                    var px: isize = 0;
                    while (px < size * e.scale) : (px += 1) {
                        e.blendPixel(
                            (x + @as(isize, @intCast(column)) * size) * e.scale + px,
                            (y + @as(isize, @intCast(row)) * size) * e.scale + py,
                            235,
                            219,
                            178,
                            alpha,
                        );
                    }
                }
            }
        }
    }
}
