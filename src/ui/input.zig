const state = @import("../state.zig");
const hitbox = @import("hitbox.zig");

const InputGeometry = extern struct {
    card: hitbox.Rect,
    art: hitbox.Rect,
    bar: hitbox.Rect,
    buttons: [3]hitbox.Rect,
    bar_x: f64,
    bar_width: f64,
    controls_visible: bool,
    progress_visible: bool,
};
extern fn wallify_native_pointer(x: f64, y: f64, kind: c_int, geometry: *const InputGeometry) callconv(.c) void;

// Rendering still owns the geometry cache; all interaction policy is Swift.
pub export fn wallify_pointer(x: f64, y: f64, kind: c_int) void {
    const layout = state.layout;
    const geometry = InputGeometry{
        .card = layout.card(state.shared().mode_mix),
        .art = .{ .x = layout.art_x, .y = layout.art_y, .w = layout.art_size, .h = layout.art_size, .radius = 14 },
        .bar = .{ .x = layout.bar_x, .y = layout.bar_y - layout.bar_hit_pad_y, .w = layout.bar_w, .h = layout.bar_h + 2 * layout.bar_hit_pad_y, .radius = 3 },
        .buttons = .{ layout.buttons[0].bounds(), layout.buttons[1].bounds(), layout.buttons[2].bounds() },
        .bar_x = layout.bar_x,
        .bar_width = layout.bar_w,
        .controls_visible = layout.controlsVisible(state.shared().setting_show_controls),
        .progress_visible = layout.progressVisible(state.shared().setting_hide_progress),
    };
    wallify_native_pointer(x, y, kind, &geometry);
}
