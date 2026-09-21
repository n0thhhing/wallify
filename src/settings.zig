const std = @import("std");
const state = @import("state.zig");
const native = @import("platform/native.zig");

pub fn parseBool(raw: []const u8) ?bool {
    const s = std.mem.trim(u8, raw, " \t\r\n");
    if (std.ascii.eqlIgnoreCase(s, "true") or std.ascii.eqlIgnoreCase(s, "1") or std.ascii.eqlIgnoreCase(s, "yes") or std.ascii.eqlIgnoreCase(s, "on")) return true;
    if (std.ascii.eqlIgnoreCase(s, "false") or std.ascii.eqlIgnoreCase(s, "0") or std.ascii.eqlIgnoreCase(s, "no") or std.ascii.eqlIgnoreCase(s, "off")) return false;
    return null;
}

pub fn parseFrameStrength(raw: []const u8) state.FrameStrength {
    const s = std.mem.trim(u8, raw, " \t\r\n");
    if (std.ascii.eqlIgnoreCase(s, "off") or std.mem.eql(u8, s, "0")) return .off;
    if (std.ascii.eqlIgnoreCase(s, "subtle") or std.mem.eql(u8, s, "1")) return .subtle;
    if (std.ascii.eqlIgnoreCase(s, "strong") or std.mem.eql(u8, s, "2")) return .strong;
    return .subtle;
}

pub fn frameStrengthName(v: state.FrameStrength) []const u8 {
    return switch (v) {
        .off => "off",
        .subtle => "subtle",
        .strong => "strong",
    };
}

pub fn parseGlowIntensity(raw: []const u8) state.GlowIntensity {
    const s = std.mem.trim(u8, raw, " \t\r\n");
    if (std.ascii.eqlIgnoreCase(s, "low") or std.mem.eql(u8, s, "0")) return .low;
    if (std.ascii.eqlIgnoreCase(s, "normal") or std.mem.eql(u8, s, "1")) return .normal;
    if (std.ascii.eqlIgnoreCase(s, "high") or std.mem.eql(u8, s, "2")) return .high;
    return .normal;
}

pub fn glowIntensityName(v: state.GlowIntensity) []const u8 {
    return switch (v) {
        .low => "low",
        .normal => "normal",
        .high => "high",
    };
}

pub fn parseAnimationSpeed(raw: []const u8) state.AnimationSpeed {
    const s = std.mem.trim(u8, raw, " \t\r\n");
    if (std.ascii.eqlIgnoreCase(s, "slow") or std.mem.eql(u8, s, "0")) return .slow;
    if (std.ascii.eqlIgnoreCase(s, "normal") or std.mem.eql(u8, s, "1")) return .normal;
    if (std.ascii.eqlIgnoreCase(s, "fast") or std.mem.eql(u8, s, "2")) return .fast;
    return .normal;
}

pub fn animationSpeedName(v: state.AnimationSpeed) []const u8 {
    return switch (v) {
        .slow => "slow",
        .normal => "normal",
        .fast => "fast",
    };
}

pub fn parseMediaSource(raw: []const u8) state.MediaSource {
    const s = std.mem.trim(u8, raw, " \t\r\n");
    if (std.ascii.eqlIgnoreCase(s, "now_playing") or std.ascii.eqlIgnoreCase(s, "system") or std.mem.eql(u8, s, "0")) return .now_playing;
    if (std.ascii.eqlIgnoreCase(s, "spotify") or std.mem.eql(u8, s, "1")) return .spotify;
    if (std.ascii.eqlIgnoreCase(s, "spotifast") or std.ascii.eqlIgnoreCase(s, "fastpotify") or std.mem.eql(u8, s, "2")) return .spotifast;
    if (std.ascii.eqlIgnoreCase(s, "auto") or std.mem.eql(u8, s, "3")) return .auto;
    return .now_playing;
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
    const s = std.mem.trim(u8, raw, " \t\r\n");
    if (std.ascii.eqlIgnoreCase(s, "compact") or
        std.ascii.eqlIgnoreCase(s, "1x1") or
        std.mem.eql(u8, s, "0")) return .compact;

    // "expanded" was the old 3×1 default, so keep it and legacy numeric 1 working.
    if (std.ascii.eqlIgnoreCase(s, "two_by_one") or
        std.ascii.eqlIgnoreCase(s, "2x1") or
        std.ascii.eqlIgnoreCase(s, "medium")) return .two_by_one;

    if (std.ascii.eqlIgnoreCase(s, "expanded") or
        std.ascii.eqlIgnoreCase(s, "three_by_one") or
        std.ascii.eqlIgnoreCase(s, "3x1") or
        std.ascii.eqlIgnoreCase(s, "wide") or
        std.mem.eql(u8, s, "1") or
        std.mem.eql(u8, s, "2")) return .expanded;

    if (std.ascii.eqlIgnoreCase(s, "one_by_two") or
        std.ascii.eqlIgnoreCase(s, "1x2") or
        std.mem.eql(u8, s, "3")) return .one_by_two;

    if (std.ascii.eqlIgnoreCase(s, "two_by_two") or
        std.ascii.eqlIgnoreCase(s, "2x2") or
        std.mem.eql(u8, s, "4")) return .two_by_two;

    return .expanded;
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
    const s = std.mem.trim(u8, raw, " \t\r\n");
    if (std.ascii.eqlIgnoreCase(s, "spotify") or std.mem.eql(u8, s, "0")) return .spotify;
    if (std.ascii.eqlIgnoreCase(s, "cat") or std.ascii.eqlIgnoreCase(s, "pixel_cat") or std.mem.eql(u8, s, "1")) return .pixel_cat;
    if (std.ascii.eqlIgnoreCase(s, "banana_cat") or std.ascii.eqlIgnoreCase(s, "banana") or std.mem.eql(u8, s, "2")) return .banana_cat;
    if (std.ascii.eqlIgnoreCase(s, "raccoon") or std.mem.eql(u8, s, "3")) return .raccoon;
    return .pixel_cat;
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
    const s = std.mem.trim(u8, raw, " \t\r\n");
    if (std.ascii.eqlIgnoreCase(s, "default") or std.mem.eql(u8, s, "0")) return .default;
    if (std.ascii.eqlIgnoreCase(s, "cinematic") or std.mem.eql(u8, s, "1")) return .cinematic;
    if (std.ascii.eqlIgnoreCase(s, "ripple") or std.ascii.eqlIgnoreCase(s, "liquid_ripple") or std.mem.eql(u8, s, "2")) return .ripple;
    if (std.ascii.eqlIgnoreCase(s, "flip") or std.ascii.eqlIgnoreCase(s, "card_flip") or std.mem.eql(u8, s, "3")) return .flip;
    if (std.ascii.eqlIgnoreCase(s, "vinyl") or std.ascii.eqlIgnoreCase(s, "vinyl_spin") or std.mem.eql(u8, s, "4")) return .vinyl;
    if (std.ascii.eqlIgnoreCase(s, "glitch") or std.ascii.eqlIgnoreCase(s, "cyber_glitch") or std.mem.eql(u8, s, "5")) return .glitch;
    return .cinematic;
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
    var lines = std.mem.splitScalar(u8, content, '\n');
    var has_saved_margins = false;

    while (lines.next()) |raw_line| {
        // Strip comments starting with '#' or ';'
        var line = raw_line;
        if (std.mem.indexOfAny(u8, line, "#;")) |comment_idx| {
            line = line[0..comment_idx];
        }
        const text = std.mem.trim(u8, line, " \t\r\n");
        if (text.len == 0 or text[0] == '[') continue;

        var pair = std.mem.splitScalar(u8, text, '=');
        const raw_key = pair.next() orelse continue;
        const raw_val = pair.next() orelse continue;

        const key = std.mem.trim(u8, raw_key, " \t\r\n");
        const val = std.mem.trim(u8, raw_val, " \t\r\n");

        if (std.ascii.eqlIgnoreCase(key, "artwork_glow")) {
            if (parseBool(val)) |b| state.setting_glow = b;
        } else if (std.ascii.eqlIgnoreCase(key, "native_glass")) {
            if (parseBool(val)) |b| state.setting_native_glass = b;
        } else if (std.ascii.eqlIgnoreCase(key, "aurora")) {
            if (parseBool(val)) |b| state.setting_aurora = b;
        } else if (std.ascii.eqlIgnoreCase(key, "animations")) {
            if (parseBool(val)) |b| state.setting_animations = b;
        } else if (std.ascii.eqlIgnoreCase(key, "dim_paused_artwork")) {
            if (parseBool(val)) |b| state.setting_dim = b;
        } else if (std.ascii.eqlIgnoreCase(key, "widget_debug")) {
            if (parseBool(val)) |b| state.setting_debug = b;
        } else if (std.ascii.eqlIgnoreCase(key, "frame_strength")) {
            state.setting_frame = parseFrameStrength(val);
        } else if (std.ascii.eqlIgnoreCase(key, "glow_intensity")) {
            state.setting_intensity = parseGlowIntensity(val);
        } else if (std.ascii.eqlIgnoreCase(key, "animation_speed")) {
            state.setting_speed = parseAnimationSpeed(val);
        } else if (std.ascii.eqlIgnoreCase(key, "media_source")) {
            state.setting_source = parseMediaSource(val);
        } else if (std.ascii.eqlIgnoreCase(key, "widget_mode")) {
            state.setting_mode = parseWidgetMode(val);
        } else if (std.ascii.eqlIgnoreCase(key, "idle_style")) {
            state.setting_idle_style = parseIdleStyle(val);
        } else if (std.ascii.eqlIgnoreCase(key, "track_transition")) {
            state.setting_transition = parseTransitionStyle(val);
        } else if (std.ascii.eqlIgnoreCase(key, "hide_text")) {
            if (parseBool(val)) |b| state.setting_hide_text = b;
        } else if (std.ascii.eqlIgnoreCase(key, "hide_progress")) {
            if (parseBool(val)) |b| state.setting_hide_progress = b;
        } else if (std.ascii.eqlIgnoreCase(key, "show_controls")) {
            if (parseBool(val)) |b| state.setting_show_controls = b;
        } else if (std.ascii.eqlIgnoreCase(key, "show_timestamps")) {
            if (parseBool(val)) |b| state.setting_show_timestamps = b;
        } else if (std.ascii.eqlIgnoreCase(key, "artwork_border")) {
            if (parseBool(val)) |b| state.setting_artwork_border = b;
        } else if (std.ascii.eqlIgnoreCase(key, "compact_gradient")) {
            if (parseBool(val)) |b| state.setting_compact_gradient = b;
        } else if (std.ascii.eqlIgnoreCase(key, "font_scale")) {
            state.setting_font_scale = if (std.ascii.eqlIgnoreCase(val, "small"))
                .small
            else if (std.ascii.eqlIgnoreCase(val, "large"))
                .large
            else
                .normal;
        } else if (std.ascii.eqlIgnoreCase(key, "artwork_radius")) {
            state.setting_artwork_radius = @enumFromInt(@min(2, std.fmt.parseInt(u8, val, 10) catch 1));
        } else if (std.ascii.eqlIgnoreCase(key, "progress_thickness")) {
            state.setting_progress_thickness = @enumFromInt(@min(2, std.fmt.parseInt(u8, val, 10) catch 1));
        } else if (std.ascii.eqlIgnoreCase(key, "media_key_target")) {
            state.setting_media_key_target = if (std.ascii.eqlIgnoreCase(val, "active"))
                .active
            else if (std.ascii.eqlIgnoreCase(val, "spotify"))
                .spotify
            else if (std.ascii.eqlIgnoreCase(val, "spotifast"))
                .spotifast
            else
                .off;
        } else if (std.ascii.eqlIgnoreCase(key, "widget_grid_x")) {
            if (std.fmt.parseInt(u8, val, 10)) |num| {
                state.widget_grid_x = @min(state.Layout.grid_max, num);
            } else |_| {}
        } else if (std.ascii.eqlIgnoreCase(key, "widget_grid_y")) {
            if (std.fmt.parseInt(u8, val, 10)) |num| {
                state.widget_grid_y = @min(state.Layout.grid_max, num);
            } else |_| {}
        } else if (std.ascii.eqlIgnoreCase(key, "widget_margin_left")) {
            if (std.fmt.parseInt(i32, val, 10)) |num| {
                state.widget_margin_left = @max(0, num);
                has_saved_margins = true;
            } else |_| {}
        } else if (std.ascii.eqlIgnoreCase(key, "widget_margin_top")) {
            if (std.fmt.parseInt(i32, val, 10)) |num| {
                state.widget_margin_top = @max(state.Layout.margin_top_min, num);
                has_saved_margins = true;
            } else |_| {}
        }
    }

    if (!has_saved_margins) {
        state.widget_margin_left = state.Layout.margin_left_default + @as(i32, state.widget_grid_x) * @as(i32, @intFromFloat(state.Layout.grid_pitch));
        state.widget_margin_top = state.Layout.margin_top_default + @as(i32, state.widget_grid_y) * @as(i32, @intFromFloat(state.Layout.grid_pitch));
    }
}

/// Hydrates persistent user preferences from disk into active runtime state.
pub fn loadWidgetSettings() void {
    const path = native.wallify_settings_path();
    const fd = std.posix.openatZ(std.posix.AT.FDCWD, path, .{ .ACCMODE = .RDONLY }, 0) catch return;
    defer _ = std.posix.system.close(fd);

    var buffer: [4096]u8 = undefined;
    const n = std.posix.read(fd, &buffer) catch return;
    if (n == 0) return;

    parseConfigContent(buffer[0..n]);
    std.log.info("settings: loaded {d} bytes from {s}", .{ n, path });
}

/// Formats the active configuration into an expressive, self-documenting configuration file.
pub fn renderConfigContent(buffer: []u8) ?[]const u8 {
    return std.fmt.bufPrint(
        buffer,
        \\# ==============================================================================
        \\# Wallify Configuration
        \\#
        \\# Preferences take effect immediately on reload or when Wallify launches.
        \\# Settings can also be adjusted via the right-click desktop context menu.
        \\# ==============================================================================
        \\
        \\[Appearance]
        \\# Ambient glow radiating from album artwork colors [true, false]
        \\artwork_glow = {s}
        \\native_glass = {s}
        \\
        \\# Multi-stop dynamic aurora gradient behind the widget [true, false]
        \\aurora = {s}
        \\
        \\# Fluid UI animations for transitions and controls [true, false]
        \\animations = {s}
        \\
        \\# Dim album artwork when playback is paused [true, false]
        \\dim_paused_artwork = {s}
        \\
        \\# Inner border bezel accentuation [off, subtle, strong]
        \\frame_strength = {s}
        \\
        \\# Ambient glow radiance [low, normal, high]
        \\glow_intensity = {s}
        \\
        \\# Animation pacing and interpolation speed [slow, normal, fast]
        \\animation_speed = {s}
        \\
        \\[Behavior]
        \\# Form factor [1x1, 2x1, 3x1, 1x2, 2x2]
        \\widget_mode = {s}
        \\
        \\# Metadata telemetry source [now_playing, spotify, spotifast]
        \\media_source = {s}
        \\
        \\# Mascot shown when player is inactive [cat, banana_cat, raccoon, spotify]
        \\idle_style = {s}
        \\
        \\# Artwork transition on track changes [cinematic, ripple, flip, vinyl, glitch, default]
        \\track_transition = {s}
        \\
        \\# Hide track title and artist text [true, false]
        \\hide_text = {s}
        \\
        \\# Hide progress/scrubber bar [true, false]
        \\hide_progress = {s}
        \\
        \\# Show playback controls [true, false]
        \\show_controls = {s}
        \\
        \\# Show elapsed and duration timestamps [true, false]
        \\show_timestamps = {s}
        \\
        \\# Show a subtle border around artwork [true, false]
        \\artwork_border = {s}
        \\
        \\# Show compact-mode gradient underlay [true, false]
        \\compact_gradient = {s}
        \\
        \\# Artwork corner radius [0, 1, 2]
        \\artwork_radius = {d}
        \\
        \\# Progress bar thickness [0, 1, 2]
        \\progress_thickness = {d}
        \\
        \\# Font size scale [small, normal, large]
        \\font_scale = {s}
        \\
        \\# Hardware media key redirect [off, active, spotify, spotifast]
        \\media_key_target = {s}
        \\
        \\[Position]
        \\# Screen coordinates in points (from top-left of display below menu bar)
        \\widget_margin_left = {d}
        \\widget_margin_top = {d}
        \\
        \\# Snap tile coordinates on the 180pt macOS desktop widget grid
        \\widget_grid_x = {d}
        \\widget_grid_y = {d}
        \\
        \\[Debug]
        \\# Show developer diagnostics overlay window [true, false]
        \\widget_debug = {s}
        \\
    ,
        .{
            if (state.setting_glow) "true" else "false",
            if (state.setting_native_glass) "true" else "false",
            if (state.setting_aurora) "true" else "false",
            if (state.setting_animations) "true" else "false",
            if (state.setting_dim) "true" else "false",
            frameStrengthName(state.setting_frame),
            glowIntensityName(state.setting_intensity),
            animationSpeedName(state.setting_speed),
            widgetModeName(state.setting_mode),
            mediaSourceName(state.setting_source),
            idleStyleName(state.setting_idle_style),
            transitionStyleName(state.setting_transition),
            if (state.setting_hide_text) "true" else "false",
            if (state.setting_hide_progress) "true" else "false",
            if (state.setting_show_controls) "true" else "false",
            if (state.setting_show_timestamps) "true" else "false",
            if (state.setting_artwork_border) "true" else "false",
            if (state.setting_compact_gradient) "true" else "false",
            @intFromEnum(state.setting_artwork_radius),
            @intFromEnum(state.setting_progress_thickness),
            switch (state.setting_font_scale) {
                .small => "small",
                .normal => "normal",
                .large => "large",
            },
            switch (state.setting_media_key_target) {
                .off => "off",
                .active => "active",
                .spotify => "spotify",
                .spotifast => "spotifast",
            },
            state.widget_margin_left,
            state.widget_margin_top,
            state.widget_grid_x,
            state.widget_grid_y,
            if (state.setting_debug) "true" else "false",
        },
    ) catch null;
}

/// Atomically flushes active widget geometry, themes, and feature toggles to disk.
pub fn saveWidgetSettings() void {
    var buffer: [4096]u8 = undefined;
    const text = renderConfigContent(&buffer) orelse return;

    const path = native.wallify_settings_path();
    const fd = std.posix.openatZ(std.posix.AT.FDCWD, path, .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true }, 0o644) catch return;
    defer _ = std.posix.system.close(fd);
    _ = std.posix.system.write(fd, text.ptr, text.len);
    std.log.info("settings: saved {d} bytes to {s}", .{ text.len, path });
    native.wallify_refresh_settings_ui();
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

    try std.testing.expectEqual(false, state.setting_glow);
    try std.testing.expectEqual(true, state.setting_aurora);
    try std.testing.expectEqual(state.FrameStrength.strong, state.setting_frame);
    try std.testing.expectEqual(state.GlowIntensity.high, state.setting_intensity);
    try std.testing.expectEqual(state.AnimationSpeed.fast, state.setting_speed);
    try std.testing.expectEqual(state.WidgetMode.compact, state.setting_mode);
    try std.testing.expectEqual(state.MediaSource.spotify, state.setting_source);
    try std.testing.expectEqual(state.IdleStyle.banana_cat, state.setting_idle_style);
    try std.testing.expectEqual(state.TransitionStyle.ripple, state.setting_transition);
    try std.testing.expectEqual(@as(i32, 120), state.widget_margin_left);
    try std.testing.expectEqual(@as(i32, 45), state.widget_margin_top);
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

    try std.testing.expectEqual(true, state.setting_glow);
    try std.testing.expectEqual(state.FrameStrength.subtle, state.setting_frame);
    try std.testing.expectEqual(state.GlowIntensity.low, state.setting_intensity);
    try std.testing.expectEqual(state.AnimationSpeed.slow, state.setting_speed);
    try std.testing.expectEqual(state.MediaSource.now_playing, state.setting_source);
    try std.testing.expectEqual(state.WidgetMode.expanded, state.setting_mode);
    try std.testing.expectEqual(state.IdleStyle.pixel_cat, state.setting_idle_style);
    try std.testing.expectEqual(state.TransitionStyle.vinyl, state.setting_transition);
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
