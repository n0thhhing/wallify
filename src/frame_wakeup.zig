extern fn wallify_frame_wakeup_init() callconv(.c) void;
extern fn wallify_frame_wake() callconv(.c) void;
extern fn wallify_frame_wait() callconv(.c) void;
extern fn wallify_frame_wait_for(nanoseconds: u64) callconv(.c) void;

pub fn init() void {
    wallify_frame_wakeup_init();
}
pub fn wake() void {
    wallify_frame_wake();
}
pub fn wait() void {
    wallify_frame_wait();
}
pub fn waitFor(nanoseconds: u64) void {
    wallify_frame_wait_for(nanoseconds);
}
