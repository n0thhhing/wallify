const std = @import("std");

extern "c" fn dispatch_semaphore_create(value: isize) ?*anyopaque;
extern "c" fn dispatch_semaphore_signal(dsema: *anyopaque) isize;
extern "c" fn dispatch_semaphore_wait(dsema: *anyopaque, timeout: u64) isize;

var semaphore: ?*anyopaque = null;
var pending = std.atomic.Value(bool).init(false);

pub fn init() void {
    if (semaphore == null) {
        semaphore = dispatch_semaphore_create(0);
    }
}

pub fn wake() void {
    if (semaphore) |s| {
        // A frame request is a notification, not a count of frames to render.
        // Keep at most one token while the renderer is already animating.
        if (!pending.swap(true, .acq_rel)) {
            _ = dispatch_semaphore_signal(s);
        }
    }
}

pub fn wait() void {
    if (semaphore) |s| {
        _ = dispatch_semaphore_wait(s, ~@as(u64, 0));
        pending.store(false, .release);
    }
}

test "frame wakeups coalesce and can be signaled again after consumption" {
    init();
    const s = semaphore orelse return error.SemaphoreUnavailable;
    for (0..1000) |_| wake();
    wait();
    try std.testing.expect(dispatch_semaphore_wait(s, 0) != 0);
    wake();
    wait();
    try std.testing.expect(dispatch_semaphore_wait(s, 0) != 0);
}
