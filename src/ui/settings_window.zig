const std = @import("std");
const state = @import("../state.zig");
const window = @import("window.zig");
const native = @import("../platform/native.zig");

pub const WallifySettingsSnapshot = extern struct {
    glow: bool,
    aurora: bool,
    animations: bool,
    dim_paused: bool,
    debug_hud: bool,
    frame_strength: c_int,
    glow_intensity: c_int,
    animation_speed: c_int,
    media_source: c_int,
    widget_mode: c_int,
    idle_style: c_int,
    track_transition: c_int,
    margin_left: c_int,
    margin_top: c_int,
    grid_x: c_int,
    grid_y: c_int,
};

pub extern fn wallify_show_settings_window() void;
pub extern fn wallify_close_settings_window() void;
pub extern fn wallify_settings_notify_position_changed() void;

pub fn open() void {
    wallify_show_settings_window();
}

pub fn close() void {
    wallify_close_settings_window();
}

pub fn notify_position_changed() void {
    wallify_settings_notify_position_changed();
}

pub export fn wallify_settings_get_snapshot(out: ?*WallifySettingsSnapshot) callconv(.c) void {
    if (out) |s| {
        s.* = .{
            .glow = state.setting_glow,
            .aurora = state.setting_aurora,
            .animations = state.setting_animations,
            .dim_paused = state.setting_dim,
            .debug_hud = state.setting_debug,
            .frame_strength = @intFromEnum(state.setting_frame),
            .glow_intensity = @intFromEnum(state.setting_intensity),
            .animation_speed = @intFromEnum(state.setting_speed),
            .media_source = @intFromEnum(state.setting_source),
            .widget_mode = @intFromEnum(state.setting_mode),
            .idle_style = switch (state.setting_idle_style) {
                .pixel_cat => 0,
                .banana_cat => 1,
                .spotify => 2,
            },
            .track_transition = @intFromEnum(state.setting_transition),
            .margin_left = state.widget_margin_left,
            .margin_top = state.widget_margin_top,
            .grid_x = state.widget_grid_x,
            .grid_y = state.widget_grid_y,
        };
    }
}

pub export fn wallify_settings_apply_bool(key: c_int, val: bool) callconv(.c) void {
    switch (key) {
        0 => state.setting_glow = val,
        1 => state.setting_aurora = val,
        2 => state.setting_animations = val,
        3 => state.setting_dim = val,
        4 => {
            state.setting_debug = val;
            if (val) window.widget_debug_window_show() else window.widget_debug_window_hide();
        },
        else => {},
    }
    state.saveWidgetSettings();
    state.requestFrame();
}

pub export fn wallify_settings_apply_int(key: c_int, val: c_int) callconv(.c) void {
    switch (key) {
        10 => state.setting_frame = @enumFromInt(std.math.clamp(val, 0, 2)),
        11 => state.setting_intensity = @enumFromInt(std.math.clamp(val, 0, 2)),
        12 => state.setting_speed = @enumFromInt(std.math.clamp(val, 0, 2)),
        13 => state.setting_source = @enumFromInt(std.math.clamp(val, 0, 1)),
        14 => {
            const new_mode: state.WidgetMode = @enumFromInt(std.math.clamp(val, 0, 1));
            if (state.setting_mode != new_mode) {
                state.setting_mode = new_mode;
                if (new_mode == .compact) {
                    state.panel_resize_after_compact = true;
                } else {
                    state.panel_resize_after_compact = false;
                    native.resize(false);
                }
            }
        },
        15 => state.setting_idle_style = switch (val) {
            0 => .pixel_cat,
            1 => .banana_cat,
            else => .spotify,
        },
        16 => state.setting_transition = @enumFromInt(std.math.clamp(val, 0, 5)),
        else => {},
    }
    state.saveWidgetSettings();
    state.requestFrame();
}

pub export fn wallify_settings_restore_defaults() callconv(.c) void {
    state.setting_idle_style = .pixel_cat;
    state.setting_transition = .cinematic;
    state.setting_glow = true;
    state.setting_aurora = true;
    state.setting_animations = true;
    state.setting_dim = true;
    state.setting_frame = .subtle;
    state.setting_intensity = .normal;
    state.setting_speed = .normal;
    state.setting_source = .now_playing;
    state.setting_mode = .expanded;
    state.panel_resize_after_compact = false;
    native.resize(false);
    state.saveWidgetSettings();
    state.requestFrame();
}

pub export fn wallify_settings_reset_position() callconv(.c) void {
    state.widget_margin_left = state.Layout.margin_left_default;
    state.widget_margin_top = state.Layout.margin_top_default;
    state.panel_position_dirty = true;
    state.saveWidgetSettings();
    state.requestFrame();
}

test "settings snapshot matches active state" {
    var snapshot: WallifySettingsSnapshot = undefined;
    wallify_settings_get_snapshot(&snapshot);
    try std.testing.expectEqual(state.setting_glow, snapshot.glow);
    try std.testing.expectEqual(state.setting_aurora, snapshot.aurora);
    try std.testing.expectEqual(state.setting_animations, snapshot.animations);

    // Test idle style mapping synchronization
    wallify_settings_apply_int(15, 0);
    try std.testing.expectEqual(state.IdleStyle.pixel_cat, state.setting_idle_style);
    wallify_settings_get_snapshot(&snapshot);
    try std.testing.expectEqual(@as(c_int, 0), snapshot.idle_style);

    wallify_settings_apply_int(15, 1);
    try std.testing.expectEqual(state.IdleStyle.banana_cat, state.setting_idle_style);
    wallify_settings_get_snapshot(&snapshot);
    try std.testing.expectEqual(@as(c_int, 1), snapshot.idle_style);

    wallify_settings_apply_int(15, 2);
    try std.testing.expectEqual(state.IdleStyle.spotify, state.setting_idle_style);
    wallify_settings_get_snapshot(&snapshot);
    try std.testing.expectEqual(@as(c_int, 2), snapshot.idle_style);
}
