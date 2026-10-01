const gpu = @import("../canvas.zig");
pub fn draw(canvas: *gpu.Canvas, card: gpu.Rect, time: f64) void {
    @import("native.zig").draw(1, canvas, card, time, false);
}
