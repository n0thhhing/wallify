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
pub var setting_glow = true;
pub var setting_animations = true;
pub var setting_dim = true;
pub var setting_frame: u8 = 1;
pub var setting_intensity: u8 = 1;
pub var setting_speed: u8 = 1;
pub var setting_source: u8 = 0; // 0 = Now Playing, 1 = Spotify
// 0 = Compact, 1 = Expanded. Expanded preserves the original panel layout.
pub var setting_mode: u8 = 1;
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

pub var global_hover_state: [32]u8 = undefined;
pub var global_hover_state_len: usize = 0;
pub var global_click_state: [32]u8 = undefined;
pub var global_click_state_len: usize = 0;

pub var frame_requested = std.atomic.Value(bool).init(true);

pub fn requestFrame() void {
    frame_requested.store(true, .release);
}

pub var previous_canvas_width: usize = 0;
pub var artwork_refresh_pending = true;
pub var cached_art: []u8 = &.{};
pub var previous_art: []u8 = &.{};
pub var art_transition_until: f64 = 0;

extern "c" fn fopen(filename: [*c]const u8, mode: [*c]const u8) ?*anyopaque;
extern "c" fn fwrite(ptr: *const anyopaque, size: usize, nmemb: usize, stream: *anyopaque) usize;
extern "c" fn fclose(stream: *anyopaque) c_int;
extern "c" fn fgets(buffer: [*]u8, size: c_int, stream: *anyopaque) ?[*]u8;

pub fn loadWidgetSettings() void {
    const file = fopen("widget-settings.conf", "r") orelse return;
    defer _ = fclose(file);
    var line: [128]u8 = undefined;
    var has_saved_margins = false;
    while (fgets(&line, line.len, file) != null) {
        const text = std.mem.trim(u8, std.mem.sliceTo(&line, 0), " \r\n");
        var pair = std.mem.splitScalar(u8, text, '=');
        const key = pair.next() orelse "";
        const value = pair.next() orelse "";
        const level = std.fmt.parseInt(u8, value, 10) catch 1;
        if (std.mem.eql(u8, key, "frame_strength")) setting_frame = @min(2, level);
        if (std.mem.eql(u8, key, "glow_intensity")) setting_intensity = @min(2, level);
        if (std.mem.eql(u8, key, "animation_speed")) setting_speed = @min(2, level);
        if (std.mem.eql(u8, key, "media_source")) setting_source = @min(1, level);
        if (std.mem.eql(u8, key, "widget_mode")) setting_mode = @min(1, level);
        if (std.mem.eql(u8, key, "widget_grid_x")) widget_grid_x = @min(20, level);
        if (std.mem.eql(u8, key, "widget_grid_y")) widget_grid_y = @min(20, level);
        if (std.mem.eql(u8, key, "widget_margin_left")) { widget_margin_left = @max(0, std.fmt.parseInt(i32, value, 10) catch 14); has_saved_margins = true; }
        if (std.mem.eql(u8, key, "widget_margin_top")) { widget_margin_top = @max(-180, std.fmt.parseInt(i32, value, 10) catch 12); has_saved_margins = true; }
        if (std.mem.startsWith(u8, text, "artwork_glow=")) setting_glow = !std.mem.endsWith(u8, text, "false");
        if (std.mem.startsWith(u8, text, "animations=")) setting_animations = !std.mem.endsWith(u8, text, "false");
        if (std.mem.startsWith(u8, text, "dim_paused_artwork=")) setting_dim = !std.mem.endsWith(u8, text, "false");
    }
    if (!has_saved_margins) {
        widget_margin_left = 14 + @as(i32, widget_grid_x) * 180;
        widget_margin_top = 12 + @as(i32, widget_grid_y) * 180;
    }
}

pub fn saveWidgetSettings() void {
    var buffer: [512]u8 = undefined;
    const text = std.fmt.bufPrint(&buffer, "# Wallify widget preferences; also editable from the right-click menu.\nartwork_glow={s}\nanimations={s}\ndim_paused_artwork={s}\nframe_strength={d}\nglow_intensity={d}\nanimation_speed={d}\nmedia_source={d}\nwidget_mode={d}\nwidget_grid_x={d}\nwidget_grid_y={d}\nwidget_margin_left={d}\nwidget_margin_top={d}\n", .{ if (setting_glow) "true" else "false", if (setting_animations) "true" else "false", if (setting_dim) "true" else "false", setting_frame, setting_intensity, setting_speed, setting_source, setting_mode, widget_grid_x, widget_grid_y, widget_margin_left, widget_margin_top }) catch return;
    const file = fopen("widget-settings.conf", "w") orelse return;
    _ = fwrite(text.ptr, 1, text.len, file);
    _ = fclose(file);
}
pub var current_image_id: u32 = 1;
