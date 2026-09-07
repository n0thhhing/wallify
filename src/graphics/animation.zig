const std = @import("std");
const state = @import("../state.zig");
const macos = @import("../macos.zig");
const render = @import("render.zig");
const media = @import("../media/media.zig");
const icon_transition = @import("icon_transition.zig");

extern "c" fn usleep(useconds: c_uint) c_int;
extern "c" fn system(command: [*:0]const u8) c_int;

fn resizePanel(compact: bool) void {
    // `resize-os-window --action=os-panel` is Kitty's supported live panel
    // resize API. It preserves this terminal process and its animation state.
    const command = if (compact)
        "/Applications/kitty.app/Contents/MacOS/kitten @ --to unix:/tmp/wallify-kitty.sock resize-os-window --action=os-panel --incremental columns=174px lines=232px"
    else
        "/Applications/kitty.app/Contents/MacOS/kitten @ --to unix:/tmp/wallify-kitty.sock resize-os-window --action=os-panel --incremental columns=708px lines=205px";
    _ = system(command);
}

fn movePanelToWidgetGrid() void {
    // Kitty documents live panel placement through resize-os-window with the
    // os-panel action.  This moves the actual surface, so transparent pixels
    // never become a second, invisible input window.
    var command: [320]u8 = undefined;
    const margin_left = state.widget_margin_left;
    const margin_top = state.widget_margin_top;
    const text = std.fmt.bufPrintZ(&command,
        "/Applications/kitty.app/Contents/MacOS/kitten @ --to unix:/tmp/wallify-kitty.sock resize-os-window --no-response --action=os-panel --incremental margin-left={d}px margin-top={d}px",
        .{ margin_left, margin_top }) catch return;
    _ = system(text.ptr);
}

pub fn animationLoop() void {
    var previous_columns = macos.widget_terminal_columns();
    var previous_time = macos.widget_monotonic_time();
    while (true) {
        const columns = macos.widget_terminal_columns();
        var needs_draw = state.frame_requested.swap(false, .acq_rel) or columns != previous_columns;
        previous_columns = columns;
        const now = macos.widget_monotonic_time();
        if (state.animation_time < state.art_transition_until) needs_draw = true;
        const menu_action = macos.widget_context_menu_action();
        switch (menu_action) {
            1 => media.togglePlayback(),
            2 => media.triggerCommand(media.MRMediaRemoteCommandPreviousTrack),
            3 => media.triggerCommand(media.MRMediaRemoteCommandNextTrack),
            4 => macos.widget_open_spotify(),
            5 => state.setting_glow = !state.setting_glow,
            6 => state.setting_animations = !state.setting_animations,
            7 => state.setting_dim = !state.setting_dim,
            10...12 => state.setting_frame = @intCast(menu_action - 10),
            20...22 => state.setting_intensity = @intCast(menu_action - 20),
            30...32 => state.setting_speed = @intCast(menu_action - 30),
            40 => {
                state.setting_glow = true; state.setting_animations = true; state.setting_dim = true;
                state.setting_frame = 1; state.setting_intensity = 1; state.setting_speed = 1;
                state.setting_source = 0;
                state.setting_mode = 1;
            },
            50...51 => state.setting_source = @intCast(menu_action - 50),
            60...61 => {
                const selected: u8 = @intCast(menu_action - 60);
                if (state.desktop_mode and selected == 1 and state.mode_mix < 0.5) resizePanel(false);
                state.panel_resize_after_compact = state.desktop_mode and selected == 0 and state.mode_mix >= 0.5;
                state.setting_mode = selected;
            },
            else => {},
        }
        if (menu_action != 0) {
            if (menu_action >= 5) state.saveWidgetSettings();
            needs_draw = true;
        }
        if (!state.setting_animations) {
            state.play_pause_mix = if (state.global_rate > 0) 1 else 0;
            state.global_anim_art_t = state.play_pause_mix;
            state.art_transition_until = 0;
            state.seek_expansion = if (state.global_is_dragging) 1 else 0;
            state.seek_velocity = 0;
        }

        const dt = @min(0.1, @max(0, now - previous_time)) * ([_]f64{ 0.7, 1, 1.4 })[state.setting_speed];
        state.animation_time += dt;
        const target_mode: f64 = @floatFromInt(state.setting_mode);
        if (@abs(state.mode_mix - target_mode) > 0.001) {
            // Smooth, critically damped-feeling mode morph without a visible jump.
            state.mode_mix += (target_mode - state.mode_mix) * @min(1, dt * 8);
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
            const t = @min(1.0, state.panel_snap_elapsed / 0.22);
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
        if (state.mode_mix < 0.99 and state.global_title_len > 0) {
            const scale: f64 = @floatFromInt(state.render_scale);
            const title_width = macos.widget_text_width(state.global_title[0..].ptr, state.global_title_len, 15 * state.render_scale, 1) / scale;
            if (title_width > 126) {
                const travel = title_width - 126;
                state.marquee_offset += dt * 28 * state.marquee_direction;
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
            needs_draw = true;
        } else {
            state.marquee_offset = 0;
            state.marquee_direction = 1;
        }
        previous_time = now;
        const seek_target: f64 = if (state.global_is_dragging) 1 else 0;
        if (@abs(state.seek_expansion - seek_target) > 0.0001 or @abs(state.seek_velocity) > 0.001) {
            const step = @min(dt, 1.0 / 60.0);
            state.seek_velocity += (322.27 * (seek_target - state.seek_expansion) - 25.13 * state.seek_velocity) * step;
            state.seek_expansion += state.seek_velocity * step;
            needs_draw = true;
        }
        if (state.global_rate > 0 and !state.global_is_dragging) needs_draw = true;
        const icon_target: f64 = if (state.global_rate > 0) 1 else 0;
        if (state.play_pause_mix != icon_target) {
            state.play_pause_mix = icon_transition.advance(state.play_pause_mix, state.global_rate > 0, dt);
            needs_draw = true;
        }
        for (state.layout.buttons, 0..) |button, index| {
            const target: f64 = if (std.mem.eql(u8, button.name, state.global_hover_state[0..state.global_hover_state_len])) 1 else 0;
            if (@abs(state.hover_amount[index] - target) > 0.001) {
                state.hover_amount[index] += (target - state.hover_amount[index]) * (if (state.setting_animations) @min(1, dt * 10) else 1);
                needs_draw = true;
            }
        }
        if (state.global_rate > 0.0) {
            if (state.global_anim_art_t < 1.0) {
                state.global_anim_art_t += dt / 0.3;
                if (state.global_anim_art_t > 1.0) state.global_anim_art_t = 1.0;
                needs_draw = true;
            }
        } else {
            if (state.global_anim_art_t > 0.0) {
                state.global_anim_art_t -= dt / 0.3;
                if (state.global_anim_art_t < 0.0) state.global_anim_art_t = 0.0;
                needs_draw = true;
            }
        }

        if (needs_draw) {
            render.drawUIFrame();
            const remaining = (1.0 / 60.0) - (macos.widget_monotonic_time() - now);
            if (remaining > 0) _ = usleep(@intFromFloat(remaining * 1_000_000));
        } else {
            _ = usleep(20_000); 
        }
    }
}
