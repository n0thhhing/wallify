const std = @import("std");
const state = @import("../../state.zig");
const native = @import("../../platform/native.zig");
const gpu = @import("../canvas.zig");
const assets = @import("../assets.zig");
const window = @import("../../ui/window.zig");
const icon_transition = @import("../icon_transition.zig");
const labels = @import("labels.zig");

pub fn drawPlayer(canvas: *gpu.Canvas, card: gpu.Rect) void {
    const elapsed = if (state.global_rate == 0.0 or state.global_is_dragging)
        state.global_elapsed
    else
        state.playback_clock.position(window.widget_monotonic_time(), state.global_duration);

    const inverse_art_mix = 1.0 - state.global_anim_art_t;
    const ease = 1.0 - inverse_art_mix * inverse_art_mix * inverse_art_mix;
    const inset = 10.0 * (1.0 - ease);
    const radius_delta: f64 = switch (state.setting_artwork_radius) {
        .soft => -8.0,
        .rounded => 0.0,
        .large => 8.0,
    };

    const art = gpu.Rect{
        .x = state.layout.art_x + inset,
        .y = state.layout.art_y + inset,
        .w = @max(1.0, state.layout.art_size - 2.0 * inset),
        .h = @max(1.0, state.layout.art_size - 2.0 * inset),
        .radius = @max(0.0, state.layout.art_radius + radius_delta - inset * state.layout.compact_mix),
    };

    const transition = std.math.clamp(1.0 - (state.art_transition_until - state.animation_time) / assets.transition_duration, 0.0, 1.0);
    const mix = transition * transition * transition * (10.0 + transition * (-15.0 + 6.0 * transition));

    drawArtworkGlow(canvas, ease, mix);
    drawArtworkImage(canvas, art, ease, mix);

    if (state.layout.compact_mix > 0.5) {
        if (state.setting_compact_gradient) {
            _ = canvas.add(native.gpu.WALLIFY_GRADIENT, 0, .{
                .x = card.x,
                .y = card.y + 84.0,
                .w = card.w,
                .h = @max(0.0, card.h - 84.0),
            }, .{ 0.0, 0.0, 0.0, 162.0 / 255.0 });
        }
    } else {
        if (state.layout.progressVisible(state.setting_hide_progress)) drawProgressBar(canvas, elapsed);
        if (state.layout.controlsVisible(state.setting_show_controls)) drawButtons(canvas);
    }

    labels.drawLabels(canvas, elapsed);
}

fn drawArtworkGlow(canvas: *gpu.Canvas, ease: f64, mix: f64) void {
    if (!state.setting_glow or !state.global_has_artwork or !assets.has_art) return;

    const glow_base_size: f64 = 132.0;
    const glow_extent: f64 = @floatCast(native.wallify_glow_extent(@floatCast(glow_base_size)));
    const size = glow_extent * state.layout.art_size / glow_base_size;
    const rect = gpu.Rect{
        .x = state.layout.art_x + (state.layout.art_size - size) / 2.0,
        .y = state.layout.art_y + (state.layout.art_size - size) / 2.0,
        .w = size,
        .h = size,
    };
    // Keep artwork glow visible with native Liquid Glass, but reduce it enough
    // that it complements the system material instead of overpowering the rim.
    const glass_factor: f32 = if (state.setting_native_glass) 0.45 else 1.0;
    var alpha: f32 = @floatCast(0.5 * ease * state.setting_intensity.multiplier() * glass_factor);

    // In animated transition modes, pulse the ambient glow slightly during the transition
    if (state.setting_transition != .default and mix < 1.0) {
        const pulse = @as(f32, @floatCast(std.math.sin(mix * std.math.pi)));
        alpha *= (1.0 + 0.35 * pulse);
    }

    if (mix < 1.0) {
        _ = canvas.add(native.gpu.WALLIFY_GLOW, @intFromEnum(gpu.Texture.previous_glow), rect, .{ 1.0, 1.0, 1.0, alpha * @as(f32, @floatCast(1.0 - mix)) });
    }
    _ = canvas.add(native.gpu.WALLIFY_GLOW, @intFromEnum(gpu.Texture.glow), rect, .{ 1.0, 1.0, 1.0, alpha * @as(f32, @floatCast(mix)) });
}

fn drawArtworkImage(canvas: *gpu.Canvas, art: gpu.Rect, ease: f64, mix: f64) void {
    if (state.global_has_artwork and assets.has_art) {
        if (state.setting_transition != .default and mix < 1.0) {
            canvas.transition(
                state.setting_transition,
                .artwork,
                .previous_artwork,
                art,
                @floatCast(mix),
                @floatCast(state.animation_time),
                @as(f32, @floatFromInt(state.extracted_r)) / 255.0,
                @as(f32, @floatFromInt(state.extracted_g)) / 255.0,
                @as(f32, @floatFromInt(state.extracted_b)) / 255.0,
            );
        } else {
            if (mix < 1.0) canvas.image(.previous_artwork, art, 1.0);
            canvas.image(.artwork, art, @floatCast(mix));
        }

        if (state.setting_dim) {
            canvas.fill(art, .{ 0.0, 0.0, 0.0, @floatCast(0.4 * (1.0 - ease)) });
        }
        if (state.layout.compact_mix < 0.5 and state.setting_artwork_border) {
            canvas.stroke(art, 0.5, .{ 1.0, 1.0, 1.0, 0.11 });
        }
    } else {
        canvas.fill(art, .{ 0.157, 0.157, 0.176, 1.0 });
    }
}

fn drawProgressBar(canvas: *gpu.Canvas, elapsed: f64) void {
    const base_height: f64 = switch (state.setting_progress_thickness) {
        .thin => 3.0,
        .standard => 5.0,
        .thick => 8.0,
    };
    const height = base_height + 4.0 * state.seek_expansion;
    const bar = gpu.Rect{
        .x = state.layout.bar_x,
        .y = state.layout.bar_y - (height - state.layout.bar_h) / 2.0,
        .w = state.layout.bar_w,
        .h = height,
        .radius = height / 2.0,
    };
    canvas.fill(bar, .{ 0.176, 0.176, 0.176, 1.0 });

    if (state.global_duration > 0.0) {
        var progress = bar;
        progress.w *= std.math.clamp(elapsed / state.global_duration, 0.0, 1.0);
        if (progress.w > 0.0) canvas.fill(progress, .{ 1.0, 1.0, 1.0, 1.0 });
    }
}

fn drawButtons(canvas: *gpu.Canvas) void {
    for (state.layout.buttons, 0..) |button, i| {
        if (state.hover_amount[i] > 0.001) {
            canvas.fill(button.bounds(), .{ 1.0, 1.0, 1.0, @floatCast(state.hover_amount[i] * 31.0 / 255.0) });
        }

        const texture: gpu.Texture = switch (button.id) {
            .Prev => .previous,
            .Next => .next,
            .PlayPause => if (state.play_pause_mix < 0.5) .play else .pause,
        };

        const scale = if (button.id == .PlayPause)
            icon_transition.scale(state.play_pause_mix, state.global_rate > 0.0)
        else
            1.0;

        const size = 48.0 * scale;
        canvas.image(texture, .{
            .x = button.x - size / 2.0,
            .y = button.y - size / 2.0,
            .w = size,
            .h = size,
        }, 1.0);
    }
}
