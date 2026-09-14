const std = @import("std");
const PixelEngine = @import("../pixel_engine.zig").PixelEngine;

const FRAME_W: isize = 98;
const FRAME_H: isize = 114;
const NUM_FRAMES: usize = 45;

const raw_data = @embedFile("banana_pixels");

var frame_offsets: [NUM_FRAMES]usize = undefined;
var initialized = false;

fn initOffsets() void {
    if (initialized) return;
    var byte_idx: usize = 0;
    var pixel_idx: usize = 0;
    var frame: usize = 0;
    while (byte_idx < raw_data.len) {
        if (pixel_idx % (FRAME_W * FRAME_H) == 0) {
            frame_offsets[frame] = byte_idx;
            frame += 1;
            if (frame == NUM_FRAMES) break;
        }
        const header = raw_data[byte_idx];
        byte_idx += 1;
        const count = header & 0x7F;
        if ((header & 0x80) != 0) {
            byte_idx += 4;
            pixel_idx += count;
        } else {
            byte_idx += @as(usize, count) * 4;
            pixel_idx += count;
        }
    }
    initialized = true;
}

pub fn draw(
    e: *PixelEngine,
    left: isize,
    top: isize,
    width: isize,
    time: f64,
) void {
    if (!initialized) initOffsets();

    const frame_idx: usize = @intFromFloat(@mod(time * 24.0, @as(f64, @floatFromInt(NUM_FRAMES))));
    var byte_idx: usize = frame_offsets[frame_idx];

    const dx = left + @divTrunc(width - FRAME_W, 2) - 6;
    const dy = top + @divTrunc(164 - FRAME_H, 2);

    var pixel_in_frame: usize = 0;
    const total_pixels_in_frame = FRAME_W * FRAME_H;
    
    while (pixel_in_frame < total_pixels_in_frame and byte_idx < raw_data.len) {
        const header = raw_data[byte_idx];
        byte_idx += 1;
        const count = header & 0x7F;
        
        if ((header & 0x80) != 0) {
            const r = raw_data[byte_idx];
            const g = raw_data[byte_idx+1];
            const b = raw_data[byte_idx+2];
            const a = raw_data[byte_idx+3];
            byte_idx += 4;
            
            if (a > 0) {
                var c: usize = 0;
                while (c < count) : (c += 1) {
                    const sx = @as(isize, @intCast((pixel_in_frame + c) % @as(usize, @intCast(FRAME_W))));
                    const sy = @as(isize, @intCast((pixel_in_frame + c) / @as(usize, @intCast(FRAME_W))));
                    var v: isize = 0;
                    while (v < e.scale) : (v += 1) {
                        var u: isize = 0;
                        while (u < e.scale) : (u += 1) {
                            e.blendPixel((dx + sx) * e.scale + u, (dy + sy) * e.scale + v, r, g, b, a);
                        }
                    }
                }
            }
            pixel_in_frame += count;
        } else {
            var c: usize = 0;
            while (c < count) : (c += 1) {
                const a = raw_data[byte_idx + 3];
                if (a > 0) {
                    const r = raw_data[byte_idx];
                    const g = raw_data[byte_idx + 1];
                    const b = raw_data[byte_idx + 2];
                    const sx = @as(isize, @intCast((pixel_in_frame + c) % @as(usize, @intCast(FRAME_W))));
                    const sy = @as(isize, @intCast((pixel_in_frame + c) / @as(usize, @intCast(FRAME_W))));
                    var v: isize = 0;
                    while (v < e.scale) : (v += 1) {
                        var u: isize = 0;
                        while (u < e.scale) : (u += 1) {
                            e.blendPixel((dx + sx) * e.scale + u, (dy + sy) * e.scale + v, r, g, b, a);
                        }
                    }
                }
                byte_idx += 4;
            }
            pixel_in_frame += count;
        }
    }
}
