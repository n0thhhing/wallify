const std = @import("std");
const state = @import("../state.zig");
const native = @import("../platform/native.zig");
const gpu = @import("canvas.zig");
const assets = @import("assets.zig");
const text = @import("text_cache.zig");
const window = @import("../ui/window.zig");
const icon_transition = @import("icon_transition.zig");
const L = state.Layout;
const primary: gpu.Color = .{ 245.0 / 255.0, 245.0 / 255.0, 247.0 / 255.0, 1 };
fn lerp(a: f64, b: f64, t: f64) f64 {
    return a + (b - a) * t;
}

// Metadata updates invalidate the artwork cache; rendering never polls the file.
pub fn extractColor() void {
    assets.artwork_dirty.store(true, .release);
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
    state.layout.update(@floatFromInt(native.wallify_width()), @floatFromInt(native.wallify_height()), state.mode_mix);
    const card = state.layout.card(state.mode_mix);
    var canvas = gpu.Canvas{ .clip = card };
    canvas.fill(card, .{ 28.0 / 255.0, 28.0 / 255.0, 30.0 / 255.0, 1 });
    if (state.idle_mix < 1) drawPlayer(&canvas, card);
    if (state.idle_mix > 0) {
        // Opaque idle background provides the group crossfade without a CPU underlay.
        canvas.opacity = @floatCast(state.idle_mix);
        canvas.fill(card, .{ 30.0 / 255.0, 29.0 / 255.0, 32.0 / 255.0, 1 });
        switch (state.setting_idle_style) {
            .pixel_cat => @import("pets/idle_cat.zig").draw(&canvas, card, state.cat_time),
            .banana_cat => @import("pets/banana_cat.zig").draw(&canvas, card, state.cat_time),
            .spotify => {
                const compact = state.mode_mix < 0.5;
                const size = if (compact) card.w else L.art_size_expanded;
                const padded = size * 128.0 / 104.0;
                const inset = (padded - size) / 2;
                canvas.image(.spotify, .{ .x = (if (compact) card.x else L.art_x_expanded) - inset, .y = (if (compact) card.y else L.art_y_expanded) - inset, .w = padded, .h = padded }, 1);
                if (!compact) {
                    text.draw(&canvas, "Open Spotify", state.layout.bar_x, L.art_y_expanded + 36, state.layout.bar_w, 17, 1, true, primary, 0, false, true);
                    text.draw(&canvas, "Click to launch", state.layout.bar_x, L.art_y_expanded + 63, state.layout.bar_w, 13, 1, false, .{ 0.62, 0.60, 0.57, 1 }, 0, false, true);
                }
            },
        }
    }
    canvas.opacity = 1;
    const frame = state.setting_frame.multiplier();
    if (frame > 0) canvas.stroke(card, 0.8, .{ 1, 1, 1, @floatCast(0.12 * frame) });
    canvas.submit(state.layout.width, state.layout.height);
}
fn drawPlayer(canvas: *gpu.Canvas, card: gpu.Rect) void {
    const elapsed = if (state.global_is_dragging) state.global_elapsed else state.playback_clock.position(window.widget_monotonic_time(), state.global_duration);
    const ease = 1 - std.math.pow(f64, 1 - state.global_anim_art_t, 3);
    const inset = 10 * (1 - ease);
    const art = gpu.Rect{ .x = state.layout.art_x + inset, .y = state.layout.art_y + inset, .w = state.layout.art_size - 2 * inset, .h = state.layout.art_size - 2 * inset, .radius = @max(0, lerp(L.art_corner_radius_compact, L.art_corner_radius_expanded, state.mode_mix) - inset * (1 - state.mode_mix)) };
    const transition = std.math.clamp(1 - (state.art_transition_until - state.animation_time) / assets.transition_duration, 0, 1);
    const mix = transition * transition * transition * (10 + transition * (-15 + 6 * transition));
    if (state.setting_glow and state.global_has_artwork and assets.has_art) {
        const size = @as(f64, native.wallify_glow_extent(L.art_size_expanded)) * state.layout.art_size / L.art_size_expanded;
        const rect = gpu.Rect{
            .x = state.layout.art_x + (state.layout.art_size - size) / 2,
            .y = state.layout.art_y + (state.layout.art_size - size) / 2,
            .w = size,
            .h = size,
        };
        const alpha: f32 = @floatCast(0.5 * ease * state.setting_intensity.multiplier());
        if (mix < 1) _ = canvas.add(native.gpu.WALLIFY_GLOW, @intFromEnum(gpu.Texture.previous_glow), rect, .{ 1, 1, 1, alpha * @as(f32, @floatCast(1 - mix)) });
        _ = canvas.add(native.gpu.WALLIFY_GLOW, @intFromEnum(gpu.Texture.glow), rect, .{ 1, 1, 1, alpha * @as(f32, @floatCast(mix)) });
    }
    if (state.global_has_artwork and assets.has_art) {
        if (mix < 1) canvas.image(.previous_artwork, art, 1);
        canvas.image(.artwork, art, @floatCast(mix));
        if (state.setting_dim) canvas.fill(art, .{ 0, 0, 0, @floatCast(0.4 * (1 - ease)) });
        if (state.mode_mix >= 0.5) canvas.stroke(art, 0.5, .{ 1, 1, 1, 0.11 });
    } else canvas.fill(art, .{ 0.157, 0.157, 0.176, 1 });
    if (state.mode_mix < 0.5) {
        _ = canvas.add(native.gpu.WALLIFY_GRADIENT, 0, .{ .x = card.x, .y = card.y + 84, .w = card.w, .h = card.h - 84 }, .{ 0, 0, 0, 162.0 / 255.0 });
    } else {
        const height = state.layout.bar_h + 4 * state.seek_expansion;
        const bar = gpu.Rect{ .x = state.layout.bar_x, .y = state.layout.bar_y - (height - state.layout.bar_h) / 2, .w = state.layout.bar_w, .h = height, .radius = height / 2 };
        canvas.fill(bar, .{ 0.176, 0.176, 0.176, 1 });
        if (state.global_duration > 0) {
            var progress = bar;
            progress.w *= std.math.clamp(elapsed / state.global_duration, 0, 1);
            if (progress.w > 0) canvas.fill(progress, .{ 1, 1, 1, 1 });
        }
        for (state.layout.buttons, 0..) |button, i| {
            if (state.hover_amount[i] > 0.001) canvas.fill(button.bounds(), .{ 1, 1, 1, @floatCast(state.hover_amount[i] * 31.0 / 255.0) });
            const texture: gpu.Texture = switch (button.id) {
                .Prev => .previous,
                .Next => .next,
                .PlayPause => if (state.play_pause_mix < 0.5) .play else .pause,
            };
            const scale = if (button.id == .PlayPause) icon_transition.scale(state.play_pause_mix, state.global_rate > 0) else 1;
            const size = 48 * scale;
            canvas.image(texture, .{ .x = button.x - size / 2, .y = button.y - size / 2, .w = size, .h = size }, 1);
        }
    }
    drawLabels(canvas, elapsed);
}
fn drawLabels(canvas: *gpu.Canvas, elapsed: f64) void {
    const title = if (state.global_title_len > 0) state.global_title[0..state.global_title_len] else "Not Playing";
    const artist = if (state.global_artist_len > 0) state.global_artist[0..state.global_artist_len] else "";
    const secondary: gpu.Color = .{ @as(f32, @floatFromInt(@max(145, state.extracted_r))) / 255.0, @as(f32, @floatFromInt(@max(145, state.extracted_g))) / 255.0, @as(f32, @floatFromInt(@max(145, state.extracted_b))) / 255.0, 1 };
    if (state.mode_mix < 0.16) {
        text.draw(canvas, title, L.art_x_expanded, L.card_y + L.mini_title_y, L.mini_text_width, 15, 1, true, primary, state.marquee_offset, false, false);
        text.draw(canvas, artist, L.art_x_expanded, L.card_y + L.mini_artist_y, L.mini_text_width, 11, 1, false, secondary, 0, false, true);
        return;
    }
    const t = std.math.clamp((state.mode_mix - 0.16) / 0.84, 0, 1);
    const x = lerp(L.art_x_expanded, state.layout.bar_x, t);
    const width = lerp(L.mini_text_width, state.layout.bar_w, t);
    text.draw(canvas, title, x, lerp(L.card_y + L.mini_title_y, state.layout.art_y + 8, t), width, 17, lerp(15, 17, t) / 17, true, primary, 0, false, true);
    text.draw(canvas, if (artist.len > 0) artist else "Play something to get started", x, lerp(L.card_y + L.mini_artist_y, state.layout.art_y + 32, t), width, 14, lerp(11, 14, t) / 14, false, secondary, 0, false, true);
    if (t < 0.88) return;
    var buffer: [32]u8 = undefined;
    const e: u32 = @intFromFloat(@max(0, elapsed));
    const d: u32 = @intFromFloat(@max(0, state.global_duration));
    const e_text = std.fmt.bufPrint(&buffer, "{d}:{d:0>2}", .{ e / 60, e % 60 }) catch return;
    text.draw(canvas, e_text, x, state.layout.bar_y + 13, 100, 12, 1, false, secondary, 0, false, false);
    const d_text = std.fmt.bufPrint(&buffer, "{d}:{d:0>2}", .{ d / 60, d % 60 }) catch return;
    text.draw(canvas, d_text, x, state.layout.bar_y + 13, state.layout.bar_w, 12, 1, false, secondary, 0, true, false);
}
