const std = @import("std");
const gpu = @import("../canvas.zig");
const native = @import("../../platform/native.zig");
const sprites = @import("../sprites.zig");

const Strip = struct { x: u8, y: u8, width: u8 };
const sleep_strips = [_]Strip{
    .{ .x = 0, .y = 0, .width = 5 },
    .{ .x = 3, .y = 1, .width = 1 },
    .{ .x = 2, .y = 2, .width = 1 },
    .{ .x = 1, .y = 3, .width = 1 },
    .{ .x = 0, .y = 4, .width = 5 },
};
const heart_strips = [_]Strip{
    .{ .x = 1, .y = 0, .width = 1 },
    .{ .x = 3, .y = 0, .width = 1 },
    .{ .x = 0, .y = 1, .width = 5 },
    .{ .x = 0, .y = 2, .width = 5 },
    .{ .x = 1, .y = 3, .width = 3 },
    .{ .x = 2, .y = 4, .width = 1 },
};

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

        // Adjacent pixels share color and opacity, so submit one strip per run.
        const strips: []const Strip = if (petted) &heart_strips else &sleep_strips;
        for (strips) |strip| {
            canvas.fill(.{
                .x = x + @as(f64, @floatFromInt(strip.x)) * size,
                .y = y + @as(f64, @floatFromInt(strip.y)) * size,
                .w = @as(f64, @floatFromInt(strip.width)) * size,
                .h = size,
            }, .{ color[0], color[1], color[2], @floatCast(opacity * color[3]) });
        }
    }
}

test "effect strips preserve every glyph pixel without overlap" {
    const masks = [_][5][]const u8{
        .{ "11111", "00010", "00100", "01000", "11111" },
        .{ "01010", "11111", "11111", "01110", "00100" },
    };
    for ([_][]const Strip{ &sleep_strips, &heart_strips }, masks) |strips, mask| {
        var coverage = [_][5]u8{.{0} ** 5} ** 5;
        for (strips) |strip| {
            for (strip.x..strip.x + strip.width) |x| coverage[strip.y][x] += 1;
        }
        for (mask, 0..) |row, y| {
            for (row, 0..) |pixel, x| try std.testing.expectEqual(pixel - '0', coverage[y][x]);
        }
    }
}
