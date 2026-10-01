const std = @import("std");
const state = @import("../state.zig");
extern fn wallify_idle_compositor_active() callconv(.c) bool;
extern fn wallify_idle_compositor_elapsed(seconds: f64) callconv(.c) f64;
pub fn isActive() bool {
    return wallify_idle_compositor_active();
}
pub fn elapsedAnimationTime(seconds: f64) f64 {
    return wallify_idle_compositor_elapsed(seconds);
}
const Conditions = struct {
    idle_mix: f64 = 1,
    animations: bool = true,
    style: state.IdleStyle = .raccoon,
    resizing: bool = false,
    snapping: bool = false,
    dragging: bool = false,
    petted: bool = false,

    fn eligible(self: Conditions) bool {
        return self.idle_mix == 1 and self.animations and self.style != .spotify and
            !self.resizing and !self.snapping and !self.dragging and !self.petted;
    }
};

test "compositor yields to disabled animations, launcher, and interactive transitions" {
    try std.testing.expect((Conditions{}).eligible());
    for ([_]Conditions{
        .{ .idle_mix = 0.99 }, .{ .animations = false }, .{ .style = .spotify },
        .{ .resizing = true }, .{ .snapping = true },    .{ .dragging = true },
        .{ .petted = true },
    }) |conditions| try std.testing.expect(!conditions.eligible());
}
