const std = @import("std");
const state = @import("../state.zig");
const window = @import("window.zig");
const hitbox = @import("hitbox.zig");
const media = @import("../media/controller.zig");
const spotify = @import("../media/spotify.zig");
const menu = @import("menu.zig");

const POINTER_CLICK: c_int = 1;
const POINTER_RELEASE: c_int = 2;
const POINTER_RIGHT_CLICK: c_int = 3;
const SNAP_STEP_THRESHOLD: i32 = 8;
const CLICK_TOLERANCE: f64 = 5.0;
const PET_DURATION: f64 = 2.5;
const RATE_LOCKED: u32 = 1;
const RATE_LOCK_DURATION: f64 = 0.5;
const COMPACT_MODE_THRESHOLD: f64 = 0.5;
const ART_HIT_RADIUS: f64 = 14.0;
const SEEK_HIT_RADIUS: f64 = 3.0;
const PANEL_DRAG_TOP_MIN: i32 = state.Layout.margin_top_min;

pub export fn wallify_pointer(x: f64, y_top_down: f64, kind: c_int) void {
    const is_click = kind == POINTER_CLICK;
    const is_release = kind == POINTER_RELEASE;
    const is_right = kind == POINTER_RIGHT_CLICK;

    const px = x;
    const py = y_top_down;

    state.pointer_x = px;
    const point = hitbox.Point{ .x = px, .y = py };

    if (is_right) {
        state.global_is_dragging = false;
        state.global_panel_dragging = false;
        window.widget_hide_snap_outline();
        state.global_hover_target = .none;
        menu.widget_context_menu(@intFromBool(state.global_rate > 0), @intFromBool(state.setting_glow), @intFromBool(state.setting_animations), @intFromBool(state.setting_dim), state.setting_frame, state.setting_intensity, state.setting_speed, state.setting_source, state.setting_mode);
        state.requestFrame();
        return;
    }

    var new_hover_target: state.HitTarget = .grid_background;
    var pressed: ?state.ActionId = null;

    for (state.layout.buttons) |button| {
        if (button.bounds().contains(point)) {
            new_hover_target = state.HitTarget.fromActionId(button.id);
            break;
        }
    } else {
        const seek_bounds = hitbox.Rect{ .x = state.layout.bar_x, .y = state.layout.bar_y - state.layout.bar_hit_pad_y, .w = state.layout.bar_w, .h = state.layout.bar_h + 2 * state.layout.bar_hit_pad_y, .radius = SEEK_HIT_RADIUS };
        const art_bounds = hitbox.Rect{ .x = state.layout.art_x, .y = state.layout.art_y, .w = state.layout.art_size, .h = state.layout.art_size, .radius = ART_HIT_RADIUS };
        const frame_bounds = state.layout.card(state.mode_mix);
        if (seek_bounds.contains(point)) {
            new_hover_target = .bar;
        } else if (art_bounds.contains(point)) {
            new_hover_target = .art;
        } else if (frame_bounds.contains(point)) {
            new_hover_target = .frame_bounds;
        }
    }

    var state_changed = false;
    if (state.global_hover_target != new_hover_target) {
        state.global_hover_target = new_hover_target;
        state_changed = true;
    }

    if (is_click) {
        for (state.layout.buttons) |button| {
            if (!state.spotifyIdle() and button.bounds().contains(point)) pressed = button.id;
        }
        if (state.global_click_target != new_hover_target) {
            state.global_click_target = new_hover_target;
            state_changed = true;
        }

        if (state.global_duration > 0 and new_hover_target == .bar) {
            state.global_is_dragging = true;
            state_changed = true;
        }

        const card_bounds = state.layout.card(state.mode_mix);
        if (card_bounds.contains(point) and pressed == null and !state.global_is_dragging) {
            const mouse = window.widget_mouse_location();
            state.global_panel_dragging = true;
            state.widget_drag_start_mouse_x = mouse.x;
            state.widget_drag_start_mouse_y = mouse.y;
            state.widget_drag_start_margin_left = state.widget_margin_left;
            state.widget_drag_start_margin_top = state.widget_margin_top;
            const visual_width: f64 = if (state.mode_mix < COMPACT_MODE_THRESHOLD) state.Layout.compact_panel_width else state.Layout.expanded_panel_width;
            window.widget_start_drag(state.widget_margin_left, state.widget_margin_top, visual_width);
            state_changed = true;
        }
    }

    if (state.global_panel_dragging) {
        if (!is_click and !is_release) {
            const mouse = window.widget_mouse_location();
            const next_left: i32 = @max(0, state.widget_drag_start_margin_left + @as(i32, @intFromFloat(@round(mouse.x - state.widget_drag_start_mouse_x))));
            const next_top: i32 = @max(PANEL_DRAG_TOP_MIN, state.widget_drag_start_margin_top + @as(i32, @intFromFloat(@round(state.widget_drag_start_mouse_y - mouse.y))));
            if (@abs(next_left - state.widget_margin_left) >= SNAP_STEP_THRESHOLD or @abs(next_top - state.widget_margin_top) >= SNAP_STEP_THRESHOLD) {
                state.widget_margin_left = next_left;
                state.widget_margin_top = next_top;
                state.panel_position_dirty = true;
            }
        }
        if (is_release) {
            const mouse = window.widget_mouse_location();
            const idle_click = state.spotifyIdle() and @abs(mouse.x - state.widget_drag_start_mouse_x) < CLICK_TOLERANCE and @abs(mouse.y - state.widget_drag_start_mouse_y) < CLICK_TOLERANCE;
            if (idle_click) {
                if (state.setting_idle_style != .spotify) state.cat_pet_until = state.animation_time + PET_DURATION else spotify.widget_open_spotify();
            }
            state.global_panel_dragging = false;
            window.widget_hide_snap_outline();
            state.saveWidgetSettings();
        }
        state.requestFrame();
        return;
    }

    if (state.spotifyIdle()) {
        if (is_release) {
            if (state.setting_idle_style != .spotify) state.cat_pet_until = state.animation_time + PET_DURATION else spotify.widget_open_spotify();
        }
        return;
    }

    if (is_release and !state.global_is_dragging) {
        if (state.global_click_target == new_hover_target) {
            if (new_hover_target.toActionId()) |action| {
                switch (action) {
                    .PlayPause => media.togglePlayback(),
                    .Prev => media.triggerCommand(.previous_track),
                    .Next => media.triggerCommand(.next_track),
                }
            }
        }
        state.global_click_target = .none;
    }

    if (state.global_is_dragging) {
        var x_offs: f64 = px - state.layout.bar_x;
        if (x_offs < 0.0) x_offs = 0.0;
        if (x_offs > state.layout.bar_w) x_offs = state.layout.bar_w;
        const target = state.global_duration * (x_offs / state.layout.bar_w);

        if (is_release) {
            state.global_is_dragging = false;
            state.global_elapsed = target;
            state_changed = true;
            state.playback_clock.sync(target, state.global_rate, window.widget_monotonic_time(), state.global_duration, true);
            media.triggerSeek(target);
            state.global_rate_lock = RATE_LOCKED;
            state.global_rate_lock_until = window.widget_monotonic_time() + RATE_LOCK_DURATION;
        } else {
            state.global_elapsed = target;
            state.requestFrame();
        }
    }

    if (state_changed) {
        state.requestFrame();
    }
}
