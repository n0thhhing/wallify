const std = @import("std");
const PlaybackClock = @import("media/playback_clock.zig").PlaybackClock;
const hitbox = @import("ui/hitbox.zig");
const layout_mod = @import("ui/layout.zig");

pub const ActionId = layout_mod.ActionId;
pub const ButtonDef = layout_mod.ButtonDef;
pub const Layout = layout_mod.Layout;

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
pub var global_duration: f64 = 0.0;
pub var global_position: f64 = 0.0;
pub var global_elapsed: f64 = 0.0;
pub var playback_clock = PlaybackClock{};
pub var global_track_id: [256]u8 = undefined;
pub var global_track_id_len: usize = 0;
pub var previous_track_id: [256]u8 = undefined;
pub var previous_track_id_len: usize = 0;
pub var global_art_crossfade_alpha: f32 = 1.0;
pub var global_anim_art_t: f64 = 0.0;
pub var play_pause_mix: f64 = 0.0;
pub var seek_expansion: f64 = 0.0;
pub var seek_velocity: f64 = 0.0;
pub var aurora_mix: f64 = 0.0;
pub var hover_amount = [_]f64{ 0, 0, 0 };
pub var spotify_closed = std.atomic.Value(bool).init(false);
pub var clock = PlaybackClock{};

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

pub const IdleStyle = enum(u8) {
    spotify = 0,
    pixel_cat = 1,
    banana_cat = 2,
    raccoon = 3,
};

pub const TransitionStyle = enum(u8) {
    default = 0,
    cinematic = 1,
    ripple = 2,
    flip = 3,
    vinyl = 4,
    glitch = 5,
};

pub const MediaSource = enum(u8) {
    now_playing = 0,
    spotify = 1,
    spotifast = 2,
    auto = 3,
};

pub const WidgetMode = layout_mod.WidgetMode;

pub const FontScale = enum(u8) {
    small = 0,
    normal = 1,
    large = 2,
};

/// Controls which source receives intercepted hardware media keys (F7/F8/F9).
/// When set to anything other than .off, Wallify installs a CGEventTap that
/// consumes the key event and routes it through its own command pipeline instead.
pub const MediaKeyTarget = enum(u8) {
    off = 0, // Don't intercept — macOS handles keys normally (Apple Music)
    active = 1, // Route through Wallify's active source (respects Auto mode)
    spotify = 2, // Always send to Spotify via AppleScript
    spotifast = 3, // Always send to Spotifast via IPC
};

pub const ArtworkRadius = enum(u8) {
    soft = 0,
    rounded = 1,
    large = 2,
};

pub const ProgressThickness = enum(u8) {
    thin = 0,
    standard = 1,
    thick = 2,
};

pub var setting_hide_text: bool = false;
pub var setting_hide_progress: bool = false;
pub var setting_show_controls: bool = true;
pub var setting_show_timestamps: bool = true;
pub var setting_artwork_border: bool = true;
pub var setting_compact_gradient: bool = true;
pub var setting_font_scale: FontScale = .normal;
pub var setting_artwork_radius: ArtworkRadius = .rounded;
pub var setting_progress_thickness: ProgressThickness = .standard;
pub var setting_media_key_target: MediaKeyTarget = .off;

pub var setting_glow: bool = true;
pub var setting_native_glass: bool = false;
pub var setting_aurora: bool = true;
pub var setting_animations: bool = true;
pub var setting_dim: bool = true;
pub var setting_frame: FrameStrength = .subtle;
pub var setting_intensity: GlowIntensity = .normal;
pub var setting_speed: AnimationSpeed = .normal;
pub var setting_idle_style: IdleStyle = .pixel_cat;
pub var setting_transition: TransitionStyle = .cinematic;
pub var setting_source: MediaSource = .now_playing;
pub var setting_debug: bool = false;
pub var idle_mix: f64 = 0.0;
pub var cat_pet_until: f64 = 0.0;
pub var cat_time: f64 = 0.0;
pub var pointer_x: f64 = Layout.compact_panel_width / 2.0;
pub var pointer_y: f64 = Layout.compact_panel_height / 2.0;

pub fn isPlaceholderTitle(title: []const u8) bool {
    return std.mem.eql(u8, title, "Not Playing") or
        std.mem.eql(u8, title, "Spotify is Closed") or
        std.mem.eql(u8, title, "Spotifast is Closed") or
        std.mem.eql(u8, title, "Spotify") or
        std.mem.eql(u8, title, "Spotifast") or
        std.mem.eql(u8, title, "No Track Playing");
}

pub fn spotifyIdle() bool {
    const now = std.time.microTimestamp() / 1_000_000.0;
    if (now < spotify_event_until) return false;
    if (spotify_closed.load(.acquire)) return true;
    const title_len = global_title_len;
    if (title_len == 0) return true;
    const has_track = !isPlaceholderTitle(global_title[0..title_len]);
    return !has_track and !global_has_artwork and global_rate == 0;
}

pub var setting_mode: WidgetMode = .expanded;
pub var mode_from: WidgetMode = .expanded;
pub var mode_mix: f64 = 1.0;
pub var mode_transition_active: bool = false;
pub var mode_start_width: f64 = Layout.expanded_panel_width;
pub var mode_start_height: f64 = Layout.expanded_panel_height;
pub var mode_target_width: f64 = Layout.expanded_panel_width;
pub var mode_target_height: f64 = Layout.expanded_panel_height;

pub fn beginModeTransition(
    new_mode: WidgetMode,
    current_width: f64,
    current_height: f64,
    animate: bool,
) void {
    const target = new_mode.dimensions();

    std.log.info("layout: mode {s} -> {s}, {d:.0}x{d:.0} -> {d:.0}x{d:.0}, animate={}", .{
        @tagName(setting_mode),
        @tagName(new_mode),
        current_width,
        current_height,
        target.width,
        target.height,
        animate,
    });
    mode_from = setting_mode;
    setting_mode = new_mode;
    mode_start_width = current_width;
    mode_start_height = current_height;
    mode_target_width = target.width;
    mode_target_height = target.height;
    mode_mix = if (animate) 0.0 else 1.0;
    mode_transition_active = animate;
}

pub fn modeAnimationFinished() void {
    std.log.info("layout: mode transition finished, mode={s}, size={d:.0}x{d:.0}", .{
        @tagName(setting_mode),
        mode_target_width,
        mode_target_height,
    });
    mode_mix = 1.0;
    mode_transition_active = false;
    mode_from = setting_mode;
    mode_start_width = mode_target_width;
    mode_start_height = mode_target_height;
}

pub var animation_time: f64 = 0;
pub var marquee_offset: f64 = 0;
pub var marquee_direction: f64 = 1;
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

// Re-export configuration engine from settings.zig
pub const settings = @import("settings.zig");
pub const loadWidgetSettings = settings.loadWidgetSettings;
pub const saveWidgetSettings = settings.saveWidgetSettings;

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

test "spotifyIdle correctly triggers for closed app or empty titles" {
    spotify_closed.store(true, .release);
    try std.testing.expect(spotifyIdle());

    spotify_closed.store(false, .release);
    global_title_len = 0;
    global_has_artwork = false;
    global_rate = 0.0;
    try std.testing.expect(spotifyIdle());

    const closed_title = "Spotify is Closed";
    @memcpy(global_title[0..closed_title.len], closed_title);
    global_title_len = closed_title.len;
    try std.testing.expect(spotifyIdle());

    const spotifast_closed_title = "Spotifast is Closed";
    @memcpy(global_title[0..spotifast_closed_title.len], spotifast_closed_title);
    global_title_len = spotifast_closed_title.len;
    try std.testing.expect(spotifyIdle());

    const active_title = "Starboy";
    @memcpy(global_title[0..active_title.len], active_title);
    global_title_len = active_title.len;
    global_rate = 1.0;
    try std.testing.expect(!spotifyIdle());

    // Paused active track remains active in player view
    global_rate = 0.0;
    global_has_artwork = true;
    try std.testing.expect(!spotifyIdle());
}
