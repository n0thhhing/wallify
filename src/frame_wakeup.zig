const std = @import("std");

extern "c" fn dispatch_semaphore_create(value: isize) ?*anyopaque;
extern "c" fn dispatch_semaphore_signal(dsema: *anyopaque) isize;
extern "c" fn dispatch_semaphore_wait(dsema: *anyopaque, timeout: u64) isize;
extern "c" fn dispatch_time(when: u64, delta: i64) u64;

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
    waitUntil(~@as(u64, 0));
}

pub fn waitFor(nanoseconds: u64) void {
    waitUntil(dispatch_time(0, @intCast(nanoseconds)));
}

fn waitUntil(deadline: u64) void {
    if (semaphore) |s| {
        if (dispatch_semaphore_wait(s, deadline) == 0) {
            pending.store(false, .release);
        }
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

test "timed frame waits preserve wakeups after timeout" {
    init();
    waitFor(1);
    wake();
    waitFor(1_000_000);
    try std.testing.expect(!pending.load(.acquire));
    try std.testing.expect(dispatch_semaphore_wait(semaphore.?, 0) != 0);
}
