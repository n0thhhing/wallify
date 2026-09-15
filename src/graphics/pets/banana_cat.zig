const gpu = @import("../canvas.zig");
const native = @import("../../platform/native.zig");
const sprites = @import("../sprites.zig");
pub fn draw(canvas: *gpu.Canvas, card: gpu.Rect, time: f64) void {
    const frame = @floor(@mod(time * 24, sprites.banana_frames));
    const c = canvas.add(native.gpu.WALLIFY_NEAREST, @intFromEnum(gpu.Texture.banana), .{ .x = card.x + (card.w - sprites.banana_width) / 2 - 6, .y = card.y + (card.h - sprites.banana_frame_height) / 2, .w = sprites.banana_width, .h = sprites.banana_frame_height }, .{ 1, 1, 1, 1 });
    c.sy = @floatCast(frame / sprites.banana_frames);
    c.sh = 1.0 / @as(f32, sprites.banana_frames);
}
