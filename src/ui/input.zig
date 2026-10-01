const std = @import("std");
const state = @import("../state.zig");
const window = @import("window.zig");
const hitbox = @import("hitbox.zig");
const media = @import("../media/controller.zig");
const spotify = @import("../media/spotify.zig");
const spotifast = @import("../media/spotifast.zig");
const menu = @import("menu.zig");

const POINTER_CLICK: c_int = 1;
const POINTER_RELEASE: c_int = 2;
const POINTER_RIGHT_CLICK: c_int = 3;
const SNAP_STEP_THRESHOLD: i32 = 1;
const CLICK_TOLERANCE: f64 = 5.0;
const PET_DURATION: f64 = 2.5;
const RATE_LOCKED: u32 = 1;
const RATE_LOCK_DURATION: f64 = 0.5;
const ART_HIT_RADIUS: f64 = 14.0;
const SEEK_HIT_RADIUS: f64 = 3.0;
const PANEL_DRAG_TOP_MIN: i32 = state.Layout.margin_top_min;

fn isContextMenuKind(kind: c_int) bool {
    return kind == POINTER_RIGHT_CLICK;
}

fn openIdlePlayer() void {
    if (state.shared().setting_source == .spotifast) {
        spotifast.widget_open_spotifast();
    } else {
        spotify.widget_open_spotify();
    }
}

// Pointer input is the highest-priority redraw source: hover, dragging, snapping, and seeking
// all feed the same coalesced frame request instead of owning separate render loops.
pub export fn wallify_pointer(x: f64, y_top_down: f64, kind: c_int) void {
    const is_click = kind == POINTER_CLICK;
    const is_release = kind == POINTER_RELEASE;
    const is_right = isContextMenuKind(kind);

    const px = x;
    const py = y_top_down;
    state.shared().pointer_x = px;
    state.shared().pointer_y = py;
    const point = hitbox.Point{ .x = px, .y = py };

    if (is_right) {
        std.log.info("input: context menu at {d:.1},{d:.1}", .{ px, py });
        state.shared().global_is_dragging = false;
        state.shared().global_panel_dragging = false;
        window.widget_hide_snap_outline();
        state.shared().global_hover_target = .none;
        menu.widget_context_menu();
        state.requestFrame();
        return;
    }

    var new_hover_target: state.HitTarget = .grid_background;
    var pressed: ?state.ActionId = null;
    const controls_visible = state.layout.controlsVisible(state.shared().setting_show_controls) and !state.spotifyIdle();
    const progress_visible = state.layout.progressVisible(state.shared().setting_hide_progress) and !state.spotifyIdle();

    for (state.layout.buttons) |button| {
        if (controls_visible and button.bounds().contains(point)) {
            new_hover_target = state.HitTarget.fromActionId(button.id);
            break;
        }
    } else {
        const seek_bounds = hitbox.Rect{ .x = state.layout.bar_x, .y = state.layout.bar_y - state.layout.bar_hit_pad_y, .w = state.layout.bar_w, .h = state.layout.bar_h + 2 * state.layout.bar_hit_pad_y, .radius = SEEK_HIT_RADIUS };
        const art_bounds = hitbox.Rect{ .x = state.layout.art_x, .y = state.layout.art_y, .w = state.layout.art_size, .h = state.layout.art_size, .radius = ART_HIT_RADIUS };
        const frame_bounds = state.layout.card(state.shared().mode_mix);
        if (progress_visible and seek_bounds.contains(point)) {
            new_hover_target = .bar;
        } else if (art_bounds.contains(point)) {
            new_hover_target = .art;
        } else if (frame_bounds.contains(point)) {
            new_hover_target = .frame_bounds;
        }
    }

    // Track only interaction state that affects presentation; redundant pointer samples should not
    // wake the renderer when the visible hit target has not changed.
    var state_changed = false;
    if (state.shared().global_hover_target != new_hover_target) {
        state.shared().global_hover_target = new_hover_target;
        state_changed = true;
    }

    if (is_click) {
        for (state.layout.buttons) |button| {
            if (controls_visible and button.bounds().contains(point)) pressed = button.id;
        }
        if (state.shared().global_click_target != new_hover_target) {
            state.shared().global_click_target = new_hover_target;
            state_changed = true;
        }

        if (state.shared().global_duration > 0 and new_hover_target == .bar) {
            std.log.info("input: seek start at {d:.2}s", .{state.shared().global_elapsed});
            state.shared().global_is_dragging = true;
            state_changed = true;
        }

        const card_bounds = state.layout.card(state.shared().mode_mix);
        if (card_bounds.contains(point) and pressed == null and !state.shared().global_is_dragging) {
            std.log.info("input: panel drag start at {d:.1},{d:.1}", .{ px, py });
            const mouse = window.widget_mouse_location();
            state.shared().global_panel_dragging = true;
            state.shared().widget_drag_start_mouse_x = mouse.x;
            state.shared().widget_drag_start_mouse_y = mouse.y;
            state.shared().widget_drag_start_margin_left = state.shared().widget_margin_left;
            state.shared().widget_drag_start_margin_top = state.shared().widget_margin_top;
            const visual_width: f64 = @floatFromInt(@import("../platform/native.zig").wallify_width());
            window.widget_start_drag(state.shared().widget_margin_left, state.shared().widget_margin_top, visual_width);
            state_changed = true;
        }
    }

    if (state.shared().global_panel_dragging) {
        if (!is_click and !is_release) {
            const mouse = window.widget_mouse_location();
            const next_left: i32 = @max(0, state.shared().widget_drag_start_margin_left + @as(i32, @intFromFloat(@round(mouse.x - state.shared().widget_drag_start_mouse_x))));
            const next_top: i32 = @max(PANEL_DRAG_TOP_MIN, state.shared().widget_drag_start_margin_top + @as(i32, @intFromFloat(@round(state.shared().widget_drag_start_mouse_y - mouse.y))));
            if (@abs(next_left - state.shared().widget_margin_left) >= SNAP_STEP_THRESHOLD or @abs(next_top - state.shared().widget_margin_top) >= SNAP_STEP_THRESHOLD) {
                state.shared().widget_margin_left = next_left;
                state.shared().widget_margin_top = next_top;
                state.shared().panel_position_dirty = true;
            }
        }

        const visual_left: f64 = 0.0;
        const visual_top: f64 = 0.0;
        const native = @import("../platform/native.zig");
        const visual_width: f64 = @floatFromInt(native.wallify_width());
        const visual_height: f64 = @floatFromInt(native.wallify_height());

        window.widget_set_snap_debug(state.shared().mode_mix, visual_width, visual_height, true);
        const live_snap = window.widget_nearby_panel_snap(state.shared().widget_margin_left, state.shared().widget_margin_top, visual_left, visual_top, visual_width, visual_height);

        const visual_span = @max(visual_width, visual_height);
        const preview_radius: f64 = @max(180.0, visual_span * 0.45);
        const commit_radius: f64 = @max(150.0, visual_span * 0.32);
        const show_snap_preview = live_snap.found and live_snap.distance_sq <= preview_radius * preview_radius;

        if (!is_release and show_snap_preview) {
            window.widget_show_snap_outline(live_snap.outline_x, live_snap.outline_y, live_snap.outline_width, live_snap.outline_height);
        } else if (!is_release) {
            window.widget_hide_snap_outline();
        }

        if (is_release) {
            const mouse = window.widget_mouse_location();
            const idle_click = state.spotifyIdle() and @abs(mouse.x - state.shared().widget_drag_start_mouse_x) < CLICK_TOLERANCE and @abs(mouse.y - state.shared().widget_drag_start_mouse_y) < CLICK_TOLERANCE;
            if (idle_click) {
                std.log.info("input: idle click at {d:.1},{d:.1}", .{ px, py });
                if (state.shared().setting_idle_style != .spotify) state.shared().cat_pet_until = state.shared().animation_time + PET_DURATION else openIdlePlayer();
            }

            const snap_target = live_snap;
            if (!idle_click and snap_target.found and snap_target.distance_sq <= commit_radius * commit_radius) {
                std.log.info("input: snap commit {d},{d} -> {d},{d}, distance²={d:.0}", .{
                    state.shared().widget_margin_left,
                    state.shared().widget_margin_top,
                    snap_target.margin_left,
                    snap_target.margin_top,
                    snap_target.distance_sq,
                });
                state.shared().panel_snap_active = true;
                state.shared().panel_snap_elapsed = 0;
                state.shared().panel_snap_start_left = state.shared().widget_margin_left;
                state.shared().panel_snap_start_top = state.shared().widget_margin_top;
                state.shared().panel_snap_target_left = @max(0, snap_target.margin_left);
                state.shared().panel_snap_target_top = @max(PANEL_DRAG_TOP_MIN, snap_target.margin_top);
                state.shared().panel_save_after_snap = true;
            }

            state.shared().global_panel_dragging = false;
            std.log.info("input: panel drag end at {d},{d}", .{ state.shared().widget_margin_left, state.shared().widget_margin_top });
            window.widget_set_snap_debug(state.shared().mode_mix, visual_width, visual_height, false);
            window.widget_hide_snap_outline();
            if (!state.shared().panel_snap_active) state.saveWidgetSettings();
        }
        state.requestFrame();
        return;
    }

    if (state.spotifyIdle()) {
        if (is_release) {
            if (state.shared().setting_idle_style != .spotify) state.shared().cat_pet_until = state.shared().animation_time + PET_DURATION else openIdlePlayer();
        }
        return;
    }

    if (is_release and !state.shared().global_is_dragging) {
        if (state.shared().global_click_target == new_hover_target) {
            std.log.info("input: release target={s}", .{@tagName(new_hover_target)});
            if (new_hover_target.toActionId()) |action| {
                switch (action) {
                    .PlayPause => media.togglePlayback(),
                    .Prev => media.triggerCommand(.previous_track),
                    .Next => media.triggerCommand(.next_track),
                }
            }
        }
        pressed = null;
    }

    if (state.shared().global_is_dragging) {
        var x_offs: f64 = px - state.layout.bar_x;
        if (x_offs < 0.0) x_offs = 0.0;
        if (x_offs > state.layout.bar_w) x_offs = state.layout.bar_w;
        const target = state.shared().global_duration * (x_offs / state.layout.bar_w);

        if (is_release) {
            std.log.info("input: seek end at {d:.2}s", .{target});
            state.shared().global_is_dragging = false;
            state.shared().global_elapsed = target;
            state_changed = true;
            state.shared().playback_clock.sync(target, state.shared().global_rate, window.widget_monotonic_time(), state.shared().global_duration, true);
            media.triggerSeek(target);
            state.shared().global_rate_lock = RATE_LOCKED;
            state.shared().global_rate_lock_until = window.widget_monotonic_time() + RATE_LOCK_DURATION;
        } else {
            state.shared().global_elapsed = target;
            state.requestFrame();
        }
    }

    if (is_release) pressed = null;
    if (state_changed) state.requestFrame();
}

pub fn enableRawMode() !void {}
pub fn disableRawMode() void {}
pub fn inputLoop() void {}

test "right-click input is routed only to context menu handling" {
    try std.testing.expect(isContextMenuKind(POINTER_RIGHT_CLICK));
    try std.testing.expect(!isContextMenuKind(POINTER_CLICK));
    try std.testing.expect(!isContextMenuKind(POINTER_RELEASE));
}
