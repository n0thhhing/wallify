const gpu = @import("../canvas.zig");
const native = @import("../../platform/native.zig");
const sprites = @import("../sprites.zig");
const cat = @import("idle_cat.zig");

pub fn frameAt(time: f64) usize {
    const phase = @mod(time, 3.6);
    // A slow inhale, a short hold, then an exhale and a longer rest.
    for ([_]f64{ 0.9, 1.3, 2.0, 2.5 }, 0..) |end, frame| {
        if (phase < end) return frame;
    }
    return 4;
}

pub fn draw(canvas: *gpu.Canvas, card: gpu.Rect, time: f64, petted: bool) void {
    const frame: f64 = @floatFromInt(frameAt(time));
    const width = sprites.raccoon_frame_width * 3;
    const height = sprites.raccoon_height * 3;
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
