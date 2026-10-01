const gpu = @import("../canvas.zig");
const pet = @import("native.zig");
pub fn draw(canvas: *gpu.Canvas, card: gpu.Rect, time: f64, petted: bool) void {
    pet.draw(0, canvas, card, time, petted);
}
pub fn drawSleepEffects(canvas: *gpu.Canvas, card: gpu.Rect, time: f64, petted: bool) void {
    pet.draw(3, canvas, card, time, petted);
}
