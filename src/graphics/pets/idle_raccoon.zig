const gpu = @import("../canvas.zig");
const native = @import("../../platform/native.zig");
const sprites = @import("../sprites.zig");
const cat = @import("idle_cat.zig");

pub fn frameAt(time: f64) usize {
    // Match the Pixel Cat's five poses at three frames per second.
    return @intFromFloat(@mod(time * 3, sprites.raccoon_frames));
}

pub fn draw(canvas: *gpu.Canvas, card: gpu.Rect, time: f64, petted: bool) void {
    const frame: f64 = @floatFromInt(frameAt(time));
    const width = sprites.raccoon_frame_width;
    const height = sprites.raccoon_height;
    const c = canvas.add(native.gpu.WALLIFY_NEAREST, @intFromEnum(gpu.Texture.raccoon), .{
        .x = @floor(card.x + (card.w - width) / 2),
        .y = @floor(card.y + card.h - height - 5),
        .w = width,
        .h = height,
    }, .{ 1, 1, 1, 1 });
    c.sx = @floatCast(frame / sprites.raccoon_frames);
    c.sw = 1.0 / @as(f32, sprites.raccoon_frames);
    cat.drawSleepEffects(canvas, card, time, petted);
}
