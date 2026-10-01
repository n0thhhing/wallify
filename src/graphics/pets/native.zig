const gpu = @import("../canvas.zig");
const native = @import("../../platform/native.zig");
extern fn wallify_draw_pet(style: c_int, card: *const gpu.Rect, clip: *const gpu.Rect, time: f64, petted: bool, opacity: f32, output: [*]native.DrawCommand, capacity: usize) callconv(.c) usize;

pub fn draw(style: c_int, canvas: *gpu.Canvas, card: gpu.Rect, time: f64, petted: bool) void {
    canvas.count += wallify_draw_pet(style, &card, &canvas.clip, time, petted, canvas.opacity, canvas.commands[canvas.count..].ptr, canvas.commands.len - canvas.count);
}
