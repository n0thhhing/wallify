const std = @import("std");
const state = @import("../state.zig");

pub const WallifySettingsSnapshot = extern struct {
    native_glass: bool,
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
    hide_text: bool,
    hide_progress: bool,
    show_controls: bool,
    show_timestamps: bool,
    artwork_border: bool,
    compact_gradient: bool,
    artwork_radius: c_int,
    progress_thickness: c_int,
    font_scale: c_int,
    media_key_target: c_int,
    playing: bool,
    title: [512]u8,
    artist: [512]u8,
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

extern fn wallify_native_settings_snapshot(out: ?*WallifySettingsSnapshot) callconv(.c) void;
pub export fn wallify_settings_get_snapshot(out: ?*WallifySettingsSnapshot) callconv(.c) void {
    wallify_native_settings_snapshot(out);
}

extern fn wallify_native_apply_bool(key: c_int, val: bool) callconv(.c) void;
pub export fn wallify_settings_apply_bool(key: c_int, val: bool) callconv(.c) void {
    wallify_native_apply_bool(key, val);
}

extern fn wallify_native_apply_int(key: c_int, val: c_int) callconv(.c) void;
pub export fn wallify_settings_apply_int(key: c_int, val: c_int) callconv(.c) void {
    wallify_native_apply_int(key, val);
}

extern fn wallify_native_restore_defaults() callconv(.c) void;
pub export fn wallify_settings_restore_defaults() callconv(.c) void {
    wallify_native_restore_defaults();
}

extern fn wallify_native_reset_position() callconv(.c) void;
pub export fn wallify_settings_reset_position() callconv(.c) void {
    wallify_native_reset_position();
}

test "settings snapshot matches active state" {
    var snapshot: WallifySettingsSnapshot = undefined;
    wallify_settings_get_snapshot(&snapshot);
    try std.testing.expectEqual(state.shared().setting_glow, snapshot.glow);
    try std.testing.expectEqual(state.shared().setting_aurora, snapshot.aurora);
    try std.testing.expectEqual(state.shared().setting_animations, snapshot.animations);

    // Test media source mapping synchronization
    wallify_settings_apply_int(13, 2);
    try std.testing.expectEqual(state.MediaSource.spotifast, state.shared().setting_source);
    wallify_settings_get_snapshot(&snapshot);
    try std.testing.expectEqual(@as(c_int, 2), snapshot.media_source);

    // Test idle style mapping synchronization
    wallify_settings_apply_int(15, 0);
    try std.testing.expectEqual(state.IdleStyle.pixel_cat, state.shared().setting_idle_style);
    wallify_settings_get_snapshot(&snapshot);
    try std.testing.expectEqual(@as(c_int, 0), snapshot.idle_style);

    wallify_settings_apply_int(15, 1);
    try std.testing.expectEqual(state.IdleStyle.banana_cat, state.shared().setting_idle_style);
    wallify_settings_get_snapshot(&snapshot);
    try std.testing.expectEqual(@as(c_int, 1), snapshot.idle_style);

    wallify_settings_apply_int(15, 2);
    try std.testing.expectEqual(state.IdleStyle.spotify, state.shared().setting_idle_style);
    wallify_settings_get_snapshot(&snapshot);
    try std.testing.expectEqual(@as(c_int, 2), snapshot.idle_style);

    wallify_settings_apply_int(15, 3);
    try std.testing.expectEqual(state.IdleStyle.raccoon, state.shared().setting_idle_style);
    wallify_settings_get_snapshot(&snapshot);
    try std.testing.expectEqual(@as(c_int, 3), snapshot.idle_style);
}
