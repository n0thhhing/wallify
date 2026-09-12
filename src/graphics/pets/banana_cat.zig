const std = @import("std");
const PixelEngine = @import("../pixel_engine.zig").PixelEngine;

const FRAME_W: isize = 98;
const FRAME_H: isize = 114;
const NUM_FRAMES: usize = 45;

const raw_data = @embedFile("banana_pixels");

pub fn draw(
    e: *PixelEngine,
    left: isize,
    top: isize,
    width: isize,
    time: f64,
) void {
    const frame_idx: usize = @intFromFloat(@mod(time * 24.0, @as(f64, @floatFromInt(NUM_FRAMES))));
    const frame_offset = frame_idx * @as(usize, @intCast(FRAME_W * FRAME_H));

    // Calculate in logical coordinates
    // Shift left by 5 logical points to visually center the cat within the 98pt frame
    const dx = left + @divTrunc(width - FRAME_W, 2) - 6;
    const dy = top + @divTrunc(164 - FRAME_H, 2);

    var sy: isize = 0;
    while (sy < FRAME_H) : (sy += 1) {
        var sx: isize = 0;
        while (sx < FRAME_W) : (sx += 1) {
            const pixel_idx = frame_offset + @as(usize, @intCast(sy * FRAME_W + sx));
            const color_idx = pixel_idx * 4;

            const r: u8 = raw_data[color_idx];
            const g: u8 = raw_data[color_idx + 1];
            const b: u8 = raw_data[color_idx + 2];
            const a: u8 = raw_data[color_idx + 3];

            if (a > 0) {
                // Scale logical points to physical pixels
                var v: isize = 0;
                while (v < e.scale) : (v += 1) {
                    var u: isize = 0;
                    while (u < e.scale) : (u += 1) {
                        e.blendPixel((dx + sx) * e.scale + u, (dy + sy) * e.scale + v, r, g, b, a);
                    }
                }
            }
        }
    }
}
