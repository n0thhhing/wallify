const state = @import("../state.zig");
pub const gpu = @cImport({
    @cInclude("gpu.h");
});

pub const DrawCommand = gpu.DrawCommand;
pub extern fn wallify_present(width: f32, height: f32, cmds: [*]const DrawCommand, count: usize) void;
extern fn wallify_create(width: c_int, height: c_int, margin_left: c_int, margin_top: c_int) bool;
extern fn wallify_resize(width: c_int, height: c_int) void;
pub fn create(compact: bool, left: c_int, top: c_int) bool {
    return wallify_create(@intFromFloat(if (compact) state.Layout.compact_panel_width else state.Layout.expanded_panel_width), @intFromFloat(if (compact) state.Layout.compact_panel_height else state.Layout.expanded_panel_height), left, top);
}
pub fn resize(compact: bool) void {
    wallify_resize(@intFromFloat(if (compact) state.Layout.compact_panel_width else state.Layout.expanded_panel_width), @intFromFloat(if (compact) state.Layout.compact_panel_height else state.Layout.expanded_panel_height));
}
pub extern fn wallify_move(margin_left: c_int, margin_top: c_int) void;
pub extern fn wallify_prepare() void;
pub extern fn wallify_settings_path() [*c]const u8;
pub extern fn wallify_width() c_int;
pub extern fn wallify_height() c_int;
pub extern fn wallify_load_texture(texture_id: c_int, pixels: [*]const u32, width: usize, height: usize) void;

pub extern fn wallify_swap_textures(dest: c_int, src: c_int) void;

pub extern fn wallify_blur_texture(source: c_int, destination: c_int, art_size: f32) void;

pub extern fn wallify_profile_scene(seconds: f64) void;

pub extern fn wallify_glow_extent(art_size: f32) f32;

pub extern fn wallify_show_settings_window() void;
pub extern fn wallify_close_settings_window() void;
pub extern fn wallify_has_settings_flag() bool;

pub extern fn wallify_panel_window_number() isize;
pub extern fn wallify_panel_offsets(out_x: *f64, out_y: *f64) bool;
pub extern "c" fn wallify_refresh_settings_ui() void;

pub extern "c" fn wallify_update_glass_rect(x: f64, y: f64, w: f64, h: f64, radius: f64, active: bool) void;

/// Install or remove the CGEventTap for hardware media key interception.
/// target: 0=off, 1=active source, 2=spotify, 3=spotifast
pub extern "c" fn wallify_update_media_key_tap(target: c_int) void;
