extern "c" fn dispatch_semaphore_create(value: isize) ?*anyopaque;
extern "c" fn dispatch_semaphore_signal(dsema: *anyopaque) isize;
extern "c" fn dispatch_semaphore_wait(dsema: *anyopaque, timeout: u64) isize;

var semaphore: ?*anyopaque = null;

pub fn init() void {
    if (semaphore == null) {
        semaphore = dispatch_semaphore_create(0);
    }
}

pub fn wake() void {
    if (semaphore) |s| {
        _ = dispatch_semaphore_signal(s);
    }
}

pub fn wait() void {
    if (semaphore) |s| {
        _ = dispatch_semaphore_wait(s, ~@as(u64, 0));
    }
}
