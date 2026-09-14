import os

with open("src/ui/input.zig", "w") as f:
    f.write("""const std = @import("std");
const state = @import("../state.zig");
const window = @import("window.zig");
const hitbox = @import("hitbox.zig");
const media = @import("../media/controller.zig");
const spotify = @import("../media/spotify.zig");
const menu = @import("menu.zig");

pub export fn wallify_pointer(x: f64, y_bottom_up: f64, kind: c_int) void {
    const is_click = kind == 1;
    const is_release = kind == 2;
    const is_right = kind == 3;

    const display_height = state.layout.height;
    const px = x;
    const py = display_height - y_bottom_up;

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
        const seek_bounds = hitbox.Rect{ .x = state.layout.bar_x, .y = state.layout.bar_y - state.layout.bar_hit_pad_y, .w = state.layout.bar_w, .h = state.layout.bar_h + 2 * state.layout.bar_hit_pad_y, .radius = 3 };
        const art_bounds = hitbox.Rect{ .x = state.layout.art_x, .y = state.layout.art_y, .w = state.layout.art_size, .h = state.layout.art_size, .radius = 14 };
        const frame_bounds = hitbox.Rect{ .x = 0, .y = 0, .w = state.layout.width, .h = state.layout.height, .radius = 26 };
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

        const card_width: f64 = if (state.mode_mix < 0.5) 164.0 else state.layout.width;
        const card_x: f64 = if (state.mode_mix < 0.5) 8.0 else 0.0;
        const card_bounds = hitbox.Rect{ .x = card_x, .y = 35, .w = card_width, .h = 164, .radius = 26 };
        if (state.desktop_mode and card_bounds.contains(point) and pressed == null and !state.global_is_dragging) {
            const mouse = window.widget_mouse_location();
            state.global_panel_dragging = true;
            state.widget_drag_start_mouse_x = mouse.x;
            state.widget_drag_start_mouse_y = mouse.y;
            state.widget_drag_start_margin_left = state.widget_margin_left;
            state.widget_drag_start_margin_top = state.widget_margin_top;
            const visual_width: f64 = if (state.mode_mix < 0.5) 164.0 else 531.0;
            window.widget_start_drag(state.widget_margin_left, state.widget_margin_top, visual_width);
            state_changed = true;
        }
    }

    if (state.global_panel_dragging) {
        if (!is_click and !is_release) {
            const mouse = window.widget_mouse_location();
            const next_left: i32 = @max(0, state.widget_drag_start_margin_left + @as(i32, @intFromFloat(@round(mouse.x - state.widget_drag_start_mouse_x))));
            const next_top: i32 = @max(-180, state.widget_drag_start_margin_top + @as(i32, @intFromFloat(@round(state.widget_drag_start_mouse_y - mouse.y))));
            if (@abs(next_left - state.widget_margin_left) >= 8 or @abs(next_top - state.widget_margin_top) >= 8) {
                state.widget_margin_left = next_left;
                state.widget_margin_top = next_top;
                state.panel_position_dirty = true;
                @import("../platform/native.zig").wallify_move(next_left, next_top);
            }
        }
        if (is_release) {
            const mouse = window.widget_mouse_location();
            const idle_click = state.spotifyIdle() and @abs(mouse.x - state.widget_drag_start_mouse_x) < 5 and @abs(mouse.y - state.widget_drag_start_mouse_y) < 5;
            if (idle_click) {
                if (state.setting_idle_style != .spotify) state.cat_pet_until = state.animation_time + 2.5 else spotify.widget_open_spotify();
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
            if (state.setting_idle_style != .spotify) state.cat_pet_until = state.animation_time + 2.5 else spotify.widget_open_spotify();
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
            state.global_rate_lock = 1;
            state.global_rate_lock_until = window.widget_monotonic_time() + 0.5;
        } else {
            state.global_elapsed = target;
            state.requestFrame();
        }
    }

    if (state_changed) {
        state.requestFrame();
    }
}

pub fn enableRawMode() !void {}
pub fn inputLoop() void {}
""")
