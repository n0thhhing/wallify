pub const DrawCommand = extern struct {
    texture_id: c_int,
    dx: f32,
    dy: f32,
    dw: f32,
    dh: f32,
    sx: f32,
    sy: f32,
    sw: f32,
    sh: f32,
    alpha: f32,
};

pub extern fn wallify_present(pixels: [*]const u32, width: usize, height: usize, cmds: [*]const DrawCommand, cmd_count: usize) void;
pub extern fn wallify_create(compact: bool, margin_left: c_int, margin_top: c_int) bool;
pub extern fn wallify_resize(compact: bool) void;
pub extern fn wallify_move(margin_left: c_int, margin_top: c_int) void;
pub extern fn wallify_prepare() void;
pub extern fn wallify_settings_path() [*c]const u8;
pub extern fn wallify_width() c_int;
pub extern fn wallify_height() c_int;
pub extern fn wallify_load_texture(texture_id: c_int, pixels: [*]const u32, width: usize, height: usize) void;

/// Called by native.m whenever the panel is created or resized so that
/// drawUIFrame always has the true logical-point panel dimensions.
pub export fn wallify_set_panel_size(w: c_int, h: c_int) callconv(.c) void {
    @import("../state.zig").panel_pixel_width = w;
    @import("../state.zig").panel_pixel_height = h;
}
pub extern fn wallify_swap_textures(dest: c_int, src: c_int) void;
