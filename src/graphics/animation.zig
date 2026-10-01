extern fn wallify_swift_animation_loop() callconv(.c) void;
pub fn animationLoop() void {
    wallify_swift_animation_loop();
}
