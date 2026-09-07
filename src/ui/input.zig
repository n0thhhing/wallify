const std = @import("std");
const state = @import("../state.zig");
const macos = @import("../macos.zig");
const media = @import("../media/media.zig");
const hitbox = @import("hitbox.zig");

pub fn enableRawMode() !void {
    state.global_hover_state_len = 4;
    state.global_click_state_len = 4;
    @memcpy(state.global_hover_state[0..4], "None");
    @memcpy(state.global_click_state[0..4], "None");

    state.original_termios = try std.posix.tcgetattr(0);
    var raw = state.original_termios;
    raw.lflag.ICANON = false;
    raw.lflag.ECHO = false;
    // Keep Ctrl-C as an input byte so the handler below can restore Kitty's
    // mouse modes before the process exits.
    raw.lflag.ISIG = false;
    try std.posix.tcsetattr(0, .FLUSH, raw);

    std.debug.print("\x1b[?25l\x1b[?1003h\x1b[?1006h", .{});
    state.pixel_mouse = std.c.getenv("TMUX") == null and macos.widget_cell_width() > 0 and macos.widget_cell_height() > 0;
    if (state.pixel_mouse) std.debug.print("\x1b[?1016h", .{});
    std.debug.print("\x1b[2J\x1b[H", .{});
}

pub fn disableRawMode() void {
    _ = std.posix.tcsetattr(0, .FLUSH, state.original_termios) catch {};
    std.debug.print("\x1b_Ga=d,d=A\x1b\\\x1b[?1016l\x1b[?1003l\x1b[?1006l\x1b[?25h\n", .{});
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
        if (received == 0) break;
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
                            macos.widget_hide_snap_outline();
                            state.global_hover_state_len = 4;
                            @memcpy(state.global_hover_state[0..4], "None");
                            if (open_menu) macos.widget_context_menu(@intFromBool(state.global_rate > 0), @intFromBool(state.setting_glow), @intFromBool(state.setting_animations), @intFromBool(state.setting_dim), state.setting_frame, state.setting_intensity, state.setting_speed, state.setting_source, state.setting_mode);
                            state.requestFrame();
                            i = end + 1;
                            continue;
                        }
                        var new_hover_str: []const u8 = "Grid Background";

                        const point = if (state.pixel_mouse)
                            hitbox.fromPixel(cx, cy, macos.widget_cell_width() * state.layout.cells_x, macos.widget_cell_height() * state.layout.cells_y, state.layout.width, state.layout.height)
                        else
                            hitbox.fromCell(cx, cy, state.layout.width / state.layout.cells_x, state.layout.height / state.layout.cells_y);
                        const px = point.x;
                        for (state.layout.buttons) |button| {
                            if (button.bounds().contains(point)) {
                                new_hover_str = button.name;
                                break;
                            }
                        } else {
                            const seek_bounds = hitbox.Rect{ .x = state.layout.bar_x, .y = state.layout.bar_y - state.layout.bar_hit_pad_y, .w = state.layout.bar_w, .h = state.layout.bar_h + 2 * state.layout.bar_hit_pad_y, .radius = 3 };
                            const art_bounds = hitbox.Rect{ .x = state.layout.art_x, .y = state.layout.art_y, .w = state.layout.art_size, .h = state.layout.art_size, .radius = 14 };
                            const frame_bounds = hitbox.Rect{ .x = 0, .y = 0, .w = state.layout.width, .h = state.layout.height, .radius = 26 };
                            if (seek_bounds.contains(point)) {
                                new_hover_str = "Geometry: Bar";
                            } else if (art_bounds.contains(point)) {
                                new_hover_str = "Geometry: Art";
                            } else if (frame_bounds.contains(point)) {
                                new_hover_str = "Frame Bounds";
                            }
                        }

                        var state_changed = false;
                        if (!std.mem.eql(u8, new_hover_str, state.global_hover_state[0..state.global_hover_state_len])) {
                            @memcpy(state.global_hover_state[0..new_hover_str.len], new_hover_str);
                            state.global_hover_state_len = new_hover_str.len;
                            state_changed = true;
                        }

                        if (is_click) {
                            pressed = null;
                            for (state.layout.buttons) |button| {
                                if (button.bounds().contains(point)) pressed = button.id;
                            }
                            if (!std.mem.eql(u8, new_hover_str, state.global_click_state[0..state.global_click_state_len])) {
                                @memcpy(state.global_click_state[0..new_hover_str.len], new_hover_str);
                                state.global_click_state_len = new_hover_str.len;
                                state_changed = true;
                            }

                            if (state.global_duration > 0 and std.mem.eql(u8, new_hover_str, "Geometry: Bar")) {
                                state.global_is_dragging = true;
                                state_changed = true;
                            }
                            // Dragging the cover or an unused portion of the
                            // card moves the real Kitty panel in widget-sized
                            // increments. Controls and the seek bar retain
                            // their exact hitboxes.
                            if (state.desktop_mode and pressed == null and !state.global_is_dragging) {
                                const mouse = macos.widget_mouse_location();
                                state.global_panel_dragging = true;
                                state.widget_drag_start_mouse_x = mouse.x;
                                state.widget_drag_start_mouse_y = mouse.y;
                                state.widget_drag_start_margin_left = state.widget_margin_left;
                                state.widget_drag_start_margin_top = state.widget_margin_top;
                                const scale = macos.widget_scale_factor();
                                const panel_width = (macos.widget_cell_width() * state.layout.cells_x) / scale;
                                const panel_height = (macos.widget_cell_height() * state.layout.cells_y) / scale;
                                const s = panel_height / state.layout.height;
                                const visual_width = if (state.mode_mix < 0.5) state.layout.art_size * s else panel_width;
                                macos.widget_start_drag(state.widget_margin_left, state.widget_margin_top, visual_width);
                                state_changed = true;
                            }
                        }

                        if (state.global_panel_dragging) {
                            if (!is_click) {
                                const mouse = macos.widget_mouse_location();
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
                            const scale = macos.widget_scale_factor();
                            const panel_height = (macos.widget_cell_height() * state.layout.cells_y) / scale;
                            
                            const s = panel_height / state.layout.height;
                            // The black card is drawn at exactly x=0, y=35 internally.
                            const visual_left = 0.0;
                            const visual_top = 35.0 * s;
                            // Align the top-left visual edge exactly with the top-left visual edge of a native widget.
                            // On macOS Sonoma Desktop, native widgets take up the ENTIRE 180x180 slot visually (0 padding).
                            const slot_w: f64 = if (state.mode_mix < 0.5) 180.0 else 360.0;
                            const slot_h: f64 = if (state.mode_mix < 0.5) 180.0 else 180.0;
                            const native_padding = 0.0;
                            const slot_left = visual_left - native_padding;
                            const slot_top = visual_top - native_padding;

                            const live_snap = macos.widget_nearby_panel_snap(state.widget_margin_left, state.widget_margin_top, slot_left, slot_top, slot_w, slot_h);
                            if (!is_release and live_snap.found) {
                                macos.widget_show_snap_outline(live_snap.outline_x, live_snap.outline_y, live_snap.outline_width, live_snap.outline_height);
                            } else if (!is_release) {
                                macos.widget_hide_snap_outline();
                            }
                            if (is_release) {
                                const snap = live_snap;
                                if (snap.found) {
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
                                macos.widget_hide_snap_outline();
                                if (!state.panel_snap_active) state.saveWidgetSettings();
                            }
                            pressed = null;
                            state.requestFrame();
                            i = end + 1;
                            continue;
                        }

                        // Compact mode has no playback controls, but still
                        // supports the drag interaction above and its menu.
                        if (state.mode_mix < 0.5) {
                            i = end + 1;
                            continue;
                        }

                        if (is_release and !state.global_is_dragging) {
                            if (pressed == .PlayPause and std.mem.eql(u8, new_hover_str, "Action: Play/Pause")) {
                                media.togglePlayback();
                            }
                            if (pressed == .Prev and std.mem.eql(u8, new_hover_str, "Action: Previous")) media.triggerCommand(media.MRMediaRemoteCommandPreviousTrack);
                            if (pressed == .Next and std.mem.eql(u8, new_hover_str, "Action: Next")) media.triggerCommand(media.MRMediaRemoteCommandNextTrack);
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
                                state.playback_clock.sync(target, state.global_rate, macos.widget_monotonic_time(), state.global_duration, true);
                                media.triggerSeek(target);
                                state.global_rate_lock = 1;
                                state.global_rate_lock_until = macos.widget_monotonic_time() + 0.5;
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
                'n' => media.triggerCommand(media.MRMediaRemoteCommandNextTrack),
                'b' => media.triggerCommand(media.MRMediaRemoteCommandPreviousTrack),
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
