const std = @import("std");
const state = @import("../state.zig");
const render = @import("render.zig");
const media = @import("../media/controller.zig");
const icon_transition = @import("icon_transition.zig");
const window = @import("../ui/window.zig");
const menu = @import("../ui/menu.zig");
const spotify = @import("../media/spotify.zig");
const text_cache = @import("text_cache.zig");

const FRAME_TIME_LIMIT: f64 = 0.1;
const TARGET_FPS: f64 = 60.0;
const IDLE_MIX_SPEED: f64 = 2.5;
const MODE_MIX_EPSILON: f64 = 0.001;
const MODE_MIX_SPEED: f64 = 8.0;
const PANEL_SNAP_DURATION: f64 = 0.22;
const MARQUEE_MODE_THRESHOLD: f64 = 0.99;
const COMPACT_MODE_THRESHOLD: f64 = 0.5;
const MARQUEE_FONT_SIZE: usize = 15;
const MARQUEE_VIEWPORT_WIDTH: f64 = 126.0;
const MARQUEE_SPEED: f64 = 28.0;
const SEEK_EXPANSION_EPSILON: f64 = 0.0001;
const SEEK_VELOCITY_EPSILON: f64 = 0.001;
const SEEK_K: f64 = 322.27;
const SEEK_DAMPING: f64 = 25.13;
const HOVER_EPSILON: f64 = 0.001;
const HOVER_SPEED: f64 = 10.0;
const ART_FADE_DURATION: f64 = 0.3;
const ARTWORK_WAKE_GRACE: f64 = 0.1;
const IDLE_DRAW_SLEEP_US: u64 = 20_000;

fn sleep_us(us: u64) void {
    const ts = std.posix.timespec{
        .sec = @intCast(us / 1_000_000),
        .nsec = @intCast((us % 1_000_000) * 1000),
    };
    _ = std.posix.system.nanosleep(&ts, null);
}

fn resizePanel(compact: bool) void {
    @import("../platform/native.zig").resize(compact);
}
fn movePanelToWidgetGrid() void {
    @import("../platform/native.zig").wallify_move(state.widget_margin_left, state.widget_margin_top);
}

pub fn animationLoop() void {
    var previous_columns = @import("../platform/native.zig").wallify_width();
    var previous_time = window.widget_monotonic_time();
    while (true) {
        const columns = @import("../platform/native.zig").wallify_width();
        var needs_draw = state.frame_requested.swap(false, .acq_rel) or columns != previous_columns;
        previous_columns = columns;
        const now = window.widget_monotonic_time();
        if (state.animation_time < state.art_transition_until) needs_draw = true;
        const menu_action = menu.widget_context_menu_action();
        switch (menu_action) {
            .play_pause => media.togglePlayback(),
            .previous_track => media.triggerCommand(.previous_track),
            .next_track => media.triggerCommand(.next_track),
            .open_spotify => spotify.widget_open_spotify(),
            .toggle_glow => state.setting_glow = !state.setting_glow,
            .toggle_animations => state.setting_animations = !state.setting_animations,
            .toggle_dim => state.setting_dim = !state.setting_dim,
            .idle_spotify => state.setting_idle_style = .spotify,
            .idle_pixel => state.setting_idle_style = .pixel_cat,
            .idle_banana => state.setting_idle_style = .banana_cat,
            .frame_off => state.setting_frame = .off,
            .frame_subtle => state.setting_frame = .subtle,
            .frame_strong => state.setting_frame = .strong,
            .intensity_low => state.setting_intensity = .low,
            .intensity_normal => state.setting_intensity = .normal,
            .intensity_high => state.setting_intensity = .high,
            .speed_slow => state.setting_speed = .slow,
            .speed_normal => state.setting_speed = .normal,
            .speed_fast => state.setting_speed = .fast,
            .restore_defaults => {
                resizePanel(false);
                state.setting_idle_style = .spotify;
                state.setting_glow = true;
                state.setting_animations = true;
                state.setting_dim = true;
                state.setting_frame = .subtle;
                state.setting_intensity = .normal;
                state.setting_speed = .normal;
                state.setting_source = .now_playing;
                state.setting_mode = .expanded;
            },
            .source_now_playing => state.setting_source = .now_playing,
            .source_spotify => state.setting_source = .spotify,
            .mode_compact => {
                state.panel_resize_after_compact = true;
                state.setting_mode = .compact;
            },
            .mode_expanded => {
                state.panel_resize_after_compact = false;
                resizePanel(false);
                state.setting_mode = .expanded;
            },
            else => {},
        }
        if (menu_action != .none) {
            if (@intFromEnum(menu_action) >= 5) state.saveWidgetSettings();
            needs_draw = true;
        }
        if (!state.setting_animations) {
            state.play_pause_mix = if (state.global_rate > 0) 1 else 0;
            state.global_anim_art_t = state.play_pause_mix;
            state.art_transition_until = 0;
            state.seek_expansion = if (state.global_is_dragging) 1 else 0;
            state.seek_velocity = 0;
        }

        const dt = @min(FRAME_TIME_LIMIT, @max(0, now - previous_time)) * state.setting_speed.multiplier();
        state.animation_time += dt;
        const idle_target: f64 = if (state.spotifyIdle()) 1 else 0;
        const old_idle_mix = state.idle_mix;
        state.idle_mix = if (!state.setting_animations) idle_target else state.idle_mix + std.math.clamp(idle_target - state.idle_mix, -dt * IDLE_MIX_SPEED, dt * IDLE_MIX_SPEED);
        if (old_idle_mix != state.idle_mix) needs_draw = true;
        if (state.idle_mix > 0 and state.cat_pet_until > 0 and state.animation_time < state.cat_pet_until + ARTWORK_WAKE_GRACE) needs_draw = true;
        if (state.idle_mix > 0 and state.setting_idle_style != .spotify and state.setting_animations) {
            const fps: f64 = switch (state.setting_idle_style) {
                .banana_cat => 24.0,
                else => 30.0,
            };
            const previous_tick = @floor(state.cat_time * fps);
            state.cat_time += dt;
            if (@floor(state.cat_time * fps) != previous_tick) needs_draw = true;
        }
        const target_mode: f64 = @floatFromInt(@intFromEnum(state.setting_mode));
        if (!state.setting_animations) state.mode_mix = target_mode;
        if (@abs(state.mode_mix - target_mode) > MODE_MIX_EPSILON) {
            // Smooth, critically damped-feeling mode morph without a visible jump.
            state.mode_mix += (target_mode - state.mode_mix) * @min(1, dt * MODE_MIX_SPEED);
            needs_draw = true;
        } else state.mode_mix = target_mode;
        if (state.panel_resize_after_compact and state.mode_mix <= 0.001) {
            state.panel_resize_after_compact = false;
            resizePanel(true);
        }
        if (state.panel_position_dirty) {
            state.panel_position_dirty = false;
            movePanelToWidgetGrid();
            needs_draw = true;
        }
        if (state.panel_snap_active) {
            state.panel_snap_elapsed += dt;
            const t = @min(1.0, state.panel_snap_elapsed / PANEL_SNAP_DURATION);
            const eased = 1.0 - (1.0 - t) * (1.0 - t) * (1.0 - t);
            state.widget_margin_left = @intFromFloat(@round(@as(f64, @floatFromInt(state.panel_snap_start_left)) + @as(f64, @floatFromInt(state.panel_snap_target_left - state.panel_snap_start_left)) * eased));
            state.widget_margin_top = @intFromFloat(@round(@as(f64, @floatFromInt(state.panel_snap_start_top)) + @as(f64, @floatFromInt(state.panel_snap_target_top - state.panel_snap_start_top)) * eased));
            state.panel_position_dirty = true;
            needs_draw = true;
            if (t >= 1.0) {
                state.panel_snap_active = false;
                if (state.panel_save_after_snap) {
                    state.panel_save_after_snap = false;
                    state.saveWidgetSettings();
                }
            }
        }
        if (!state.spotifyIdle() and state.mode_mix < MARQUEE_MODE_THRESHOLD and state.global_title_len > 0) {
            const title_width = text_cache.width(state.global_title[0..state.global_title_len], MARQUEE_FONT_SIZE, true);
            if (title_width > MARQUEE_VIEWPORT_WIDTH and state.setting_animations) {
                const travel = title_width - MARQUEE_VIEWPORT_WIDTH;
                state.marquee_offset += dt * MARQUEE_SPEED * state.marquee_direction;
                if (state.marquee_offset >= travel) {
                    state.marquee_offset = travel;
                    state.marquee_direction = -1;
                } else if (state.marquee_offset <= 0) {
                    state.marquee_offset = 0;
                    state.marquee_direction = 1;
                }
            } else {
                state.marquee_offset = 0;
                state.marquee_direction = 1;
            }
            if (title_width > MARQUEE_VIEWPORT_WIDTH and state.setting_animations) needs_draw = true;
        } else {
            state.marquee_offset = 0;
            state.marquee_direction = 1;
        }
        previous_time = now;
        const seek_target: f64 = if (state.global_is_dragging) 1 else 0;
        if (@abs(state.seek_expansion - seek_target) > SEEK_EXPANSION_EPSILON or @abs(state.seek_velocity) > SEEK_VELOCITY_EPSILON) {
            const step = @min(dt, 1.0 / TARGET_FPS);
            state.seek_velocity += (SEEK_K * (seek_target - state.seek_expansion) - SEEK_DAMPING * state.seek_velocity) * step;
            state.seek_expansion += state.seek_velocity * step;
            needs_draw = true;
        }
        if (state.global_rate > 0 and !state.global_is_dragging and
            (state.mode_mix >= COMPACT_MODE_THRESHOLD or (state.setting_glow and state.setting_animations))) needs_draw = true;
        const icon_target: f64 = if (state.global_rate > 0) 1 else 0;
        if (state.play_pause_mix != icon_target) {
            state.play_pause_mix = icon_transition.advance(state.play_pause_mix, state.global_rate > 0, dt);
            needs_draw = true;
        }
        for (state.layout.buttons, 0..) |button, index| {
            const target: f64 = if (state.global_hover_target == state.HitTarget.fromActionId(button.id)) 1 else 0;
            if (@abs(state.hover_amount[index] - target) > HOVER_EPSILON) {
                state.hover_amount[index] += (target - state.hover_amount[index]) * (if (state.setting_animations) @min(1, dt * HOVER_SPEED) else 1);
                needs_draw = true;
            }
        }
        if (state.global_rate > 0.0) {
            if (state.global_anim_art_t < 1.0) {
                state.global_anim_art_t += dt / ART_FADE_DURATION;
                if (state.global_anim_art_t > 1.0) state.global_anim_art_t = 1.0;
                needs_draw = true;
            }
        } else {
            if (state.global_anim_art_t > 0.0) {
                state.global_anim_art_t -= dt / ART_FADE_DURATION;
                if (state.global_anim_art_t < 0.0) state.global_anim_art_t = 0.0;
                needs_draw = true;
            }
        }

        if (needs_draw) {
            render.drawUIFrame();
            const remaining = (1.0 / TARGET_FPS) - (window.widget_monotonic_time() - now);
            if (remaining > 0) sleep_us(@intFromFloat(remaining * 1_000_000));
        } else {
            sleep_us(IDLE_DRAW_SLEEP_US);
        }
    }
}
