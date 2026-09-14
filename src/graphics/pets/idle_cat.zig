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
                pixels[pixel_idx * 4] = b;
                pixels[pixel_idx * 4 + 1] = g;
                pixels[pixel_idx * 4 + 2] = r;
                pixels[pixel_idx * 4 + 3] = a;
                pixel_idx += 1;
            }
        } else {
            for (0..count) |_| {
                pixels[pixel_idx * 4] = raw_pixels[byte_idx + 2];
                pixels[pixel_idx * 4 + 1] = raw_pixels[byte_idx + 1];
                pixels[pixel_idx * 4 + 2] = raw_pixels[byte_idx];
                pixels[pixel_idx * 4 + 3] = raw_pixels[byte_idx + 3];
                byte_idx += 4;
                pixel_idx += 1;
            }
        }
    }
    initialized = true;
    var u32_pixels = std.heap.page_allocator.alloc(u32, image_width * image_height) catch return;
    defer std.heap.page_allocator.free(u32_pixels);
    @memcpy(std.mem.sliceAsBytes(u32_pixels[0..]), pixels[0..]);
    @import("../../platform/native.zig").wallify_load_texture(3, u32_pixels.ptr, image_width, image_height);
}

const Sprite = struct { x: usize, y: usize, w: usize, h: usize };

const sprites = [_]Sprite{
    .{ .x = @intFromFloat(0.0 * 0.38), .y = 0, .w = @intFromFloat(291.0 * 0.38), .h = @intFromFloat(138.0 * 0.38) },
    .{ .x = @intFromFloat(291.0 * 0.38), .y = 0, .w = @intFromFloat(285.0 * 0.38), .h = @intFromFloat(138.0 * 0.38) },
    .{ .x = @intFromFloat(576.0 * 0.38), .y = 0, .w = @intFromFloat(283.0 * 0.38), .h = @intFromFloat(132.0 * 0.38) },
    .{ .x = @intFromFloat(859.0 * 0.38), .y = 0, .w = @intFromFloat(284.0 * 0.38), .h = @intFromFloat(132.0 * 0.38) },
    .{ .x = @intFromFloat(1143.0 * 0.38), .y = 0, .w = @intFromFloat(283.0 * 0.38), .h = @intFromFloat(135.0 * 0.38) },
};

pub fn draw(e: *PixelEngine, left: isize, top: isize, width: isize, time: f64, pet: bool, pointer: f64, leaving: bool, commands: []@import("../../platform/native.zig").DrawCommand, cmd_count: *usize) void {
    _ = pet;
    _ = pointer;
    _ = leaving;
    
    if (!initialized) initPixels();

    const fidx = @as(usize, @intFromFloat(time * 3)) % sprites.len;
    const sprite = sprites[fidx];
    
    const dw: isize = @intCast(sprite.w);
    const dh: isize = @intCast(sprite.h);


    const draw_x = left + @divTrunc(width - dw, 2);
    const draw_y = top + 164 - dh - 5;

    if (cmd_count.* < commands.len) {
        const scale = @as(isize, @intCast(@import("../../state.zig").render_scale));
        commands[cmd_count.*] = .{
            .texture_id = 3,
            .dx = @as(f32, @floatFromInt(draw_x * scale)),
            .dy = @as(f32, @floatFromInt(draw_y * scale)),
            .dw = @as(f32, @floatFromInt(dw * scale)),
            .dh = @as(f32, @floatFromInt(dh * scale)),
            .sx = @as(f32, @floatFromInt(sprite.x)) / @as(f32, @floatFromInt(image_width)),
            .sy = @as(f32, @floatFromInt(sprite.y)) / @as(f32, @floatFromInt(image_height)),
            .sw = @as(f32, @floatFromInt(sprite.w)) / @as(f32, @floatFromInt(image_width)),
            .sh = @as(f32, @floatFromInt(sprite.h)) / @as(f32, @floatFromInt(image_height)),
            .alpha = 1.0,
        };
        cmd_count.* += 1;
    }
    // Anchor the Z marks to the cat's head: roughly upper-right area of the sprite.
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
