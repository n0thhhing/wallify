const std = @import("std");
const state = @import("../state.zig");
const render = @import("render.zig");
const media = @import("../media/controller.zig");
const icon_transition = @import("icon_transition.zig");
const window = @import("../ui/window.zig");
const menu = @import("../ui/menu.zig");
const spotify = @import("../media/spotify.zig");
const spotifast = @import("../media/spotifast.zig");
const text_cache = @import("text_cache.zig");
const frame_wakeup = @import("../frame_wakeup.zig");

const FRAME_TIME_LIMIT: f64 = 0.1;
const TARGET_FPS: f64 = 60.0;
const IDLE_MIX_SPEED: f64 = 2.5;
const MODE_MIX_EPSILON: f64 = 0.001;
const MODE_MIX_SPEED: f64 = 8.0;
const PANEL_SNAP_DURATION: f64 = 0.22;
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
const PROGRESS_FRAME_INTERVAL: f64 = 1.0 / 30.0;

fn sleep_us(us: u64) void {
    const ts = std.posix.timespec{
        .sec = @intCast(us / 1_000_000),
        .nsec = @intCast((us % 1_000_000) * 1000),
    };
    _ = std.posix.system.nanosleep(&ts, null);
}

fn beginModeTransition(new_mode: state.WidgetMode) void {
    const native = @import("../platform/native.zig");
    const current_width: f64 = @floatFromInt(native.wallify_width());
    const current_height: f64 = @floatFromInt(native.wallify_height());

    state.beginModeTransition(
        new_mode,
        current_width,
        current_height,
        state.setting_animations,
    );

    if (!state.mode_transition_active) {
        native.resizeForMode(new_mode);
    }
}

fn movePanelToWidgetGrid() void {
    @import("../platform/native.zig").wallify_move(state.widget_margin_left, state.widget_margin_top);
    @import("../ui/settings_window.zig").notify_position_changed();
}

pub fn animationLoop() void {
    var previous_columns = @import("../platform/native.zig").wallify_width();
    var previous_time = window.widget_monotonic_time();
    var last_draw_time = previous_time;
    var marquee_cached_title: [256]u8 = undefined;
    var marquee_cached_title_len: usize = 0;
    var marquee_cached_width: f64 = 0.0;
    while (true) {
        var high_rate_animation = false;
        var idle_frame_interval: f64 = 0;
        const columns = @import("../platform/native.zig").wallify_width();
        var needs_draw = state.frame_requested.swap(false, .acq_rel) or columns != previous_columns;
        previous_columns = columns;
        const now = window.widget_monotonic_time();
        if (state.animation_time < state.art_transition_until) {
            needs_draw = true;
            high_rate_animation = true;
        }
        const menu_action = menu.widget_context_menu_action();
        if (menu_action != .none) {
            std.log.info("menu: action={s}", .{@tagName(menu_action)});
        }
        switch (menu_action) {
            .play_pause => media.togglePlayback(),
            .previous_track => media.triggerCommand(.previous_track),
            .next_track => media.triggerCommand(.next_track),
            .open_spotify => if (state.setting_source == .spotifast) spotifast.widget_open_spotifast() else spotify.widget_open_spotify(),
            .toggle_glow => state.setting_glow = !state.setting_glow,
            .toggle_aurora => state.setting_aurora = !state.setting_aurora,
            .toggle_animations => state.setting_animations = !state.setting_animations,
            .toggle_dim => state.setting_dim = !state.setting_dim,
            .idle_spotify => state.setting_idle_style = .spotify,
            .idle_pixel => state.setting_idle_style = .pixel_cat,
            .idle_banana => state.setting_idle_style = .banana_cat,
            .idle_raccoon => state.setting_idle_style = .raccoon,
            .transition_default => state.setting_transition = .default,
            .transition_cinematic => state.setting_transition = .cinematic,
            .transition_ripple => state.setting_transition = .ripple,
            .transition_flip => state.setting_transition = .flip,
            .transition_vinyl => state.setting_transition = .vinyl,
            .transition_glitch => state.setting_transition = .glitch,
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
                state.setting_idle_style = .pixel_cat;
                state.setting_transition = .cinematic;
                state.setting_glow = true;
                state.setting_native_glass = false;
                state.setting_aurora = true;
                state.setting_animations = true;
                state.setting_dim = true;
                state.setting_debug = false;
                window.widget_debug_window_hide();
                state.setting_frame = .subtle;
                state.setting_intensity = .normal;
                state.setting_speed = .normal;
                state.setting_source = .now_playing;
                state.setting_hide_text = false;
                state.setting_hide_progress = false;
                state.setting_show_controls = true;
                state.setting_show_timestamps = true;
                state.setting_artwork_border = true;
                state.setting_compact_gradient = true;
                state.setting_artwork_radius = .rounded;
                state.setting_progress_thickness = .standard;
                state.setting_font_scale = .normal;
                state.setting_media_key_target = .off;
                @import("../platform/native.zig").wallify_update_media_key_tap(0);
                beginModeTransition(.expanded);
            },
            .source_now_playing => state.setting_source = .now_playing,
            .source_spotify => state.setting_source = .spotify,
            .source_spotifast => state.setting_source = .spotifast,
            .mode_compact => beginModeTransition(.compact),
            .mode_two_by_one => beginModeTransition(.two_by_one),
            .mode_expanded => beginModeTransition(.expanded),
            .mode_one_by_two => beginModeTransition(.one_by_two),
            .mode_two_by_two => beginModeTransition(.two_by_two),
            .open_settings => {
                @import("../ui/settings_window.zig").open();
            },
            else => {},
        }
        if (menu_action != .none) {
            if (@intFromEnum(menu_action) >= 5 and menu_action != .open_settings) state.saveWidgetSettings();
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
        if (old_idle_mix != state.idle_mix) {
            needs_draw = true;
            high_rate_animation = state.setting_animations;
        }
        if (state.idle_mix > 0 and state.cat_pet_until > 0 and state.animation_time < state.cat_pet_until + ARTWORK_WAKE_GRACE) needs_draw = true;
        if (state.idle_mix > 0 and state.setting_idle_style != .spotify and state.setting_animations) {
            const fps: f64 = switch (state.setting_idle_style) {
                .banana_cat => 24.0,
                else => 30.0,
            };
            const previous_tick = @floor(state.cat_time * fps);
            idle_frame_interval = 1.0 / fps;
            state.cat_time += dt;
            if (@floor(state.cat_time * fps) != previous_tick) {
                needs_draw = true;
            }
        }
        if (state.mode_transition_active) {
            high_rate_animation = true;
            const native = @import("../platform/native.zig");

            if (!state.setting_animations) {
                native.resizeForMode(state.setting_mode);
                state.modeAnimationFinished();
                needs_draw = true;
            } else {
                const previous_mix = state.mode_mix;
                state.mode_mix = @min(1.0, state.mode_mix + dt * 5.5);

                // Ease the physical window and renderer with the same curve.
                const eased = 1.0 - std.math.pow(f64, 1.0 - state.mode_mix, 3.0);
                const width = state.mode_start_width +
                    (state.mode_target_width - state.mode_start_width) * eased;
                const height = state.mode_start_height +
                    (state.mode_target_height - state.mode_start_height) * eased;

                native.resizeTo(width, height);
                needs_draw = true;

                if (state.mode_mix >= 1.0 or previous_mix == state.mode_mix) {
                    state.modeAnimationFinished();
                    native.resizeForMode(state.setting_mode);
                }
            }
        }

        if (state.panel_position_dirty) {
            state.panel_position_dirty = false;
            movePanelToWidgetGrid();
            needs_draw = true;
        }
        if (state.panel_snap_active) {
            high_rate_animation = true;
            // Cubic ease-out snap glide. Settles the panel into its target desktop slot over PANEL_SNAP_DURATION.
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
        if (!state.setting_hide_text and !state.spotifyIdle() and state.layout.compact_mix > 0.01 and state.global_title_len > 0) {
            // Compact tiles lack horizontal clearance for full track titles.
            // If the text width exceeds the viewport, we auto-scroll back and forth (marquee effect).
            const title = state.global_title[0..state.global_title_len];
            if (title.len != marquee_cached_title_len or
                !std.mem.eql(u8, title, marquee_cached_title[0..marquee_cached_title_len]))
            {
                @memcpy(marquee_cached_title[0..title.len], title);
                marquee_cached_title_len = title.len;
                marquee_cached_width = text_cache.width(title, MARQUEE_FONT_SIZE, true);
            }
            const title_width = marquee_cached_width;
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
            if (title_width > MARQUEE_VIEWPORT_WIDTH and state.setting_animations) {
                needs_draw = true;
                high_rate_animation = true;
            }
        } else {
            state.marquee_offset = 0;
            state.marquee_direction = 1;
        }

        const aurora_target: f64 = if (state.setting_aurora and state.idle_mix < 0.5 and state.global_has_artwork) 1 else 0;
        if (!state.setting_animations) {
            state.aurora_mix = aurora_target;
        } else if (@abs(state.aurora_mix - aurora_target) > 0.001) {
            state.aurora_mix += (aurora_target - state.aurora_mix) * @min(1, dt * 3.5);
            needs_draw = true;
        } else {
            state.aurora_mix = aurora_target;
        }
        if (state.aurora_mix > 0.001 and state.global_rate > 0 and state.setting_animations) {
            needs_draw = true;
            high_rate_animation = true;
        }

        previous_time = now;
        const seek_target: f64 = if (state.global_is_dragging) 1 else 0;
        if (@abs(state.seek_expansion - seek_target) > SEEK_EXPANSION_EPSILON or @abs(state.seek_velocity) > SEEK_VELOCITY_EPSILON) {
            high_rate_animation = true;
            // Critically-damped harmonic oscillator for the interactive seek thumb.
            // Provides an organic, bouncy response when the user hovers/drags the progress bar.
            const step = @min(dt, 1.0 / TARGET_FPS);
            state.seek_velocity += (SEEK_K * (seek_target - state.seek_expansion) - SEEK_DAMPING * state.seek_velocity) * step;
            state.seek_expansion += state.seek_velocity * step;
            needs_draw = true;
        }
        const progress_active = state.global_rate > 0 and !state.global_is_dragging and state.layout.compact_mix < 0.5;
        if (progress_active and !high_rate_animation and now - last_draw_time >= PROGRESS_FRAME_INTERVAL) {
            needs_draw = true;
        }
        const icon_target: f64 = if (state.global_rate > 0) 1 else 0;
        if (state.play_pause_mix != icon_target) {
            high_rate_animation = true;
            state.play_pause_mix = icon_transition.advance(state.play_pause_mix, state.global_rate > 0, dt);
            needs_draw = true;
        }
        for (state.layout.buttons, 0..) |button, index| {
            const target: f64 = if (state.global_hover_target == state.HitTarget.fromActionId(button.id)) 1 else 0;
            if (@abs(state.hover_amount[index] - target) > HOVER_EPSILON) {
                high_rate_animation = state.setting_animations;
                state.hover_amount[index] += (target - state.hover_amount[index]) * (if (state.setting_animations) @min(1, dt * HOVER_SPEED) else 1);
                needs_draw = true;
            }
        }
        if (state.global_rate > 0.0) {
            if (state.global_anim_art_t < 1.0) {
                high_rate_animation = true;
                state.global_anim_art_t += dt / ART_FADE_DURATION;
                if (state.global_anim_art_t > 1.0) state.global_anim_art_t = 1.0;
                needs_draw = true;
            }
        } else {
            if (state.global_anim_art_t > 0.0) {
                high_rate_animation = true;
                state.global_anim_art_t -= dt / ART_FADE_DURATION;
                if (state.global_anim_art_t < 0.0) state.global_anim_art_t = 0.0;
                needs_draw = true;
            }
        }

        const frame_interval = if (high_rate_animation)
            1.0 / TARGET_FPS
        else if (idle_frame_interval > 0)
            idle_frame_interval
        else if (progress_active)
            PROGRESS_FRAME_INTERVAL
        else
            0.0;

        if (needs_draw) {
            render.drawUIFrame();
            last_draw_time = window.widget_monotonic_time();
        }

        const after = window.widget_monotonic_time();
        if (frame_interval > 0.0) {
            // Pace loop iterations even when a sprite tick did not need a draw.
            // Basing this on the last draw can spin once that deadline passes.
            const remaining = frame_interval - (after - now);
            if (remaining > 0) sleep_us(@intFromFloat(remaining * 1_000_000));
        } else {
            // Nothing is animating and no progress frame is due. Sleep until
            // another subsystem explicitly requests a frame instead of polling.
            frame_wakeup.wait();
        }
    }
}
