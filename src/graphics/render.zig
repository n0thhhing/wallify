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

// Keep the last static command list in Zig as well as the Metal-side texture cache.
// Steady playback only changes progress/labels/Aurora, so rebuilding artwork/glow/buttons
// and their DrawCommands on every frame is wasted CPU work.
var cached_static_canvas: gpu.Canvas = undefined;
var cached_static_key: u64 = 0;
var cached_static_valid = false;

fn hashBool(hash: *std.hash.Wyhash, value: bool) void {
    const v = @intFromBool(value);
    hash.update(std.mem.asBytes(&v));
}

fn hashF64(hash: *std.hash.Wyhash, value: f64) void {
    hash.update(std.mem.asBytes(&value));
}

fn hashEnum(hash: *std.hash.Wyhash, value: anytype) void {
    const v = @intFromEnum(value);
    hash.update(std.mem.asBytes(&v));
}

fn staticSceneKey(card: gpu.Rect) u64 {
    var hash = std.hash.Wyhash.init(0);

    // Layout geometry is determined by these mode/size inputs. Avoid hashing the
    // whole Layout struct because it also contains function-independent cache state.
    hashF64(&hash, state.layout.width);
    hashF64(&hash, state.layout.height);
    hashEnum(&hash, state.mode_from);
    hashEnum(&hash, state.setting_mode);
    hashF64(&hash, state.mode_mix);
    hashF64(&hash, card.x);
    hashF64(&hash, card.y);
    hashF64(&hash, card.w);
    hashF64(&hash, card.h);
    hashF64(&hash, card.radius);

    hashBool(&hash, state.setting_native_glass);
    hashBool(&hash, state.setting_glow);
    hashBool(&hash, state.setting_dim);
    hashBool(&hash, state.setting_compact_gradient);
    hashBool(&hash, state.setting_show_controls);
    hashBool(&hash, state.setting_artwork_border);
    hashEnum(&hash, state.setting_artwork_radius);
    hashEnum(&hash, state.setting_frame);
    hashEnum(&hash, state.setting_intensity);
    hashEnum(&hash, state.setting_transition);

    hashBool(&hash, state.global_has_artwork);
    hashBool(&hash, assets.has_art);
    hashF64(&hash, @as(f64, @floatFromInt(assets.artwork_generation)));
    hashF64(&hash, state.idle_mix);
    hashF64(&hash, state.global_anim_art_t);
    hashF64(&hash, state.play_pause_mix);
    hashF64(&hash, @as(f64, @floatFromInt(state.extracted_r)));
    hashF64(&hash, @as(f64, @floatFromInt(state.extracted_g)));
    hashF64(&hash, @as(f64, @floatFromInt(state.extracted_b)));

    // Track transition math depends on the current animation time, but only while
    // the transition is active. Once settled, animation_time must not invalidate
    // the static cache every frame.
    const transition_active = state.art_transition_until > state.animation_time;
    hashBool(&hash, transition_active);
    if (transition_active) hashF64(&hash, state.animation_time);

    return hash.final();
}

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
        state.mode_from,
        state.setting_mode,
        state.mode_mix,
    );

    const card = state.layout.card(state.mode_mix);
    @import("idle_compositor.zig").update(card);

    // Native Liquid Glass already clips the Metal subview to the card bounds.
    // The static scene cache keeps unchanged artwork/glow/buttons off the
    // per-progress-frame render path.
    const clip: gpu.Rect = if (state.setting_native_glass)
        .{ .x = 0.0, .y = 0.0, .w = 0.0, .h = 0.0, .radius = 0.0 }
    else
        card;

    const static_key = staticSceneKey(card);
    const rebuild_static = !cached_static_valid or cached_static_key != static_key;

    const ambient_intensity: f32 = if (state.global_has_artwork and assets.has_art and state.setting_glow) 0.12 else 0.0;
    native.wallify_update_glass_rect(
        card.x,
        card.y,
        card.w,
        card.h,
        card.radius,
        @as(f32, @floatFromInt(state.extracted_r)) / 255.0,
        @as(f32, @floatFromInt(state.extracted_g)) / 255.0,
        @as(f32, @floatFromInt(state.extracted_b)) / 255.0,
        state.setting_native_glass,
    );

    if (rebuild_static) {
        cached_static_canvas = gpu.Canvas{ .clip = clip };

        if (!state.setting_native_glass) {
            cached_static_canvas.glass(
                card,
                cardBackgroundColor(),
                @as(f32, @floatFromInt(state.extracted_r)) / 255.0,
                @as(f32, @floatFromInt(state.extracted_g)) / 255.0,
                @as(f32, @floatFromInt(state.extracted_b)) / 255.0,
                ambient_intensity,
            );
        }

        if (state.idle_mix < 1.0) {
            player.drawPlayerStatic(&cached_static_canvas, card);
        }

        const frame_strength = state.setting_frame.multiplier();
        if (!state.setting_native_glass and frame_strength > 0.0) {
            cached_static_canvas.stroke(card, 0.8, .{ 1.0, 1.0, 1.0, @floatCast(0.12 * frame_strength) });
        }

        cached_static_key = static_key;
        cached_static_valid = true;
    }

    var dynamic_canvas = gpu.Canvas{ .clip = clip };
    dynamic_canvas.compositeCachedScene(state.layout.width, state.layout.height);

    // Dynamic fluid Aurora wave layer (Apple Music style).
    if (!state.setting_native_glass and state.aurora_mix > 0.001 and state.global_has_artwork and assets.has_art) {
        const pri = [3]f32{
            @as(f32, @floatFromInt(state.extracted_r)) / 255.0,
            @as(f32, @floatFromInt(state.extracted_g)) / 255.0,
            @as(f32, @floatFromInt(state.extracted_b)) / 255.0,
        };
        const dim_factor: f32 = if (state.setting_dim and state.global_rate == 0) 0.65 else 1.0;
        const alpha: f32 = @floatCast(0.32 * state.aurora_mix * (1.0 - state.idle_mix) * dim_factor);
        dynamic_canvas.aurora(card, pri, pri, @floatCast(state.animation_time), alpha);
    }

    if (state.idle_mix < 1.0) {
        const elapsed = if (state.global_rate == 0.0 or state.global_is_dragging)
            state.global_elapsed
        else
            state.playback_clock.position(window.widget_monotonic_time(), state.global_duration);
        player.drawPlayerDynamic(&dynamic_canvas, elapsed);
    } else if (state.idle_mix > 0.0 and !@import("idle_compositor.zig").active) {
        idle.drawIdle(&dynamic_canvas, card);
    }

    gpu.Canvas.submitSplit(
        &cached_static_canvas,
        &dynamic_canvas,
        state.layout.width,
        state.layout.height,
    );
}

