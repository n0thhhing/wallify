const std = @import("std");
const PlaybackClock = @import("media/playback_clock.zig").PlaybackClock;
const hitbox = @import("ui/hitbox.zig");

pub const ActionId = enum { PlayPause, Prev, Next };

pub const ButtonDef = struct {
    id: ActionId,
    name: []const u8,
    x: f64,
    y: f64,
    size: usize,

    pub fn bounds(self: ButtonDef) hitbox.Rect {
        const radius: f64 = if (self.id == .PlayPause) 20 else 15;
        return .{ .x = self.x - radius, .y = self.y - radius, .w = radius * 2, .h = radius * 2, .radius = radius };
    }
};

pub const Layout = struct {
    width: f64 = 600.0,
    height: f64 = 200.0,
    cells_x: f64 = 70.0,
    cells_y: f64 = 12.0,

    art_x: f64 = 24.0,
    art_y: f64 = 24.0,
    art_size: f64 = 152.0,

    bar_x: f64 = 210.0,
    bar_y: f64 = 105.0,
    bar_w: f64 = 360.0,
    bar_h: f64 = 5.0,
    bar_hit_pad_y: f64 = 14.0,

    buttons: [3]ButtonDef = .{
        .{ .id = .Prev, .name = "Action: Previous", .x = 349.0, .y = 160.0, .size = 12.0 },
        .{ .id = .PlayPause, .name = "Action: Play/Pause", .x = 390.0, .y = 160.0, .size = 14.0 },
        .{ .id = .Next, .name = "Action: Next", .x = 431.0, .y = 160.0, .size = 12.0 },
    },
};

pub var layout = Layout{};
pub var desktop_mode = false;
pub var pixel_mouse = false;
pub const render_scale = 3;

pub var original_termios: std.posix.termios = undefined;

pub var global_title: [256]u8 = undefined;
pub var global_title_len: usize = 0;
pub var global_artist: [256]u8 = undefined;
pub var global_artist_len: usize = 0;
pub var global_has_artwork: bool = false;
pub var global_rate_lock: u32 = 0;
pub var global_rate_lock_until: f64 = 0;
pub var playback_state = @import("media/playback_state.zig").PlaybackState{};
pub var extracted_r: u8 = 180;
pub var extracted_g: u8 = 180;
pub var extracted_b: u8 = 180;
pub var global_is_dragging: bool = false;
pub var global_rate: f64 = 0.0;
pub var global_elapsed: f64 = 0.0;
pub var playback_clock = PlaybackClock{};
pub var play_pause_mix: f64 = 0;
pub var seek_expansion: f64 = 0;
pub var seek_velocity: f64 = 0;
pub var spotify_event_until: f64 = 0;
pub var hover_amount = [_]f64{ 0, 0, 0 };
pub var global_duration: f64 = 0.0;
pub var global_anim_art_t: f64 = 1.0;
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

pub const MediaSource = enum(u8) {
    now_playing = 0,
    spotify = 1,
};

pub const WidgetMode = enum(u8) {
    compact = 0,
    expanded = 1,
};

pub const IdleStyle = enum(u8) {
    spotify = 0,
    pixel_cat = 1,
    banana_cat = 2,
};

pub const HitTarget = enum {
    none,
    grid_background,
    frame_bounds,
    art,
    bar,
    button_prev,
    button_play_pause,
    button_next,

    pub fn fromActionId(id: ActionId) HitTarget {
        return switch (id) {
            .PlayPause => .button_play_pause,
            .Prev => .button_prev,
            .Next => .button_next,
        };
    }

    pub fn toActionId(self: HitTarget) ?ActionId {
        return switch (self) {
            .button_play_pause => .PlayPause,
            .button_prev => .Prev,
            .button_next => .Next,
            else => null,
        };
    }

    pub fn label(self: HitTarget) []const u8 {
        return switch (self) {
            .none => "None",
            .grid_background => "Grid Background",
            .frame_bounds => "Frame Bounds",
            .art => "Geometry: Art",
            .bar => "Geometry: Bar",
            .button_prev => "Action: Previous",
            .button_play_pause => "Action: Play/Pause",
            .button_next => "Action: Next",
        };
    }
};

pub var setting_idle_style: IdleStyle = .spotify;
pub var spotify_closed = std.atomic.Value(bool).init(false);
pub var idle_mix: f64 = 0;
pub var cat_time: f64 = 0;
pub var cat_pet_until: f64 = 0;
pub var pointer_x: f64 = 90;
pub fn spotifyIdle() bool {
    return setting_source == .spotify and spotify_closed.load(.acquire);
}
pub var setting_glow = true;
pub var setting_animations = true;
pub var setting_dim = true;
// Diagnostics are opt-in, including when preferences are missing.
pub var setting_debug = false;
pub var setting_frame: FrameStrength = .subtle;
pub var setting_intensity: GlowIntensity = .normal;
pub var setting_speed: AnimationSpeed = .normal;
pub var setting_source: MediaSource = .now_playing;
// Compact or Expanded. Expanded preserves the original panel layout.
pub var setting_mode: WidgetMode = .expanded;
pub var animation_time: f64 = 0;
pub var marquee_offset: f64 = 0;
pub var marquee_direction: f64 = 1;
pub var panel_resize_after_compact: bool = false;
// Interpolates compact (0) to expanded (1), independently of the saved target.
pub var mode_mix: f64 = 1;
// Desktop-widget grid position. A cell is one small widget plus its gap.
pub var widget_grid_x: u8 = 0;
pub var widget_grid_y: u8 = 0;
pub var global_panel_dragging = false;
pub var widget_drag_start_mouse_x: f64 = 0;
pub var widget_drag_start_mouse_y: f64 = 0;
pub var widget_drag_start_margin_left: i32 = 14;
pub var widget_drag_start_margin_top: i32 = 12;
pub var widget_margin_left: i32 = 14;
pub var widget_margin_top: i32 = 12;
pub var panel_position_dirty = false;
pub var panel_snap_active = false;
pub var panel_snap_elapsed: f64 = 0;
pub var panel_snap_start_left: i32 = 0;
pub var panel_snap_start_top: i32 = 0;
pub var panel_snap_target_left: i32 = 0;
pub var panel_snap_target_top: i32 = 0;
pub var panel_save_after_snap = false;

pub var global_hover_target: HitTarget = .none;
pub var global_click_target: HitTarget = .none;

pub var frame_requested = std.atomic.Value(bool).init(true);

pub fn requestFrame() void {
    frame_requested.store(true, .release);
}

pub var previous_canvas_width: usize = 0;
pub var artwork_refresh_pending = true;
pub var cached_art: []u8 = &.{};
pub var previous_art: []u8 = &.{};
pub var art_transition_until: f64 = 0;

pub fn loadWidgetSettings() void {
    const fd = std.posix.openatZ(std.posix.AT.FDCWD, "widget-settings.conf", .{ .ACCMODE = .RDONLY }, 0) catch return;
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
        if (std.mem.eql(u8, key, "frame_strength")) setting_frame = @enumFromInt(@min(2, level));
        if (std.mem.eql(u8, key, "glow_intensity")) setting_intensity = @enumFromInt(@min(2, level));
        if (std.mem.eql(u8, key, "animation_speed")) setting_speed = @enumFromInt(@min(2, level));
        if (std.mem.eql(u8, key, "media_source")) setting_source = @enumFromInt(@min(1, level));
        if (std.mem.eql(u8, key, "widget_mode")) setting_mode = @enumFromInt(@min(1, level));
        if (std.mem.eql(u8, key, "widget_grid_x")) widget_grid_x = @min(20, level);
        if (std.mem.eql(u8, key, "widget_grid_y")) widget_grid_y = @min(20, level);
        if (std.mem.eql(u8, key, "widget_margin_left")) {
            widget_margin_left = @max(0, std.fmt.parseInt(i32, value, 10) catch 14);
            has_saved_margins = true;
        }
        if (std.mem.eql(u8, key, "widget_margin_top")) {
            widget_margin_top = @max(-180, std.fmt.parseInt(i32, value, 10) catch 12);
            has_saved_margins = true;
        }
        if (std.mem.startsWith(u8, text, "artwork_glow=")) setting_glow = !std.mem.endsWith(u8, text, "false");
        if (std.mem.startsWith(u8, text, "animations=")) setting_animations = !std.mem.endsWith(u8, text, "false");
        if (std.mem.startsWith(u8, text, "dim_paused_artwork=")) setting_dim = !std.mem.endsWith(u8, text, "false");
        if (std.mem.eql(u8, key, "idle_style")) setting_idle_style = @enumFromInt(@min(2, level));
        if (std.mem.startsWith(u8, text, "widget_debug=")) setting_debug = !std.mem.endsWith(u8, text, "false");
    }
    if (!has_saved_margins) {
        widget_margin_left = 14 + @as(i32, widget_grid_x) * 180;
        widget_margin_top = 12 + @as(i32, widget_grid_y) * 180;
    }
}

pub fn saveWidgetSettings() void {
    var buffer: [512]u8 = undefined;
    const text = std.fmt.bufPrint(&buffer, "# Wallify widget preferences; also editable from the right-click menu.\nartwork_glow={s}\nanimations={s}\ndim_paused_artwork={s}\nwidget_debug={s}\nidle_style={d}\nframe_strength={d}\nglow_intensity={d}\nanimation_speed={d}\nmedia_source={d}\nwidget_mode={d}\nwidget_grid_x={d}\nwidget_grid_y={d}\nwidget_margin_left={d}\nwidget_margin_top={d}\n", .{ if (setting_glow) "true" else "false", if (setting_animations) "true" else "false", if (setting_dim) "true" else "false", if (setting_debug) "true" else "false", @intFromEnum(setting_idle_style), @intFromEnum(setting_frame), @intFromEnum(setting_intensity), @intFromEnum(setting_speed), @intFromEnum(setting_source), @intFromEnum(setting_mode), widget_grid_x, widget_grid_y, widget_margin_left, widget_margin_top }) catch return;
    const fd = std.posix.openatZ(std.posix.AT.FDCWD, "widget-settings.conf", .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true }, 0o644) catch return;
    defer _ = std.posix.system.close(fd);
    _ = std.posix.system.write(fd, text.ptr, text.len);
}
pub var current_image_id: u32 = 1;

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

test "AnimationSpeed multiplier paces framerate transitions" {
    try std.testing.expectEqual(@as(f64, 0.7), AnimationSpeed.slow.multiplier());
    try std.testing.expectEqual(@as(f64, 1.0), AnimationSpeed.normal.multiplier());
    try std.testing.expectEqual(@as(f64, 1.4), AnimationSpeed.fast.multiplier());
}

test "HitTarget fromActionId and toActionId are consistent" {
    const actions = [_]ActionId{ .PlayPause, .Prev, .Next };
    for (actions) |action| {
        const target = HitTarget.fromActionId(action);
        try std.testing.expectEqual(action, target.toActionId().?);
    }
    try std.testing.expect(HitTarget.none.toActionId() == null);
    try std.testing.expect(HitTarget.art.toActionId() == null);
    try std.testing.expect(HitTarget.bar.toActionId() == null);
}

test "ButtonDef bounds calculates centering and radius" {
    const play_btn = ButtonDef{ .id = .PlayPause, .name = "Action: Play/Pause", .x = 100, .y = 100, .size = 14 };
    const play_b = play_btn.bounds();
    try std.testing.expectEqual(@as(f64, 80), play_b.x);
    try std.testing.expectEqual(@as(f64, 80), play_b.y);
    try std.testing.expectEqual(@as(f64, 40), play_b.w);
    try std.testing.expectEqual(@as(f64, 40), play_b.h);
    try std.testing.expectEqual(@as(f64, 20), play_b.radius);

    const prev_btn = ButtonDef{ .id = .Prev, .name = "Action: Previous", .x = 100, .y = 100, .size = 12 };
    const prev_b = prev_btn.bounds();
    try std.testing.expectEqual(@as(f64, 85), prev_b.x);
    try std.testing.expectEqual(@as(f64, 85), prev_b.y);
    try std.testing.expectEqual(@as(f64, 30), prev_b.w);
    try std.testing.expectEqual(@as(f64, 30), prev_b.h);
    try std.testing.expectEqual(@as(f64, 15), prev_b.radius);
}

test "HitTarget labels provide descriptive names" {
    try std.testing.expectEqualStrings("None", HitTarget.none.label());
    try std.testing.expectEqualStrings("Geometry: Art", HitTarget.art.label());
    try std.testing.expectEqualStrings("Geometry: Bar", HitTarget.bar.label());
    try std.testing.expectEqualStrings("Action: Play/Pause", HitTarget.button_play_pause.label());
}

test "idle tile requires Spotify-only source and a closed application" {
    const old_source = setting_source;
    const old_closed = spotify_closed.load(.acquire);
    defer {
        setting_source = old_source;
        spotify_closed.store(old_closed, .release);
    }
    setting_source = .now_playing;
    spotify_closed.store(true, .release);
    try std.testing.expect(!spotifyIdle());
    setting_source = .spotify;
    try std.testing.expect(spotifyIdle());
    spotify_closed.store(false, .release);
    try std.testing.expect(!spotifyIdle());
}

test "IdleStyle enum values match serialization integers" {
    try std.testing.expectEqual(@as(u8, 0), @intFromEnum(IdleStyle.spotify));
    try std.testing.expectEqual(@as(u8, 1), @intFromEnum(IdleStyle.pixel_cat));
    try std.testing.expectEqual(@as(u8, 2), @intFromEnum(IdleStyle.banana_cat));
}
