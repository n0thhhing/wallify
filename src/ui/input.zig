const std = @import("std");
const state = @import("../state.zig");
const window = @import("window.zig");
const menu = @import("menu.zig");
const spotify = @import("../media/spotify.zig");
const media = @import("../media/controller.zig");
const hitbox = @import("hitbox.zig");

pub fn enableRawMode() !void {
    state.global_hover_target = .none;
    state.global_click_target = .none;

    state.original_termios = try std.posix.tcgetattr(0);
    var raw = state.original_termios;
    raw.lflag.ICANON = false;
    raw.lflag.ECHO = false;
    // Keep Ctrl-C as an input byte so the handler below can restore Kitty's
    // mouse modes before the process exits.
    raw.lflag.ISIG = false;
    try std.posix.tcsetattr(0, .FLUSH, raw);

    std.debug.print("\x1b[?25l\x1b[?1003h\x1b[?1006h", .{});
    state.pixel_mouse = std.c.getenv("TMUX") == null and window.widget_cell_width() > 0 and window.widget_cell_height() > 0;
    if (state.pixel_mouse) std.debug.print("\x1b[?1016h", .{});
    std.debug.print("\x1b[2J\x1b[H", .{});
}

pub fn disableRawMode() void {
    _ = std.posix.tcsetattr(0, .NOW, state.original_termios) catch {};
    const reset_seq = "\x1b_Ga=d,d=A\x1b\\\x1b[?1016l\x1b[?1003l\x1b[?1006l\x1b[?25h\n";
    _ = std.c.write(1, reset_seq, reset_seq.len);
}

pub fn inputLoop() void {
    var buf: [256]u8 = undefined;
    var pressed: ?state.ActionId = null;
    var right_pressed = false;
    var pending: usize = 0;
    var control_string = false;
    var control_escape = false;
    while (true) {
        const received = std.posix.read(0, buf[pending..]) catch 0;
        if (received == 0) {
            disableRawMode();
            std.process.exit(0);
        }
        const n = pending + received;

        var i: usize = 0;
        while (i < n) {
            if (control_string) {
                if (buf[i] == 7 or (control_escape and buf[i] == '\\')) control_string = false;
                control_escape = buf[i] == 27;
                i += 1;
                continue;
            }
            if (buf[i] == 27 and i + 1 < n and (buf[i + 1] == '_' or buf[i + 1] == ']' or buf[i + 1] == 'P')) {
                control_string = true;
                control_escape = false;
                i += 2;
                continue;
            }
            if (buf[i] == '\x1b' and n - i < 3) break;
            if (i + 2 < n and buf[i] == '\x1b' and buf[i + 1] == '[') {
                if (buf[i + 2] == '<') {
                    var end = i + 3;
                    while (end < n and buf[end] != 'M' and buf[end] != 'm') : (end += 1) {}
                    if (end == n) break;
                    if (end < n) {
                        const evt = buf[end];
                        const span = buf[i + 3 .. end];
                        var iter = std.mem.splitScalar(u8, span, ';');
                        const cb_str = iter.next() orelse "";
                        const cx_str = iter.next() orelse "";
                        const cy_str = iter.next() orelse "";

                        const cb = std.fmt.parseInt(u32, cb_str, 10) catch 999;
                        const cx = std.fmt.parseInt(u32, cx_str, 10) catch 0;
                        const cy = std.fmt.parseInt(u32, cy_str, 10) catch 0;

                        const is_click = (cb & (3 | 32 | 64 | 128)) == 0 and evt == 'M';
                        const is_release = (cb & 3) == 0 and evt == 'm';

                        if ((cb & (3 | 32 | 64 | 128)) == 2) {
                            const open_menu = evt == 'm' and right_pressed;
                            right_pressed = evt == 'M';
                            pressed = null;
                            state.global_is_dragging = false;
                            state.global_panel_dragging = false;
                            window.widget_hide_snap_outline();
                            state.global_hover_target = .none;
                            if (open_menu) menu.widget_context_menu(@intFromBool(state.global_rate > 0), @intFromBool(state.setting_glow), @intFromBool(state.setting_animations), @intFromBool(state.setting_dim), state.setting_frame, state.setting_intensity, state.setting_speed, state.setting_source, state.setting_mode);
                            state.requestFrame();
                            i = end + 1;
                            continue;
                        }
                        var new_hover_target: state.HitTarget = .grid_background;

                        const point = if (state.pixel_mouse)
                            hitbox.fromPixel(cx, cy, window.widget_cell_width() * state.layout.cells_x, window.widget_cell_height() * state.layout.cells_y, state.layout.width, state.layout.height)
                        else
                            hitbox.fromCell(cx, cy, state.layout.width / state.layout.cells_x, state.layout.height / state.layout.cells_y);
                        const px = point.x;
                        state.pointer_x = px;
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
                            pressed = null;
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
                            // Dragging the cover or an unused portion of the
                            // card moves the real Kitty panel in widget-sized
                            // increments. Controls and the seek bar retain
                            // their exact hitboxes.
                            // The canvas contains a 35pt transparent top inset
                            // and extra terminal surface below the card. Only
                            // the rendered widget itself may initiate a drag.
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
                            if (!is_click) {
                                const mouse = window.widget_mouse_location();
                                const next_left: i32 = @max(0, state.widget_drag_start_margin_left + @as(i32, @intFromFloat(@round(mouse.x - state.widget_drag_start_mouse_x))));
                                // A negative surface margin compensates for
                                // the card's internal top inset, letting its
                                // visible edge reach the same height as other
                                // desktop widgets.
                                const next_top: i32 = @max(-180, state.widget_drag_start_margin_top + @as(i32, @intFromFloat(@round(state.widget_drag_start_mouse_y - mouse.y))));
                                // Only send a remote resize once the surface
                                // would visibly move. Global mouse coordinates
                                // remain stable when Kitty repositions it.
                                if (@abs(next_left - state.widget_margin_left) >= 8 or @abs(next_top - state.widget_margin_top) >= 8) {
                                    state.widget_margin_left = next_left;
                                    state.widget_margin_top = next_top;
                                    state.panel_position_dirty = true;
                                }
                            }
                            // The Kitty panel margins and CGWindowList frames
                            // are both desktop points. The card starts at the
                            // surface origin horizontally and 35 points down.
                            const visual_left: f64 = if (state.mode_mix < 0.5) 8.0 else 0.0;
                            const visual_top = 35.0;
                            // Match the card width actually painted after a
                            // Kitty resize, rather than a stale fixed width.
                            const visual_width: f64 = if (state.mode_mix < 0.5) 164.0 else 531.0;
                            const visual_height: f64 = 164.0;
                            window.widget_set_snap_debug(state.mode_mix, visual_width, visual_height, true);
                            const live_snap = window.widget_nearby_panel_snap(state.widget_margin_left, state.widget_margin_top, visual_left, visual_top, visual_width, visual_height);
                            // A guide is useful only while the card is still
                            // approaching its destination. Once it reaches the
                            // exact snap rect, the card itself would cover it.
                            const preview_radius: f64 = if (state.mode_mix < 0.5) 180.0 else 240.0;
                            const commit_radius: f64 = if (state.mode_mix < 0.5) 150.0 else 190.0;
                            const show_snap_preview = live_snap.found and live_snap.distance_sq <= preview_radius * preview_radius;
                            if (!is_release and show_snap_preview) {
                                window.widget_show_snap_outline(live_snap.outline_x, live_snap.outline_y, live_snap.outline_width, live_snap.outline_height);
                            } else if (!is_release) {
                                window.widget_hide_snap_outline();
                            }
                            if (is_release) {
                                const mouse = window.widget_mouse_location();
                                const idle_click = state.spotifyIdle() and @abs(mouse.x - state.widget_drag_start_mouse_x) < 5 and @abs(mouse.y - state.widget_drag_start_mouse_y) < 5;
                                if (idle_click) {
                                    if (state.setting_idle_style != .spotify) state.cat_pet_until = state.animation_time + 2.5 else spotify.widget_open_spotify();
                                }
                                const snap = live_snap;
                                if (!idle_click and snap.found and snap.distance_sq <= commit_radius * commit_radius) {
                                    state.panel_snap_active = true;
                                    state.panel_snap_elapsed = 0;
                                    state.panel_snap_start_left = state.widget_margin_left;
                                    state.panel_snap_start_top = state.widget_margin_top;
                                    state.panel_snap_target_left = @max(0, snap.margin_left);
                                    state.panel_snap_target_top = @max(-180, snap.margin_top);
                                    state.panel_save_after_snap = true;
                                }
                                // Keep the exact drop point. macOS widgets are
                                // free-positioned; the optional snap above is
                                // only activated near a real neighboring card.
                                state.global_panel_dragging = false;
                                window.widget_set_snap_debug(state.mode_mix, visual_width, visual_height, false);
                                window.widget_hide_snap_outline();
                                if (!state.panel_snap_active) state.saveWidgetSettings();
                            }
                            pressed = null;
                            state.requestFrame();
                            i = end + 1;
                            continue;
                        }

                        // Compact mode has no playback controls, but still
                        // supports the drag interaction above and its menu.
                        if (state.spotifyIdle()) {
                            if (is_release) {
                                if (state.setting_idle_style != .spotify) state.cat_pet_until = state.animation_time + 2.5 else spotify.widget_open_spotify();
                            }
                            i = end + 1;
                            continue;
                        }
                        if (state.mode_mix < 0.5) {
                            i = end + 1;
                            continue;
                        }

                        if (is_release and !state.global_is_dragging) {
                            if (pressed) |action| {
                                if (new_hover_target.toActionId() == action) {
                                    switch (action) {
                                        .PlayPause => media.togglePlayback(),
                                        .Prev => media.triggerCommand(.previous_track),
                                        .Next => media.triggerCommand(.next_track),
                                    }
                                }
                            }
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

                        if (is_release) pressed = null;
                        if (state_changed) {
                            state.requestFrame();
                        }

                        i = end + 1;
                        continue;
                    }
                }
                var end = i + 2;
                while (end < n and (buf[end] < 0x40 or buf[end] > 0x7e)) : (end += 1) {}
                if (end == n) break;
                i = end + 1;
                continue;
            }

            switch (buf[i]) {
                'p', ' ' => media.togglePlayback(),
                'n' => media.triggerCommand(.next_track),
                'b' => media.triggerCommand(.previous_track),
                'q', 3 => {
                    disableRawMode();
                    std.process.exit(0);
                },
                else => {},
            }
            i += 1;
        }
        pending = n - i;
        if (pending == buf.len) {
            pending = 0;
        } else if (pending > 0) {
            std.mem.copyForwards(u8, buf[0..pending], buf[i..n]);
        }
    }
}
