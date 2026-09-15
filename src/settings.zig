const std = @import("std");
const state = @import("state.zig");
const native = @import("platform/native.zig");

// Visual accentuation of the widget's border bezel. Off renders completely borderless,
// while subtle and strong tint the inner highlight edge to match high-contrast wallpapers.
pub const FrameStrength = enum(u8) {
    off = 0,
    subtle = 1,
    strong = 2,

    pub fn multiplier(self: FrameStrength) f64 {
        return switch (self) {
            .off => 0.0,
            .subtle => 1.0,
            .strong => 1.5,
        };
    }
};

// Dynamic bloom radiance cast from the artwork colors onto the underlying desktop canvas.
pub const GlowIntensity = enum(u8) {
    low = 0,
    normal = 1,
    high = 2,

    pub fn multiplier(self: GlowIntensity) f64 {
        return switch (self) {
            .low => 0.5,
            .normal => 1.0,
            .high => 1.5,
        };
    }
};

// Controls easing curve pacing and interpolation frequencies for panel expansion,
// album art cross-fades, and spring-loaded snap transitions.
pub const AnimationSpeed = enum(u8) {
    slow = 0,
    normal = 1,
    fast = 2,

    pub fn multiplier(self: AnimationSpeed) f64 {
        return switch (self) {
            .slow => 0.7,
            .normal => 1.0,
            .fast => 1.4,
        };
    }
};

// Primary telemetry source for track metadata and playback controls.
pub const MediaSource = enum(u8) {
    now_playing = 0,
    spotify = 1,
};

// Display layout form factor: Compact mimics a standard 1x1 macOS desktop widget,
// whereas Expanded extends horizontally to reveal title, artist, timeline, and transport controls.
pub const WidgetMode = enum(u8) {
    compact = 0,
    expanded = 1,
};

// Idle screen presentation rendered when media is paused or Spotify is dormant.
pub const IdleStyle = enum(u8) {
    spotify = 0,
    pixel_cat = 1,
    banana_cat = 2,
};

// Hydrates persistent user preferences from disk into active runtime state.
// The file is structured as key=value pairs for clean manual inspection and editing.
// If the preferences file does not exist or fails to open, hardcoded factory defaults
// in state.zig are preserved.
pub fn loadWidgetSettings() void {
    const path = native.wallify_settings_path();
    const fd = std.posix.openatZ(std.posix.AT.FDCWD, path, .{ .ACCMODE = .RDONLY }, 0) catch return;
    defer _ = std.posix.system.close(fd);

    var buffer: [1024]u8 = undefined;
    const n = std.posix.read(fd, &buffer) catch return;
    if (n == 0) return;

    var lines = std.mem.splitScalar(u8, buffer[0..n], '\n');
    var has_saved_margins = false;

    while (lines.next()) |raw_line| {
        const text = std.mem.trim(u8, raw_line, " \r\n");
        var pair = std.mem.splitScalar(u8, text, '=');
        const key = pair.next() orelse "";
        const value = pair.next() orelse "";
        const level = std.fmt.parseInt(u8, value, 10) catch 1;

        if (std.mem.eql(u8, key, "frame_strength")) state.setting_frame = @enumFromInt(@min(2, level));
        if (std.mem.eql(u8, key, "glow_intensity")) state.setting_intensity = @enumFromInt(@min(2, level));
        if (std.mem.eql(u8, key, "animation_speed")) state.setting_speed = @enumFromInt(@min(2, level));
        if (std.mem.eql(u8, key, "media_source")) state.setting_source = @enumFromInt(@min(1, level));
        if (std.mem.eql(u8, key, "widget_mode")) state.setting_mode = @enumFromInt(@min(1, level));
        if (std.mem.eql(u8, key, "widget_grid_x")) state.widget_grid_x = @min(state.Layout.grid_max, level);
        if (std.mem.eql(u8, key, "widget_grid_y")) state.widget_grid_y = @min(state.Layout.grid_max, level);
        if (std.mem.eql(u8, key, "widget_margin_left")) {
            state.widget_margin_left = @max(0, std.fmt.parseInt(i32, value, 10) catch state.Layout.margin_left_default);
            has_saved_margins = true;
        }
        if (std.mem.eql(u8, key, "widget_margin_top")) {
            state.widget_margin_top = @max(state.Layout.margin_top_min, std.fmt.parseInt(i32, value, 10) catch state.Layout.margin_top_default);
            has_saved_margins = true;
        }
        if (std.mem.startsWith(u8, text, "artwork_glow=")) state.setting_glow = !std.mem.endsWith(u8, text, "false");
        if (std.mem.startsWith(u8, text, "aurora=")) state.setting_aurora = !std.mem.endsWith(u8, text, "false");
        if (std.mem.startsWith(u8, text, "animations=")) state.setting_animations = !std.mem.endsWith(u8, text, "false");
        if (std.mem.startsWith(u8, text, "dim_paused_artwork=")) state.setting_dim = !std.mem.endsWith(u8, text, "false");
        if (std.mem.eql(u8, key, "idle_style")) state.setting_idle_style = @enumFromInt(@min(2, level));
        if (std.mem.startsWith(u8, text, "widget_debug=")) state.setting_debug = !std.mem.endsWith(u8, text, "false");
    }

    // Derive initial absolute screen margins from discrete grid positions if explicit
    // margin coordinates were not present in legacy configurations.
    if (!has_saved_margins) {
        state.widget_margin_left = state.Layout.margin_left_default + @as(i32, state.widget_grid_x) * @as(i32, @intFromFloat(state.Layout.grid_pitch));
        state.widget_margin_top = state.Layout.margin_top_default + @as(i32, state.widget_grid_y) * @as(i32, @intFromFloat(state.Layout.grid_pitch));
    }
}

// Atomically flushes active widget geometry, themes, and feature toggles to disk.
// Writing is performed synchronously upon menu toggle or drag release so that sudden process
// termination never loses widget layout positions.
pub fn saveWidgetSettings() void {
    var buffer: [512]u8 = undefined;
    const text = std.fmt.bufPrint(
        &buffer,
        "# Wallify widget preferences; also editable from the right-click menu.\n" ++
            "artwork_glow={s}\n" ++
            "aurora={s}\n" ++
            "animations={s}\n" ++
            "dim_paused_artwork={s}\n" ++
            "widget_debug={s}\n" ++
            "idle_style={d}\n" ++
            "frame_strength={d}\n" ++
            "glow_intensity={d}\n" ++
            "animation_speed={d}\n" ++
            "media_source={d}\n" ++
            "widget_mode={d}\n" ++
            "widget_grid_x={d}\n" ++
            "widget_grid_y={d}\n" ++
            "widget_margin_left={d}\n" ++
            "widget_margin_top={d}\n",
        .{
            if (state.setting_glow) "true" else "false",
            if (state.setting_aurora) "true" else "false",
            if (state.setting_animations) "true" else "false",
            if (state.setting_dim) "true" else "false",
            if (state.setting_debug) "true" else "false",
            @intFromEnum(state.setting_idle_style),
            @intFromEnum(state.setting_frame),
            @intFromEnum(state.setting_intensity),
            @intFromEnum(state.setting_speed),
            @intFromEnum(state.setting_source),
            @intFromEnum(state.setting_mode),
            state.widget_grid_x,
            state.widget_grid_y,
            state.widget_margin_left,
            state.widget_margin_top,
        },
    ) catch return;

    const path = native.wallify_settings_path();
    const fd = std.posix.openatZ(std.posix.AT.FDCWD, path, .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true }, 0o644) catch return;
    defer _ = std.posix.system.close(fd);
    _ = std.posix.system.write(fd, text.ptr, text.len);
}

test "FrameStrength multiplier reflects visual intensity" {
    try std.testing.expectEqual(@as(f64, 0.0), FrameStrength.off.multiplier());
    try std.testing.expectEqual(@as(f64, 1.0), FrameStrength.subtle.multiplier());
    try std.testing.expectEqual(@as(f64, 1.5), FrameStrength.strong.multiplier());
}

test "GlowIntensity multiplier scales correctly" {
    try std.testing.expectEqual(@as(f64, 0.5), GlowIntensity.low.multiplier());
    try std.testing.expectEqual(@as(f64, 1.0), GlowIntensity.normal.multiplier());
    try std.testing.expectEqual(@as(f64, 1.5), GlowIntensity.high.multiplier());
}
