const std = @import("std");
const state = @import("../state.zig");
const native = @import("../platform/native.zig");
const gpu = @import("canvas.zig");
extern fn wallify_start_pet_animation(style: c_int, card: *const gpu.Rect, phase: f64, speed: f64) callconv(.c) bool;

pub var active = false;
var previous_card: gpu.Rect = undefined;
var previous_style: state.IdleStyle = .spotify;
var previous_speed: state.AnimationSpeed = .normal;

pub fn elapsedAnimationTime(seconds: f64) f64 {
    return @max(0, seconds) * previous_speed.multiplier();
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

pub fn update(card: gpu.Rect) void {
    const conditions = Conditions{
        .idle_mix = state.idle_mix,
        .animations = state.setting_animations,
        .style = state.setting_idle_style,
        .resizing = state.mode_transition_active,
        .snapping = state.panel_snap_active,
        .dragging = state.global_panel_dragging,
        .petted = state.animation_time < state.cat_pet_until,
    };
    if (!conditions.eligible()) {
        if (active) native.wallify_idle_animation_stop();
        active = false;
        return;
    }
    if (active and std.meta.eql(previous_card, card) and
        previous_style == state.setting_idle_style and previous_speed == state.setting_speed) return;

    const style: c_int = switch (state.setting_idle_style) {
        .pixel_cat => 0,
        .banana_cat => 1,
        .raccoon => 2,
        .spotify => unreachable,
    };
    active = wallify_start_pet_animation(style, &card, state.cat_time, state.setting_speed.multiplier());
    if (active) {
        previous_card = card;
        previous_style = state.setting_idle_style;
        previous_speed = state.setting_speed;
    }
}

test "compositor yields to disabled animations, launcher, and interactive transitions" {
    try std.testing.expect((Conditions{}).eligible());
    for ([_]Conditions{
        .{ .idle_mix = 0.99 }, .{ .animations = false }, .{ .style = .spotify },
        .{ .resizing = true }, .{ .snapping = true },    .{ .dragging = true },
        .{ .petted = true },
    }) |conditions| try std.testing.expect(!conditions.eligible());
}
