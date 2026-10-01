const state = @import("../state.zig");
const native = @import("../platform/native.zig");
extern fn wallify_scene_artwork_dirty() callconv(.c) void;
extern fn wallify_scene_clear_artwork() callconv(.c) void;
extern fn wallify_swift_draw_frame() callconv(.c) void;
pub fn extractColor() void {
    wallify_scene_artwork_dirty();
}
pub fn clearArtwork() void {
    wallify_scene_clear_artwork();
}
pub fn drawUIFrame() void {
    // Borrowed layout remains for the Zig Inspector and animation adapter.
    state.layout.update(@floatFromInt(native.wallify_width()), @floatFromInt(native.wallify_height()), state.shared().mode_from, state.shared().setting_mode, state.shared().mode_mix);
    wallify_swift_draw_frame();
}
