const std = @import("std");
const PlaybackClock = @import("media/playback_clock.zig").PlaybackClock;
const hitbox = @import("ui/hitbox.zig");
const layout_mod = @import("ui/layout.zig");

pub const ActionId = layout_mod.ActionId;
pub const ButtonDef = layout_mod.ButtonDef;
pub const Layout = layout_mod.Layout;

pub const SharedState = extern struct {
    global_title: [256]u8,
    global_title_len: usize,
    global_artist: [256]u8,
    global_artist_len: usize,
    global_has_artwork: bool,
    global_rate_lock: u32,
    global_rate_lock_until: f64,
    playback_state: @import("media/playback_state.zig").PlaybackState,
    extracted_r: u8,
    extracted_g: u8,
    extracted_b: u8,
    global_is_dragging: bool,
    global_rate: f64,
    global_duration: f64,
    global_position: f64,
    global_elapsed: f64,
    playback_clock: PlaybackClock,
    global_track_id: [256]u8,
    global_track_id_len: usize,
    previous_track_id: [256]u8,
    previous_track_id_len: usize,
    global_art_crossfade_alpha: f32,
    global_anim_art_t: f64,
    play_pause_mix: f64,
    seek_expansion: f64,
    seek_velocity: f64,
    aurora_mix: f64,
    hover_amount: [3]f64,
    clock: PlaybackClock,
    setting_hide_text: bool,
    setting_hide_progress: bool,
    setting_show_controls: bool,
    setting_show_timestamps: bool,
    setting_artwork_border: bool,
    setting_compact_gradient: bool,
    setting_font_scale: FontScale,
    setting_artwork_radius: ArtworkRadius,
    setting_progress_thickness: ProgressThickness,
    setting_media_key_target: MediaKeyTarget,
    setting_glow: bool,
    setting_native_glass: bool,
    setting_aurora: bool,
    setting_animations: bool,
    setting_dim: bool,
    setting_frame: FrameStrength,
    setting_intensity: GlowIntensity,
    setting_speed: AnimationSpeed,
    setting_idle_style: IdleStyle,
    setting_transition: TransitionStyle,
    setting_source: MediaSource,
    setting_debug: bool,
    idle_mix: f64,
    cat_pet_until: f64,
    cat_time: f64,
    pointer_x: f64,
    pointer_y: f64,
    setting_mode: WidgetMode,
    mode_from: WidgetMode,
    mode_mix: f64,
    mode_transition_active: bool,
    mode_start_width: f64,
    mode_start_height: f64,
    mode_target_width: f64,
    mode_target_height: f64,
    animation_time: f64,
    marquee_offset: f64,
    marquee_direction: f64,
    widget_grid_x: u8,
    widget_grid_y: u8,
    global_panel_dragging: bool,
    widget_drag_start_mouse_x: f64,
    widget_drag_start_mouse_y: f64,
    widget_drag_start_margin_left: i32,
    widget_drag_start_margin_top: i32,
    widget_margin_left: i32,
    widget_margin_top: i32,
    panel_position_dirty: bool,
    panel_snap_active: bool,
    panel_snap_elapsed: f64,
    panel_snap_start_left: i32,
    panel_snap_start_top: i32,
    panel_snap_target_left: i32,
    panel_snap_target_top: i32,
    panel_save_after_snap: bool,
    global_hover_target: HitTarget,
    global_click_target: HitTarget,
    artwork_refresh_pending: bool,
    art_transition_until: f64,
};
extern fn wallify_widget_state() callconv(.c) *SharedState;
extern fn wallify_widget_state_size() callconv(.c) usize;
pub fn shared() *SharedState {
    return wallify_widget_state();
}

pub var layout = Layout{};
pub const render_scale = 2;

pub const spotify_closed = StateFlag{ .index = 0 };
pub const spotify_has_track = StateFlag{ .index = 1 };

pub const HitTarget = enum(i32) {
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

pub fn isPlaceholderTitle(title: []const u8) bool {
    return std.mem.eql(u8, title, "Not Playing") or
        std.mem.eql(u8, title, "Spotify is Closed") or
        std.mem.eql(u8, title, "Spotifast is Closed") or
        std.mem.eql(u8, title, "Spotify") or
        std.mem.eql(u8, title, "Spotifast") or
        std.mem.eql(u8, title, "No Track Playing");
}

pub fn spotifyIdle() bool {
    return wallify_spotify_idle();
}

pub fn beginModeTransition(
    new_mode: WidgetMode,
    current_width: f64,
    current_height: f64,
    animate: bool,
) void {
    wallify_begin_mode_transition(@intFromEnum(new_mode), current_width, current_height, animate);
}

pub fn modeAnimationFinished() void {
    wallify_finish_mode_transition();
}

// Desktop-widget grid position. A cell is one small widget plus its gap.

extern fn wallify_state_flag(index: c_int, operation: c_int, value: bool) callconv(.c) bool;
extern fn wallify_spotify_idle() callconv(.c) bool;
extern fn wallify_window_visible(visible: bool) callconv(.c) void;
extern fn wallify_request_frame() callconv(.c) void;
extern fn wallify_begin_mode_transition(mode: u8, width: f64, height: f64, animate: bool) callconv(.c) void;
extern fn wallify_finish_mode_transition() callconv(.c) void;
const StateFlag = struct {
    index: c_int,
    pub fn load(self: StateFlag, order: std.builtin.AtomicOrder) bool {
        _ = order;
        return wallify_state_flag(self.index, 0, false);
    }
    pub fn store(self: StateFlag, value: bool, order: std.builtin.AtomicOrder) void {
        _ = order;
        _ = wallify_state_flag(self.index, 1, value);
    }
    pub fn swap(self: StateFlag, value: bool, order: std.builtin.AtomicOrder) bool {
        _ = order;
        return wallify_state_flag(self.index, 1, value);
    }
};

pub const frame_requested = StateFlag{ .index = 2 };
pub const window_visible = StateFlag{ .index = 3 };

pub fn setWindowVisible(visible: bool) void {
    wallify_window_visible(visible);
}

pub fn requestFrame() void {
    wallify_request_frame();
}

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

test "spotifyIdle follows explicit Spotify track presence" {
    const old_source = shared().setting_source;
    const old_closed = spotify_closed.load(.acquire);
    const old_has_track = spotify_has_track.load(.acquire);
    defer {
        shared().setting_source = old_source;
        spotify_closed.store(old_closed, .release);
        spotify_has_track.store(old_has_track, .release);
        shared().global_title_len = 0;
        shared().global_rate = 0.0;
    }

    shared().setting_source = .spotify;
    spotify_closed.store(false, .release);
    spotify_has_track.store(false, .release);
    try std.testing.expect(spotifyIdle());

    // A real track stays active even before artwork arrives and while paused.
    spotify_has_track.store(true, .release);
    shared().global_rate = 0.0;
    shared().global_has_artwork = false;
    try std.testing.expect(!spotifyIdle());

    // Live playback and real metadata are authoritative even if the async
    // presence flag has not caught up yet.
    spotify_has_track.store(false, .release);
    shared().global_rate = 1.0;
    try std.testing.expect(!spotifyIdle());
    shared().global_rate = 0.0;
    const real_title = "Starboy";
    @memcpy(shared().global_title[0..real_title.len], real_title);
    shared().global_title_len = real_title.len;
    try std.testing.expect(!spotifyIdle());

    spotify_closed.store(true, .release);
    try std.testing.expect(spotifyIdle());

    // Idle is a Spotify-only presentation state.
    spotify_closed.store(false, .release);
    spotify_has_track.store(false, .release);
    shared().setting_source = .now_playing;
    try std.testing.expect(!spotifyIdle());
}

test "Swift shared widget state has the same ABI" {
    try std.testing.expectEqual(@sizeOf(SharedState), wallify_widget_state_size());
    const c = @cImport({
        @cInclude("widget_state.h");
    });
    inline for (std.meta.fields(SharedState)) |field| {
        try std.testing.expectEqual(@offsetOf(c.WallifyWidgetState, field.name), @offsetOf(SharedState, field.name));
    }
}
