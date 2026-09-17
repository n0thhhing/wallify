const std = @import("std");
const state = @import("../state.zig");
const native = @import("../platform/native.zig");
const gpu = @import("canvas.zig");
const assets = @import("assets.zig");
const window = @import("../ui/window.zig");
const idle = @import("render/idle.zig");
const player = @import("render/player.zig");

pub const idle_renderer = idle;
pub const player_renderer = player;

// When native glass is active, drop opacity so the NSVisualEffectView blur shines through
inline fn cardBackgroundColor() gpu.Color {
    return if (state.setting_native_glass)
        .{ 28.0 / 255.0, 28.0 / 255.0, 30.0 / 255.0, 0.0 }
    else
        .{ 28.0 / 255.0, 28.0 / 255.0, 30.0 / 255.0, 1.0 };
}

// Metadata updates invalidate the artwork cache; rendering never polls the file.
pub fn extractColor() void {
    assets.artwork_dirty.store(true, .release);
}

pub fn clearArtwork() void {
    assets.clearArtwork();
    assets.artwork_dirty.store(false, .release);
}

pub fn drawUIFrame() void {
    const started = window.widget_monotonic_time();
    defer native.wallify_profile_scene(window.widget_monotonic_time() - started);

    window.widget_render_lock();
    defer window.widget_render_unlock();

    assets.init() catch |err| {
        std.log.err("GPU assets: {s}", .{@errorName(err)});
        return;
    };
    assets.refreshArtwork();

    state.layout.update(
        @floatFromInt(native.wallify_width()),
        @floatFromInt(native.wallify_height()),
        state.mode_mix,
    );

    const card = state.layout.card(state.mode_mix);
    var canvas = gpu.Canvas{ .clip = card };

    // Frosted acrylic glass shell with GPU specular bevel and subtle artwork ambient diffusion
    const ambient_intensity: f32 = if (state.global_has_artwork and assets.has_art and state.setting_glow) 0.12 else 0.0;
    native.wallify_update_glass_rect(card.x, card.y, card.w, card.h, card.radius, state.setting_native_glass);
    canvas.glass(
        card,
        cardBackgroundColor(),
        @as(f32, @floatFromInt(state.extracted_r)) / 255.0,
        @as(f32, @floatFromInt(state.extracted_g)) / 255.0,
        @as(f32, @floatFromInt(state.extracted_b)) / 255.0,
        ambient_intensity,
    );

    // Dynamic fluid Aurora wave layer (Apple Music style)
    if (state.aurora_mix > 0.001 and state.global_has_artwork and assets.has_art) {
        const pri = [3]f32{
            @as(f32, @floatFromInt(state.extracted_r)) / 255.0,
            @as(f32, @floatFromInt(state.extracted_g)) / 255.0,
            @as(f32, @floatFromInt(state.extracted_b)) / 255.0,
        };
        const dim_factor: f32 = if (state.setting_dim and state.global_rate == 0) 0.65 else 1.0;
        const alpha: f32 = @floatCast(0.32 * state.aurora_mix * (1.0 - state.idle_mix) * dim_factor);
        canvas.aurora(card, pri, pri, @floatCast(state.animation_time), alpha);
    }

    // Active media player or idle view
    if (state.idle_mix < 1.0) player.drawPlayer(&canvas, card);
    if (state.idle_mix > 0.0) idle.drawIdle(&canvas, card);

    // Optional border frame outline
    canvas.opacity = 1.0;
    const frame_strength = state.setting_frame.multiplier();
    if (frame_strength > 0.0) {
        canvas.stroke(card, 0.8, .{ 1.0, 1.0, 1.0, @floatCast(0.12 * frame_strength) });
    }

    canvas.submit(state.layout.width, state.layout.height);
}
