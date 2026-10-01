const gpu = @import("../canvas.zig");
extern fn wallify_raccoon_frame(time: f64) callconv(.c) usize;
pub fn frameAt(time: f64) usize {
    return wallify_raccoon_frame(time);
}
pub fn draw(canvas: *gpu.Canvas, card: gpu.Rect, time: f64, petted: bool) void {
    @import("native.zig").draw(2, canvas, card, time, petted);
}
