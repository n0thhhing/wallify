const std = @import("std");
const state = @import("../state.zig");
const native = @import("../platform/native.zig");
const gpu = @import("canvas.zig");
const cat = @import("pets/idle_cat.zig");
const banana = @import("pets/banana_cat.zig");
const raccoon = @import("pets/idle_raccoon.zig");

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

pub const Sequence = struct {
    sprites: [45]native.DrawCommand = undefined,
    sprite_count: usize,
    sprite_period: f64,
    effects: [108 * 15]native.DrawCommand = undefined,
    effect_frames: usize,
};

// Sample the existing renderer once, rather than maintaining a second set of
// pet geometry in Objective-C. The compositor repeats these keyframes itself.
pub fn sample(style: state.IdleStyle, card: gpu.Rect, sequence: *Sequence) void {
    const is_banana = style == .banana_cat;
    sequence.sprite_count = if (is_banana) 45 else 5;
    const fps: f64 = if (is_banana) 24 else 3;
    sequence.sprite_period = @as(f64, @floatFromInt(sequence.sprite_count)) / fps;
    for (0..sequence.sprite_count) |i| {
        var canvas = gpu.Canvas{ .clip = card };
        const time = (@as(f64, @floatFromInt(i)) + 0.5) / fps;
        switch (style) {
            .pixel_cat => cat.draw(&canvas, card, time, false),
            .banana_cat => banana.draw(&canvas, card, time),
            .raccoon => raccoon.draw(&canvas, card, time, false),
            .spotify => unreachable,
        }
        sequence.sprites[i] = canvas.commands[0];
    }
    sequence.effect_frames = if (is_banana) 0 else 108;
    for (0..sequence.effect_frames) |i| {
        var canvas = gpu.Canvas{ .clip = card };
        cat.drawSleepEffects(&canvas, card, @as(f64, @floatFromInt(i)) / 30.0, false);
        std.debug.assert(canvas.count == 15);
        @memcpy(sequence.effects[i * 15 ..][0..15], canvas.commands[0..15]);
    }
}

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

    var sequence: Sequence = undefined;
    sample(state.setting_idle_style, card, &sequence);
    active = native.wallify_idle_animation(
        &sequence.sprites,
        sequence.sprite_count,
        sequence.sprite_period,
        &sequence.effects,
        sequence.effect_frames,
        15,
        3.6,
        state.cat_time,
        state.setting_speed.multiplier(),
    );
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

test "compositor keyframes cover all pet poses and preserve Metal geometry" {
    const card = gpu.Rect{ .x = 8, .y = 8, .w = 524, .h = 164, .radius = 26 };
    for ([_]state.IdleStyle{ .pixel_cat, .raccoon, .banana_cat }) |style| {
        var sequence: Sequence = undefined;
        sample(style, card, &sequence);
        try std.testing.expectEqual(@as(usize, if (style == .banana_cat) 45 else 5), sequence.sprite_count);
        for (sequence.sprites[0..sequence.sprite_count]) |c| {
            try std.testing.expectEqual(native.gpu.WALLIFY_NEAREST, c.kind);
            try std.testing.expectEqual(@as(f32, 26), c.clip_radius);
            try std.testing.expect(c.sx >= 0 and c.sy >= 0 and c.sx + c.sw <= 1.0001 and c.sy + c.sh <= 1.0001);
        }
        if (style != .banana_cat) {
            try std.testing.expectEqual(@as(usize, 108), sequence.effect_frames);
            for (0..108) |i| {
                var canvas = gpu.Canvas{ .clip = card };
                cat.drawSleepEffects(&canvas, card, @as(f64, @floatFromInt(i)) / 30, false);
                try std.testing.expectEqualSlices(u8, std.mem.sliceAsBytes(canvas.commands[0..15]), std.mem.sliceAsBytes(sequence.effects[i * 15 ..][0..15]));
            }
        } else try std.testing.expectEqual(@as(usize, 0), sequence.effect_frames);
    }
}
