const std = @import("std");
const state = @import("state.zig");
extern fn wallify_parse_setting_enum(kind: c_int, bytes: [*]const u8, count: usize) callconv(.c) u8;
extern fn wallify_parse_config(bytes: [*]const u8, count: usize) callconv(.c) void;
extern fn wallify_load_config() callconv(.c) void;
extern fn wallify_save_config() callconv(.c) void;
extern fn wallify_render_config(bytes: [*]u8, capacity: usize) callconv(.c) isize;

pub fn parseBool(raw: []const u8) ?bool {
    const s = std.mem.trim(u8, raw, " \t\r\n");
    if (std.ascii.eqlIgnoreCase(s, "true") or std.ascii.eqlIgnoreCase(s, "1") or std.ascii.eqlIgnoreCase(s, "yes") or std.ascii.eqlIgnoreCase(s, "on")) return true;
    if (std.ascii.eqlIgnoreCase(s, "false") or std.ascii.eqlIgnoreCase(s, "0") or std.ascii.eqlIgnoreCase(s, "no") or std.ascii.eqlIgnoreCase(s, "off")) return false;
    return null;
}

pub fn parseFrameStrength(raw: []const u8) state.FrameStrength {
    return @enumFromInt(wallify_parse_setting_enum(0, raw.ptr, raw.len));
}

pub fn frameStrengthName(v: state.FrameStrength) []const u8 {
    return switch (v) {
        .off => "off",
        .subtle => "subtle",
        .strong => "strong",
    };
}

pub fn parseGlowIntensity(raw: []const u8) state.GlowIntensity {
    return @enumFromInt(wallify_parse_setting_enum(1, raw.ptr, raw.len));
}

pub fn glowIntensityName(v: state.GlowIntensity) []const u8 {
    return switch (v) {
        .low => "low",
        .normal => "normal",
        .high => "high",
    };
}

pub fn parseAnimationSpeed(raw: []const u8) state.AnimationSpeed {
    return @enumFromInt(wallify_parse_setting_enum(2, raw.ptr, raw.len));
}

pub fn animationSpeedName(v: state.AnimationSpeed) []const u8 {
    return switch (v) {
        .slow => "slow",
        .normal => "normal",
        .fast => "fast",
    };
}

pub fn parseMediaSource(raw: []const u8) state.MediaSource {
    return @enumFromInt(wallify_parse_setting_enum(3, raw.ptr, raw.len));
}

pub fn mediaSourceName(v: state.MediaSource) []const u8 {
    return switch (v) {
        .now_playing => "now_playing",
        .auto => "auto",
        .spotify => "spotify",
        .spotifast => "spotifast",
    };
}

pub fn parseWidgetMode(raw: []const u8) state.WidgetMode {
    return @enumFromInt(wallify_parse_setting_enum(4, raw.ptr, raw.len));
}

pub fn widgetModeName(v: state.WidgetMode) []const u8 {
    return switch (v) {
        .compact => "1x1",
        .two_by_one => "2x1",
        .expanded => "3x1",
        .one_by_two => "1x2",
        .two_by_two => "2x2",
    };
}

pub fn parseIdleStyle(raw: []const u8) state.IdleStyle {
    return @enumFromInt(wallify_parse_setting_enum(5, raw.ptr, raw.len));
}

pub fn idleStyleName(v: state.IdleStyle) []const u8 {
    return switch (v) {
        .spotify => "spotify",
        .pixel_cat => "cat",
        .banana_cat => "banana_cat",
        .raccoon => "raccoon",
    };
}

test "raccoon idle style parses and round trips" {
    try std.testing.expectEqual(state.IdleStyle.raccoon, parseIdleStyle("Raccoon"));
    try std.testing.expectEqual(state.IdleStyle.raccoon, parseIdleStyle("3"));
    try std.testing.expectEqual(state.IdleStyle.raccoon, parseIdleStyle(idleStyleName(.raccoon)));
}

pub fn parseTransitionStyle(raw: []const u8) state.TransitionStyle {
    return @enumFromInt(wallify_parse_setting_enum(6, raw.ptr, raw.len));
}

pub fn transitionStyleName(v: state.TransitionStyle) []const u8 {
    return switch (v) {
        .default => "default",
        .cinematic => "cinematic",
        .ripple => "ripple",
        .flip => "flip",
        .vinyl => "vinyl",
        .glitch => "glitch",
    };
}

/// Parses the contents of a configuration string into state variables.
pub fn parseConfigContent(content: []const u8) void {
    wallify_parse_config(content.ptr, content.len);
}

/// Hydrates persistent user preferences from disk into active runtime state.
pub fn loadWidgetSettings() void {
    wallify_load_config();
}

/// Formats the active configuration into an expressive, self-documenting configuration file.
pub fn renderConfigContent(buffer: []u8) ?[]const u8 {
    const count = wallify_render_config(buffer.ptr, buffer.len);
    if (count < 0) return null;
    return buffer[0..@intCast(count)];
}

/// Atomically flushes active widget geometry, themes, and feature toggles to disk.
pub fn saveWidgetSettings() void {
    wallify_save_config();
}

test "parseConfigContent handles human-readable names, comments, and sections" {
    const sample =
        \\[Appearance]
        \\# Comment line
        \\artwork_glow = false # inline comment
        \\aurora = true
        \\frame_strength = strong
        \\glow_intensity = high
        \\animation_speed = fast
        \\
        \\[Behavior]
        \\widget_mode = compact
        \\media_source = spotify
        \\idle_style = banana_cat
        \\track_transition = ripple
        \\
        \\[Position]
        \\widget_margin_left = 120
        \\widget_margin_top = 45
    ;

    parseConfigContent(sample);

    try std.testing.expectEqual(false, state.shared().setting_glow);
    try std.testing.expectEqual(true, state.shared().setting_aurora);
    try std.testing.expectEqual(state.FrameStrength.strong, state.shared().setting_frame);
    try std.testing.expectEqual(state.GlowIntensity.high, state.shared().setting_intensity);
    try std.testing.expectEqual(state.AnimationSpeed.fast, state.shared().setting_speed);
    try std.testing.expectEqual(state.WidgetMode.compact, state.shared().setting_mode);
    try std.testing.expectEqual(state.MediaSource.spotify, state.shared().setting_source);
    try std.testing.expectEqual(state.IdleStyle.banana_cat, state.shared().setting_idle_style);
    try std.testing.expectEqual(state.TransitionStyle.ripple, state.shared().setting_transition);
    try std.testing.expectEqual(@as(i32, 120), state.shared().widget_margin_left);
    try std.testing.expectEqual(@as(i32, 45), state.shared().widget_margin_top);
}

test "parseConfigContent preserves backward compatibility with integer values" {
    const legacy =
        \\artwork_glow=true
        \\frame_strength=1
        \\glow_intensity=0
        \\animation_speed=0
        \\media_source=0
        \\widget_mode=1
        \\idle_style=1
        \\track_transition=4
    ;

    parseConfigContent(legacy);

    try std.testing.expectEqual(true, state.shared().setting_glow);
    try std.testing.expectEqual(state.FrameStrength.subtle, state.shared().setting_frame);
    try std.testing.expectEqual(state.GlowIntensity.low, state.shared().setting_intensity);
    try std.testing.expectEqual(state.AnimationSpeed.slow, state.shared().setting_speed);
    try std.testing.expectEqual(state.MediaSource.now_playing, state.shared().setting_source);
    try std.testing.expectEqual(state.WidgetMode.expanded, state.shared().setting_mode);
    try std.testing.expectEqual(state.IdleStyle.pixel_cat, state.shared().setting_idle_style);
    try std.testing.expectEqual(state.TransitionStyle.vinyl, state.shared().setting_transition);
}

test "parseWidgetMode supports all five form factors" {
    const names = [_]struct {
        raw: []const u8,
        mode: state.WidgetMode,
    }{
        .{ .raw = "1x1", .mode = .compact },
        .{ .raw = "2x1", .mode = .two_by_one },
        .{ .raw = "3x1", .mode = .expanded },
        .{ .raw = "1x2", .mode = .one_by_two },
        .{ .raw = "2x2", .mode = .two_by_two },
    };

    for (names) |entry| {
        try std.testing.expectEqual(entry.mode, parseWidgetMode(entry.raw));
    }

    try std.testing.expectEqual(state.WidgetMode.expanded, parseWidgetMode("1"));
    try std.testing.expectEqualStrings("1x1", widgetModeName(.compact));
    try std.testing.expectEqualStrings("2x1", widgetModeName(.two_by_one));
    try std.testing.expectEqualStrings("3x1", widgetModeName(.expanded));
    try std.testing.expectEqualStrings("1x2", widgetModeName(.one_by_two));
    try std.testing.expectEqualStrings("2x2", widgetModeName(.two_by_two));
}

test "parseMediaSource handles spotifast and fastpotify" {
    try std.testing.expectEqual(state.MediaSource.spotifast, parseMediaSource("spotifast"));
    try std.testing.expectEqual(state.MediaSource.spotifast, parseMediaSource("Spotifast"));
    try std.testing.expectEqual(state.MediaSource.spotifast, parseMediaSource("fastpotify"));
    try std.testing.expectEqual(state.MediaSource.spotifast, parseMediaSource("2"));
    try std.testing.expectEqualStrings("spotifast", mediaSourceName(.spotifast));
}
