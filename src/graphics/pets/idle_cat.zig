const std = @import("std");
const PixelEngine = @import("../pixel_engine.zig").PixelEngine;

const raw_pixels = @embedFile("cat_pixels");
const image_width = @as(usize, @intFromFloat(1426.0 * 0.38));
const image_height = @as(usize, @intFromFloat(138.0 * 0.38));

var pixels: [image_width * image_height * 4]u8 = undefined;
var initialized = false;

fn initPixels() void {
    if (initialized) return;
    var byte_idx: usize = 0;
    var pixel_idx: usize = 0;
    while (byte_idx < raw_pixels.len and pixel_idx < image_width * image_height) {
        const header = raw_pixels[byte_idx];
        byte_idx += 1;
        const count = header & 0x7F;
        if ((header & 0x80) != 0) {
            const r = raw_pixels[byte_idx];
            const g = raw_pixels[byte_idx + 1];
            const b = raw_pixels[byte_idx + 2];
            const a = raw_pixels[byte_idx + 3];
            byte_idx += 4;
            for (0..count) |_| {
                pixels[pixel_idx * 4] = r;
                pixels[pixel_idx * 4 + 1] = g;
                pixels[pixel_idx * 4 + 2] = b;
                pixels[pixel_idx * 4 + 3] = a;
                pixel_idx += 1;
            }
        } else {
            for (0..count) |_| {
                pixels[pixel_idx * 4] = raw_pixels[byte_idx];
                pixels[pixel_idx * 4 + 1] = raw_pixels[byte_idx + 1];
                pixels[pixel_idx * 4 + 2] = raw_pixels[byte_idx + 2];
                pixels[pixel_idx * 4 + 3] = raw_pixels[byte_idx + 3];
                byte_idx += 4;
                pixel_idx += 1;
            }
        }
    }
    initialized = true;
}

const Sprite = struct { x: usize, y: usize, w: usize, h: usize };

const sprites = [_]Sprite{
    .{ .x = @intFromFloat(0.0 * 0.38), .y = 0, .w = @intFromFloat(291.0 * 0.38), .h = @intFromFloat(138.0 * 0.38) },
    .{ .x = @intFromFloat(291.0 * 0.38), .y = 0, .w = @intFromFloat(285.0 * 0.38), .h = @intFromFloat(138.0 * 0.38) },
    .{ .x = @intFromFloat(576.0 * 0.38), .y = 0, .w = @intFromFloat(283.0 * 0.38), .h = @intFromFloat(132.0 * 0.38) },
    .{ .x = @intFromFloat(859.0 * 0.38), .y = 0, .w = @intFromFloat(284.0 * 0.38), .h = @intFromFloat(132.0 * 0.38) },
    .{ .x = @intFromFloat(1143.0 * 0.38), .y = 0, .w = @intFromFloat(283.0 * 0.38), .h = @intFromFloat(135.0 * 0.38) },
};

pub fn draw(e: *PixelEngine, left: isize, top: isize, width: isize, time: f64, pet: bool, pointer: f64, leaving: bool) void {
    _ = pet;
    _ = pointer;
    _ = leaving;
    
    if (!initialized) initPixels();

    const fidx = @as(usize, @intFromFloat(time * 3)) % sprites.len;
    const sprite = sprites[fidx];
    
    const dw: isize = @intCast(sprite.w);
    const dh: isize = @intCast(sprite.h);

    const dx: isize = @intFromFloat(@round((@as(f64, @floatFromInt(left)) + @as(f64, @floatFromInt(width - dw)) / 2.0) * @as(f64, @floatFromInt(e.scale))));
    const dy = (top + 164 - dh - 5) * e.scale;

    var sy: isize = 0;
    while (sy < dh) : (sy += 1) {
        const src_y: usize = sprite.y + @as(usize, @intCast(sy));
        var sx: isize = 0;
        while (sx < dw) : (sx += 1) {
            const src_x: usize = sprite.x + @as(usize, @intCast(sx));
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
