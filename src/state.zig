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
        const radius: f64 = if (self.id == .PlayPause) Layout.play_button_hit_radius else Layout.secondary_button_hit_radius;
        return .{ .x = self.x - radius, .y = self.y - radius, .w = radius * 2, .h = radius * 2, .radius = radius };
    }
};

pub const Layout = struct {
    // Core widget geometry. Keep these here so rendering, hit testing, and
    // panel management all consume the same source of truth.
    pub const compact_content_width: f64 = 164.0;
    pub const compact_content_height: f64 = 164.0;
    pub const compact_panel_width: f64 = 180.0;
    pub const compact_panel_height: f64 = 224.0;
    pub const expanded_panel_width: f64 = 531.0;
    pub const expanded_panel_height: f64 = 199.0;
    pub const card_x_compact: f64 = 0.0;
    pub const card_x_expanded: f64 = 0.0;
    pub const card_y: f64 = 0.0;
    pub const art_x_compact: f64 = 0.0;
    pub const art_x_expanded: f64 = 16.0;
    pub const art_y_compact: f64 = 0.0;
    pub const art_y_expanded: f64 = 16.0;
    pub const art_size_expanded: f64 = 136.0;
    pub const bar_x_default: f64 = 170.0;
    pub const bar_y_default: f64 = 70.0;
    pub const button_y_default: f64 = 107.0;
    pub const mini_text_width: f64 = 132.0;
    pub const mini_title_y: f64 = 116.0;
    pub const mini_artist_y: f64 = 137.0;
    pub const card_radius: f64 = 26.0;
    pub const art_corner_radius_compact: f64 = 26.0;
    pub const art_corner_radius_expanded: f64 = 14.0;
    pub const grid_pitch: f64 = 180.0;
    pub const grid_max: u8 = 20;
    pub const margin_left_default: i32 = 14;
    pub const margin_top_default: i32 = 12;
    pub const margin_top_min: i32 = -180;
    pub const min_bar_width: f64 = 80.0;
    pub const button_spacing: f64 = 41.0;
    pub const play_button_hit_radius: f64 = 20.0;
    pub const secondary_button_hit_radius: f64 = 15.0;

    pub fn update(self: *Layout, panel_width: f64, panel_height: f64, mix: f64) void {
        self.width = panel_width;
        self.height = panel_height;
        self.art_x = art_x_compact + (art_x_expanded - art_x_compact) * mix;
        self.art_y = art_y_compact + (art_y_expanded - art_y_compact) * mix;
        self.art_size = compact_content_width + (art_size_expanded - compact_content_width) * mix;
        self.bar_x = bar_x_default;
        self.bar_y = bar_y_default;
        self.bar_w = @max(min_bar_width, panel_width - bar_x_default - 30);
        const center = self.bar_x + self.bar_w / 2;
        for (&self.buttons, 0..) |*button, i| {
            button.x = center + (@as(f64, @floatFromInt(i)) - 1) * button_spacing;
            button.y = button_y_default;
        }
    }
    pub fn card(self: Layout, mix: f64) hitbox.Rect {
        return .{ .x = card_x_compact + (card_x_expanded - card_x_compact) * mix, .y = card_y, .w = compact_content_width + (self.width - compact_content_width) * mix, .h = compact_content_height, .radius = card_radius };
    }

    width: f64 = expanded_panel_width,
    height: f64 = expanded_panel_height,

    art_x: f64 = art_x_expanded,
    art_y: f64 = art_y_expanded,
    art_size: f64 = 152.0,

    bar_x: f64 = bar_x_default,
    bar_y: f64 = bar_y_default,
    bar_w: f64 = 360.0,
    bar_h: f64 = 5.0,
    bar_hit_pad_y: f64 = 14.0,

    buttons: [3]ButtonDef = .{
        .{ .id = .Prev, .name = "Action: Previous", .x = 349.0, .y = 125.0, .size = 12.0 },
        .{ .id = .PlayPause, .name = "Action: Play/Pause", .x = 390.0, .y = 125.0, .size = 14.0 },
        .{ .id = .Next, .name = "Action: Next", .x = 431.0, .y = 125.0, .size = 12.0 },
    },
};

pub var layout = Layout{};
pub const render_scale = 2;

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
pub var pointer_x: f64 = Layout.compact_panel_width / 2.0;
pub fn spotifyIdle() bool {
    return setting_source == .spotify and spotify_closed.load(.acquire);
}
pub var setting_glow = true;
pub var setting_aurora = true;
pub var aurora_mix: f64 = 0.0;
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
pub var widget_drag_start_margin_left: i32 = Layout.margin_left_default;
pub var widget_drag_start_margin_top: i32 = Layout.margin_top_default;
pub var widget_margin_left: i32 = Layout.margin_left_default;
pub var widget_margin_top: i32 = Layout.margin_top_default;
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

pub var artwork_refresh_pending = true;
pub var art_transition_until: f64 = 0;

pub fn loadWidgetSettings() void {
    const fd = std.posix.openatZ(std.posix.AT.FDCWD, @import("platform/native.zig").wallify_settings_path(), .{ .ACCMODE = .RDONLY }, 0) catch return;
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
        if (std.mem.eql(u8, key, "widget_grid_x")) widget_grid_x = @min(Layout.grid_max, level);
        if (std.mem.eql(u8, key, "widget_grid_y")) widget_grid_y = @min(Layout.grid_max, level);
        if (std.mem.eql(u8, key, "widget_margin_left")) {
            widget_margin_left = @max(0, std.fmt.parseInt(i32, value, 10) catch Layout.margin_left_default);
            has_saved_margins = true;
        }
        if (std.mem.eql(u8, key, "widget_margin_top")) {
            widget_margin_top = @max(Layout.margin_top_min, std.fmt.parseInt(i32, value, 10) catch Layout.margin_top_default);
            has_saved_margins = true;
        }
        if (std.mem.startsWith(u8, text, "artwork_glow=")) setting_glow = !std.mem.endsWith(u8, text, "false");
        if (std.mem.startsWith(u8, text, "aurora=")) setting_aurora = !std.mem.endsWith(u8, text, "false");
        if (std.mem.startsWith(u8, text, "animations=")) setting_animations = !std.mem.endsWith(u8, text, "false");
        if (std.mem.startsWith(u8, text, "dim_paused_artwork=")) setting_dim = !std.mem.endsWith(u8, text, "false");
        if (std.mem.eql(u8, key, "idle_style")) setting_idle_style = @enumFromInt(@min(2, level));
        if (std.mem.startsWith(u8, text, "widget_debug=")) setting_debug = !std.mem.endsWith(u8, text, "false");
    }
    if (!has_saved_margins) {
        widget_margin_left = Layout.margin_left_default + @as(i32, widget_grid_x) * @as(i32, @intFromFloat(Layout.grid_pitch));
        widget_margin_top = Layout.margin_top_default + @as(i32, widget_grid_y) * @as(i32, @intFromFloat(Layout.grid_pitch));
    }
}

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
            if (setting_glow) "true" else "false",
            if (setting_aurora) "true" else "false",
            if (setting_animations) "true" else "false",
            if (setting_dim) "true" else "false",
            if (setting_debug) "true" else "false",
            @intFromEnum(setting_idle_style),
            @intFromEnum(setting_frame),
            @intFromEnum(setting_intensity),
            @intFromEnum(setting_speed),
            @intFromEnum(setting_source),
            @intFromEnum(setting_mode),
            widget_grid_x,
            widget_grid_y,
            widget_margin_left,
            widget_margin_top,
        },
    ) catch return;
    const fd = std.posix.openatZ(std.posix.AT.FDCWD, @import("platform/native.zig").wallify_settings_path(), .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true }, 0o644) catch return;
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

test "AnimationSpeed multiplier paces framerate transitions" {
    try std.testing.expectEqual(@as(f64, 0.7), AnimationSpeed.slow.multiplier());
    try std.testing.expectEqual(@as(f64, 1.0), AnimationSpeed.normal.multiplier());
    try std.testing.expectEqual(@as(f64, 1.4), AnimationSpeed.fast.multiplier());
}
